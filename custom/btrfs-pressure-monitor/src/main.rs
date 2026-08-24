use std::{
    collections::BTreeMap,
    env,
    fmt::{self, Write as _},
    fs,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

const GIB: u64 = 1024 * 1024 * 1024;
const MOUNT: &str = "/";
const WARNING_BACKOFF_SECONDS: [u64; 5] =
    [60 * 60, 2 * 60 * 60, 4 * 60 * 60, 8 * 60 * 60, 24 * 60 * 60];

fn main() {
    if let Err(error) = run() {
        eprintln!("error={}", one_line(&error));
        std::process::exit(2);
    }
}

fn run() -> Result<(), String> {
    let no_notify = parse_arguments()?;
    let measured = collect_metrics(MOUNT);
    let (metrics, assessment) = match measured {
        Ok(metrics) => {
            let assessment = assess(&metrics, &Thresholds::default());
            (Some(metrics), assessment)
        }
        Err(error) => {
            eprintln!("measurement_error={}", one_line(&error));
            (
                None,
                Assessment::new(Status::Critical, ["measurement_failure"]),
            )
        }
    };

    let summary = summary(assessment.status, &assessment.reasons, metrics.as_ref());
    println!("{summary}");

    if !no_notify {
        handle_notification(&assessment, metrics.as_ref());
    }
    Ok(())
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Status {
    Ok,
    Warning,
    Critical,
}

impl Status {
    fn as_str(self) -> &'static str {
        match self {
            Self::Ok => "ok",
            Self::Warning => "warning",
            Self::Critical => "critical",
        }
    }
}

impl fmt::Display for Status {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

#[derive(Clone, Debug, PartialEq)]
struct Metrics {
    filesystem_size: u64,
    statfs_available: u64,
    btrfs_free_estimated: u64,
    btrfs_free_minimum: u64,
    device_unallocated: u64,
    device_missing: u64,
    metadata_total: u64,
    metadata_used: u64,
    global_reserve_total: u64,
    global_reserve_used: u64,
    device_errors: BTreeMap<String, u64>,
}

impl Metrics {
    fn conservative_free(&self) -> u64 {
        self.statfs_available.min(self.btrfs_free_minimum)
    }

    fn free_percent(&self) -> f64 {
        percent(self.conservative_free(), self.filesystem_size)
    }

    fn metadata_percent(&self) -> f64 {
        percent(self.metadata_used, self.metadata_total)
    }

    fn device_error_count(&self) -> u64 {
        self.device_errors.values().copied().sum()
    }
}

#[derive(Clone, Debug)]
struct Thresholds {
    warning_free_percent: f64,
    critical_free_percent: f64,
    critical_metadata_percent: f64,
    warning_combined_metadata_percent: f64,
    warning_unallocated: u64,
    critical_combined_metadata_percent: f64,
    critical_unallocated: u64,
}

impl Default for Thresholds {
    fn default() -> Self {
        Self {
            warning_free_percent: 10.0,
            critical_free_percent: 5.0,
            critical_metadata_percent: 95.0,
            warning_combined_metadata_percent: 80.0,
            warning_unallocated: 24 * GIB,
            critical_combined_metadata_percent: 90.0,
            critical_unallocated: 12 * GIB,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct Assessment {
    status: Status,
    reasons: Vec<String>,
}

impl Assessment {
    fn new<const N: usize>(status: Status, reasons: [&str; N]) -> Self {
        Self {
            status,
            reasons: reasons.into_iter().map(str::to_owned).collect(),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct WarningBackoffState {
    fingerprint: String,
    last_notified: u64,
    notifications: u32,
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum WarningNotificationDecision {
    Notify(WarningBackoffState),
    Suppress { remaining_seconds: u64 },
}

fn handle_notification(assessment: &Assessment, metrics: Option<&Metrics>) {
    let state_path = warning_state_path();
    match assessment.status {
        Status::Ok => clear_warning_state(state_path.as_deref()),
        Status::Critical => {
            clear_warning_state(state_path.as_deref());
            let (title, body) = notification_text(assessment.status, &assessment.reasons, metrics);
            send_notification(assessment.status, &title, &body);
        }
        Status::Warning => {
            send_warning_with_backoff(state_path.as_deref(), assessment, metrics);
        }
    }
}

fn send_warning_with_backoff(
    state_path: Option<&Path>,
    assessment: &Assessment,
    metrics: Option<&Metrics>,
) {
    let Some(state_path) = state_path else {
        eprintln!("notification_backoff=disabled error=state_directory_unavailable");
        let (title, body) = notification_text(assessment.status, &assessment.reasons, metrics);
        send_notification(assessment.status, &title, &body);
        return;
    };
    let now = match unix_timestamp() {
        Ok(now) => now,
        Err(error) => {
            eprintln!("notification_backoff=disabled error={}", one_line(&error));
            let (title, body) = notification_text(assessment.status, &assessment.reasons, metrics);
            send_notification(assessment.status, &title, &body);
            return;
        }
    };
    let previous = match load_warning_state(state_path) {
        Ok(state) => state,
        Err(error) => {
            eprintln!("notification_backoff=reset error={}", one_line(&error));
            None
        }
    };
    let fingerprint = assessment.reasons.join(",");
    match warning_notification_decision(previous.as_ref(), &fingerprint, now) {
        WarningNotificationDecision::Suppress { remaining_seconds } => {
            eprintln!("notification=suppressed backoff_remaining_seconds={remaining_seconds}");
        }
        WarningNotificationDecision::Notify(next_state) => {
            let (title, body) = notification_text(assessment.status, &assessment.reasons, metrics);
            if send_notification(assessment.status, &title, &body) {
                match save_warning_state(state_path, &next_state) {
                    Ok(()) => {}
                    Err(error) => {
                        eprintln!("notification_backoff=unsaved error={}", one_line(&error));
                    }
                }
            }
        }
    }
}

fn warning_notification_decision(
    previous: Option<&WarningBackoffState>,
    fingerprint: &str,
    now: u64,
) -> WarningNotificationDecision {
    let Some(previous) = previous.filter(|state| state.fingerprint == fingerprint) else {
        return WarningNotificationDecision::Notify(WarningBackoffState {
            fingerprint: fingerprint.to_owned(),
            last_notified: now,
            notifications: 1,
        });
    };
    let delay_index = previous.notifications.saturating_sub(1) as usize;
    let delay = WARNING_BACKOFF_SECONDS[delay_index.min(WARNING_BACKOFF_SECONDS.len() - 1)];
    let Some(elapsed) = now.checked_sub(previous.last_notified) else {
        return WarningNotificationDecision::Notify(WarningBackoffState {
            fingerprint: fingerprint.to_owned(),
            last_notified: now,
            notifications: previous.notifications.saturating_add(1),
        });
    };
    if elapsed < delay {
        return WarningNotificationDecision::Suppress {
            remaining_seconds: delay - elapsed,
        };
    }
    WarningNotificationDecision::Notify(WarningBackoffState {
        fingerprint: fingerprint.to_owned(),
        last_notified: now,
        notifications: previous.notifications.saturating_add(1),
    })
}

fn warning_state_path() -> Option<PathBuf> {
    env::var_os("STATE_DIRECTORY")
        .and_then(|directories| env::split_paths(&directories).next())
        .map(|directory| directory.join("warning-backoff"))
}

fn unix_timestamp() -> Result<u64, String> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .map_err(|error| format!("reading system time: {error}"))
}

fn load_warning_state(path: &Path) -> Result<Option<WarningBackoffState>, String> {
    let text = match fs::read_to_string(path) {
        Ok(text) => text,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(format!("reading {}: {error}", path.display())),
    };
    parse_warning_state(&text).map(Some)
}

fn parse_warning_state(text: &str) -> Result<WarningBackoffState, String> {
    let mut lines = text.lines();
    if lines.next() != Some("version=1") {
        return Err("unsupported warning backoff state version".into());
    }
    let notifications = state_value(lines.next(), "notifications=")?
        .parse::<u32>()
        .map_err(|_| "invalid warning backoff notification count")?;
    if notifications == 0 {
        return Err("invalid zero warning backoff notification count".into());
    }
    let last_notified = state_value(lines.next(), "last_notified=")?
        .parse::<u64>()
        .map_err(|_| "invalid warning backoff timestamp")?;
    let fingerprint = state_value(lines.next(), "fingerprint=")?;
    if fingerprint.is_empty() {
        return Err("empty warning backoff fingerprint".into());
    }
    if lines.any(|line| !line.is_empty()) {
        return Err("unexpected warning backoff state fields".into());
    }
    Ok(WarningBackoffState {
        fingerprint: fingerprint.to_owned(),
        last_notified,
        notifications,
    })
}

fn state_value<'a>(line: Option<&'a str>, prefix: &str) -> Result<&'a str, String> {
    line.and_then(|line| line.strip_prefix(prefix))
        .ok_or_else(|| format!("missing warning backoff field {prefix:?}"))
}

fn save_warning_state(path: &Path, state: &WarningBackoffState) -> Result<(), String> {
    let text = format!(
        "version=1\nnotifications={}\nlast_notified={}\nfingerprint={}\n",
        state.notifications, state.last_notified, state.fingerprint
    );
    let temporary = path.with_extension(format!("tmp-{}", std::process::id()));
    fs::write(&temporary, text)
        .map_err(|error| format!("writing {}: {error}", temporary.display()))?;
    if let Err(error) = fs::rename(&temporary, path) {
        let _ = fs::remove_file(&temporary);
        return Err(format!("replacing {}: {error}", path.display()));
    }
    Ok(())
}

fn clear_warning_state(path: Option<&Path>) {
    let Some(path) = path else {
        return;
    };
    match fs::remove_file(path) {
        Ok(()) => {}
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => {
            eprintln!(
                "notification_backoff=uncleared error={}",
                one_line(&error.to_string())
            );
        }
    }
}

fn collect_metrics(mount: &str) -> Result<Metrics, String> {
    let usage = run_command(
        "btrfs",
        &["filesystem", "usage", "-b", mount],
        Duration::from_secs(30),
        &[],
    )?;
    let filesystem_df = run_command(
        "btrfs",
        &["filesystem", "df", "-b", mount],
        Duration::from_secs(30),
        &[],
    )?;
    let device_stats = run_command(
        "btrfs",
        &["device", "stats", mount],
        Duration::from_secs(30),
        &[],
    )?;

    let usage = parse_filesystem_usage(&usage)?;
    let (metadata_total, metadata_used) = parse_filesystem_df(&filesystem_df)?;
    if usage.device_size == 0 {
        return Err("btrfs reported an empty filesystem".into());
    }
    if metadata_total == 0 || metadata_used > metadata_total {
        return Err("btrfs reported inconsistent metadata usage".into());
    }
    if usage.statfs_available > usage.device_size
        || usage.free_estimated > usage.device_size
        || usage.free_minimum > usage.device_size
        || usage.device_unallocated > usage.device_size
    {
        return Err("btrfs reported free space larger than the filesystem".into());
    }

    Ok(Metrics {
        filesystem_size: usage.device_size,
        statfs_available: usage.statfs_available,
        btrfs_free_estimated: usage.free_estimated,
        btrfs_free_minimum: usage.free_minimum,
        device_unallocated: usage.device_unallocated,
        device_missing: usage.device_missing,
        metadata_total,
        metadata_used,
        global_reserve_total: usage.global_reserve_total,
        global_reserve_used: usage.global_reserve_used,
        device_errors: parse_device_stats(&device_stats)?,
    })
}

#[derive(Debug, Eq, PartialEq)]
struct FilesystemUsage {
    device_size: u64,
    device_unallocated: u64,
    device_missing: u64,
    free_estimated: u64,
    free_minimum: u64,
    statfs_available: u64,
    global_reserve_total: u64,
    global_reserve_used: u64,
}

fn parse_filesystem_usage(text: &str) -> Result<FilesystemUsage, String> {
    let free = labeled_value(text, "Free (estimated):")?;
    let free_estimated = first_number(free, "free estimate")?;
    let free_minimum = value_after(free, "(min:", "free minimum")?;
    let reserve = labeled_value(text, "Global reserve:")?;

    Ok(FilesystemUsage {
        device_size: labeled_number(text, "Device size:")?,
        device_unallocated: labeled_number(text, "Device unallocated:")?,
        device_missing: labeled_number(text, "Device missing:")?,
        free_estimated,
        free_minimum,
        statfs_available: labeled_number(text, "Free (statfs, df):")?,
        global_reserve_total: first_number(reserve, "global reserve")?,
        global_reserve_used: value_after(reserve, "(used:", "used global reserve")?,
    })
}

fn parse_filesystem_df(text: &str) -> Result<(u64, u64), String> {
    let mut total = 0_u64;
    let mut used = 0_u64;
    let mut profiles = 0;
    for line in text.lines().map(str::trim) {
        if !line.starts_with("Metadata,") {
            continue;
        }
        total = total
            .checked_add(assignment(line, "total=")?)
            .ok_or("metadata total overflow")?;
        used = used
            .checked_add(assignment(line, "used=")?)
            .ok_or("metadata used overflow")?;
        profiles += 1;
    }
    if profiles == 0 {
        return Err("missing metadata profile in btrfs filesystem df output".into());
    }
    Ok((total, used))
}

fn parse_device_stats(text: &str) -> Result<BTreeMap<String, u64>, String> {
    let mut errors = BTreeMap::new();
    for line in text.lines().map(str::trim).filter(|line| !line.is_empty()) {
        let separator = line
            .rfind(|character: char| character.is_ascii_whitespace())
            .ok_or("malformed btrfs device stats line")?;
        let (key, value) = line.split_at(separator);
        let key = key.trim();
        let value = value
            .trim()
            .parse()
            .map_err(|_| format!("invalid btrfs device stats value in {line:?}"))?;
        if !key.starts_with('[') || !key.contains("].") {
            return Err(format!("invalid btrfs device stats counter {key:?}"));
        }
        errors.insert(key.to_owned(), value);
    }
    if errors.is_empty() {
        return Err("missing counters in btrfs device stats output".into());
    }
    Ok(errors)
}

fn assess(metrics: &Metrics, thresholds: &Thresholds) -> Assessment {
    let mut critical = Vec::new();
    let mut warning = Vec::new();

    if metrics.device_missing > 0 {
        critical.push("device_missing");
    }
    if metrics.device_error_count() > 0 {
        critical.push("device_errors");
    }

    if metrics.free_percent() < thresholds.critical_free_percent {
        critical.push("free_space");
    } else if metrics.free_percent() < thresholds.warning_free_percent {
        warning.push("free_space");
    }

    if metrics.metadata_percent() >= thresholds.critical_metadata_percent {
        critical.push("metadata_usage");
    }

    if metrics.metadata_percent() >= thresholds.critical_combined_metadata_percent
        && metrics.device_unallocated < thresholds.critical_unallocated
    {
        critical.push("metadata_allocation");
    } else if metrics.metadata_percent() >= thresholds.warning_combined_metadata_percent
        && metrics.device_unallocated < thresholds.warning_unallocated
    {
        warning.push("metadata_allocation");
    }

    let (status, reasons) = if critical.is_empty() {
        if warning.is_empty() {
            (Status::Ok, warning)
        } else {
            (Status::Warning, warning)
        }
    } else {
        critical.extend(warning);
        (Status::Critical, critical)
    };
    Assessment {
        status,
        reasons: reasons.into_iter().map(str::to_owned).collect(),
    }
}

fn summary(status: Status, reasons: &[String], metrics: Option<&Metrics>) -> String {
    let reasons = reasons_text(reasons);
    let Some(metrics) = metrics else {
        return format!("status={status} measurement=failed reasons={reasons}");
    };
    format!(
        concat!(
            "status={} size_bytes={} statfs_available_bytes={} ",
            "free_estimated_bytes={} free_minimum_bytes={} conservative_free_bytes={} ",
            "free_percent={:.2} unallocated_bytes={} metadata_used_bytes={} ",
            "metadata_total_bytes={} metadata_percent={:.2} global_reserve_used_bytes={} ",
            "missing_devices={} device_errors={} reasons={}"
        ),
        status,
        metrics.filesystem_size,
        metrics.statfs_available,
        metrics.btrfs_free_estimated,
        metrics.btrfs_free_minimum,
        metrics.conservative_free(),
        metrics.free_percent(),
        metrics.device_unallocated,
        metrics.metadata_used,
        metrics.metadata_total,
        metrics.metadata_percent(),
        metrics.global_reserve_used,
        metrics.device_missing,
        metrics.device_error_count(),
        reasons,
    )
}

fn notification_text(
    status: Status,
    reasons: &[String],
    metrics: Option<&Metrics>,
) -> (String, String) {
    let title = if status == Status::Ok {
        "Disk pressure recovered".to_owned()
    } else {
        format!("Disk pressure {status}")
    };
    let body = if let Some(metrics) = metrics {
        let mut body = format!(
            "Free: {:.2} GiB ({:.1}%). Metadata: {:.1}%. Unallocated: {:.2} GiB.",
            metrics.conservative_free() as f64 / GIB as f64,
            metrics.free_percent(),
            metrics.metadata_percent(),
            metrics.device_unallocated as f64 / GIB as f64,
        );
        if !reasons.is_empty() {
            let _ = write!(body, " Reasons: {}.", reasons.join(", "));
        }
        body
    } else {
        format!(
            "Could not measure the Btrfs filesystem: {}",
            reasons.join(", ")
        )
    };
    (title, body)
}

fn send_notification(status: Status, title: &str, body: &str) -> bool {
    let uid = match current_uid() {
        Ok(uid) => uid,
        Err(error) => {
            eprintln!("notification=deferred error={}", one_line(&error));
            return false;
        }
    };
    let runtime = format!("/run/user/{uid}");
    let bus = format!("{runtime}/bus");
    let bus_address = format!("unix:path={bus}");
    if !Path::new(&bus).exists() {
        eprintln!("notification=deferred error=session_bus_unavailable");
        return false;
    }
    let urgency = if status == Status::Critical {
        "critical"
    } else {
        "normal"
    };
    let expiry = if status == Status::Critical {
        "0"
    } else {
        "15000"
    };
    let environment = [
        ("XDG_RUNTIME_DIR", runtime.as_str()),
        ("DBUS_SESSION_BUS_ADDRESS", bus_address.as_str()),
    ];
    match run_command(
        "notify-send",
        &[
            "--app-name",
            "Disk pressure monitor",
            "--urgency",
            urgency,
            "--expire-time",
            expiry,
            title,
            body,
        ],
        Duration::from_secs(15),
        &environment,
    ) {
        Ok(_) => true,
        Err(error) => {
            eprintln!("notification=deferred error={}", one_line(&error));
            false
        }
    }
}

fn run_command(
    program: &str,
    arguments: &[&str],
    timeout: Duration,
    environment: &[(&str, &str)],
) -> Result<String, String> {
    let mut command = Command::new(program);
    command
        .args(arguments)
        .env("LC_ALL", "C")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    for (key, value) in environment {
        command.env(key, value);
    }
    let mut child = command
        .spawn()
        .map_err(|error| format!("starting {program}: {error}"))?;
    let started = Instant::now();
    loop {
        match child
            .try_wait()
            .map_err(|error| format!("waiting for {program}: {error}"))?
        {
            Some(_) => {
                let output = child
                    .wait_with_output()
                    .map_err(|error| format!("collecting {program} output: {error}"))?;
                if !output.status.success() {
                    let stderr = String::from_utf8_lossy(&output.stderr);
                    let stdout = String::from_utf8_lossy(&output.stdout);
                    let detail = if stderr.trim().is_empty() {
                        stdout.trim()
                    } else {
                        stderr.trim()
                    };
                    return Err(format!(
                        "{program} exited with {}: {}",
                        output.status,
                        if detail.is_empty() {
                            "no output"
                        } else {
                            detail
                        }
                    ));
                }
                return String::from_utf8(output.stdout)
                    .map_err(|error| format!("{program} output was not UTF-8: {error}"));
            }
            None if started.elapsed() >= timeout => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(format!(
                    "{program} timed out after {} seconds",
                    timeout.as_secs()
                ));
            }
            None => thread::sleep(Duration::from_millis(50)),
        }
    }
}

fn labeled_value<'a>(text: &'a str, label: &str) -> Result<&'a str, String> {
    text.lines()
        .map(str::trim)
        .find_map(|line| line.strip_prefix(label).map(str::trim))
        .ok_or_else(|| format!("missing {label:?} in btrfs filesystem usage output"))
}

fn labeled_number(text: &str, label: &str) -> Result<u64, String> {
    first_number(labeled_value(text, label)?, label)
}

fn first_number(text: &str, description: &str) -> Result<u64, String> {
    let token = text
        .split_whitespace()
        .next()
        .ok_or_else(|| format!("missing {description}"))?;
    let digits = token.trim_end_matches(')');
    if digits.is_empty() || !digits.chars().all(|character| character.is_ascii_digit()) {
        return Err(format!("invalid {description} in {text:?}"));
    }
    digits
        .parse()
        .map_err(|_| format!("invalid {description} in {text:?}"))
}

fn value_after(text: &str, marker: &str, description: &str) -> Result<u64, String> {
    let value = text
        .split_once(marker)
        .map(|(_, value)| value.trim())
        .ok_or_else(|| format!("missing {description} in {text:?}"))?;
    first_number(value, description)
}

fn assignment(text: &str, key: &str) -> Result<u64, String> {
    let value = text
        .split_once(key)
        .map(|(_, value)| value)
        .ok_or_else(|| format!("missing {key:?} in {text:?}"))?;
    let token = value
        .split(|character: char| character == ',' || character.is_ascii_whitespace())
        .next()
        .ok_or_else(|| format!("missing {key:?} value in {text:?}"))?;
    if token.is_empty() || !token.chars().all(|character| character.is_ascii_digit()) {
        return Err(format!("invalid {key:?} value in {text:?}"));
    }
    token
        .parse()
        .map_err(|_| format!("invalid {key:?} value in {text:?}"))
}

fn current_uid() -> Result<u32, String> {
    let status = fs::read_to_string("/proc/self/status")
        .map_err(|error| format!("reading process status: {error}"))?;
    let uid = status
        .lines()
        .find_map(|line| line.strip_prefix("Uid:"))
        .and_then(|value| value.split_whitespace().next())
        .ok_or("missing process uid")?;
    uid.parse()
        .map_err(|_| format!("invalid process uid {uid:?}"))
}

fn percent(part: u64, total: u64) -> f64 {
    100.0 * part as f64 / total as f64
}

fn reasons_text(reasons: &[String]) -> String {
    if reasons.is_empty() {
        "none".to_owned()
    } else {
        reasons.join(",")
    }
}

fn one_line(value: &str) -> String {
    value.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn parse_arguments() -> Result<bool, String> {
    let mut no_notify = false;
    for argument in env::args().skip(1) {
        match argument.as_str() {
            "--no-notify" => no_notify = true,
            "--help" | "-h" => {
                println!("btrfs-pressure-check [--no-notify]");
                std::process::exit(0);
            }
            _ => return Err(format!("unknown argument {argument:?}")),
        }
    }
    Ok(no_notify)
}

#[cfg(test)]
mod tests {
    use super::*;

    const USAGE: &str = r#"
Overall:
    Device size:              935130238976
    Device allocated:         906138091520
    Device unallocated:        28992147456
    Device missing:                       0
    Device slack:                     3584
    Used:                     811281862656
    Free (estimated):         117353168896 (min: 102857095168)
    Free (statfs, df):        117352116224
    Data ratio:                        1.00
    Metadata ratio:                    2.00
    Global reserve:               536870912 (used: 0)
    Multiple profiles:                   no
"#;

    const FILESYSTEM_DF: &str = r#"
Data, single: total=871899332608, used=783538311168
System, DUP: total=8388608, used=131072
Metadata, DUP: total=17110990848, used=13871644672
GlobalReserve, single: total=536870912, used=0
"#;

    const DEVICE_STATS: &str = r#"
[/dev/nvme0n1p3].write_io_errs    0
[/dev/nvme0n1p3].read_io_errs     0
[/dev/nvme0n1p3].flush_io_errs    0
[/dev/nvme0n1p3].corruption_errs  0
[/dev/nvme0n1p3].generation_errs  0
"#;

    fn metrics(
        free_percent: f64,
        metadata_percent: f64,
        unallocated_gib: u64,
        missing: u64,
        errors: u64,
    ) -> Metrics {
        let size = 100 * GIB;
        let metadata_total = 10 * GIB;
        Metrics {
            filesystem_size: size,
            statfs_available: (size as f64 * free_percent / 100.0) as u64,
            btrfs_free_estimated: (size as f64 * free_percent / 100.0) as u64,
            btrfs_free_minimum: (size as f64 * free_percent / 100.0) as u64,
            device_unallocated: unallocated_gib * GIB,
            device_missing: missing,
            metadata_total,
            metadata_used: (metadata_total as f64 * metadata_percent / 100.0) as u64,
            global_reserve_total: 512 * 1024 * 1024,
            global_reserve_used: 0,
            device_errors: BTreeMap::from([("device.write_io_errs".into(), errors)]),
        }
    }

    fn notified(decision: WarningNotificationDecision) -> WarningBackoffState {
        match decision {
            WarningNotificationDecision::Notify(state) => state,
            WarningNotificationDecision::Suppress { .. } => panic!("expected notification"),
        }
    }

    #[test]
    fn parses_current_usage() {
        let parsed = parse_filesystem_usage(USAGE).unwrap();
        assert_eq!(parsed.device_size, 935_130_238_976);
        assert_eq!(parsed.device_unallocated, 28_992_147_456);
        assert_eq!(parsed.free_minimum, 102_857_095_168);
        assert_eq!(parsed.statfs_available, 117_352_116_224);
        assert_eq!(parsed.global_reserve_used, 0);
    }

    #[test]
    fn sums_metadata_profiles() {
        let text = format!("{FILESYSTEM_DF}Metadata, single: total=100, used=40\n");
        assert_eq!(
            parse_filesystem_df(&text).unwrap(),
            (17_110_990_948, 13_871_644_712)
        );
    }

    #[test]
    fn parses_device_counters() {
        let counters = parse_device_stats(DEVICE_STATS).unwrap();
        assert_eq!(counters.len(), 5);
        assert_eq!(counters.values().sum::<u64>(), 0);

        let counters = parse_device_stats("[/dev/mapper/device name].write_io_errs  1\n").unwrap();
        assert_eq!(counters["[/dev/mapper/device name].write_io_errs"], 1);
    }

    #[test]
    fn rejects_incomplete_output() {
        assert!(parse_filesystem_usage("Device size: 1\n").is_err());
        assert!(parse_filesystem_df("Data, single: total=1, used=1\n").is_err());
        assert!(parse_device_stats("no counters\n").is_err());
        assert!(first_number("123garbage", "test value").is_err());
        assert!(assignment("Metadata: total=123garbage", "total=").is_err());
    }

    #[test]
    fn classifies_free_space_boundaries() {
        let thresholds = Thresholds::default();
        assert_eq!(
            assess(&metrics(10.0, 70.0, 30, 0, 0), &thresholds).status,
            Status::Ok
        );
        assert_eq!(
            assess(&metrics(9.9, 70.0, 30, 0, 0), &thresholds).status,
            Status::Warning
        );
        assert_eq!(
            assess(&metrics(5.0, 70.0, 30, 0, 0), &thresholds).status,
            Status::Warning
        );
        assert_eq!(
            assess(&metrics(4.9, 70.0, 30, 0, 0), &thresholds).status,
            Status::Critical
        );
    }

    #[test]
    fn classifies_metadata_boundaries() {
        let thresholds = Thresholds::default();
        assert_eq!(
            assess(&metrics(20.0, 85.0, 30, 0, 0), &thresholds).status,
            Status::Ok
        );
        assert_eq!(
            assess(&metrics(20.0, 94.9, 30, 0, 0), &thresholds).status,
            Status::Ok
        );
        assert_eq!(
            assess(&metrics(20.0, 95.0, 30, 0, 0), &thresholds).status,
            Status::Critical
        );
    }

    #[test]
    fn classifies_combined_allocation_pressure() {
        let thresholds = Thresholds::default();
        let warning = assess(&metrics(20.0, 80.0, 23, 0, 0), &thresholds);
        let critical = assess(&metrics(20.0, 90.0, 11, 0, 0), &thresholds);
        assert_eq!(warning.status, Status::Warning);
        assert!(warning.reasons.contains(&"metadata_allocation".into()));
        assert_eq!(critical.status, Status::Critical);
    }

    #[test]
    fn missing_device_and_errors_are_critical() {
        let thresholds = Thresholds::default();
        assert_eq!(
            assess(&metrics(20.0, 70.0, 30, 1, 0), &thresholds).status,
            Status::Critical
        );
        assert_eq!(
            assess(&metrics(20.0, 70.0, 30, 0, 1), &thresholds).status,
            Status::Critical
        );

        let assessment = assess(&metrics(9.0, 70.0, 30, 0, 1), &thresholds);
        assert!(assessment.reasons.contains(&"device_errors".into()));
        assert!(assessment.reasons.contains(&"free_space".into()));
    }

    #[test]
    fn warning_backoff_reaches_daily_cap() {
        let fingerprint = "metadata_allocation";
        let mut now = 100;
        let mut state = notified(warning_notification_decision(None, fingerprint, now));
        assert_eq!(state.notifications, 1);

        for delay in WARNING_BACKOFF_SECONDS {
            assert_eq!(
                warning_notification_decision(Some(&state), fingerprint, now + delay - 1),
                WarningNotificationDecision::Suppress {
                    remaining_seconds: 1
                }
            );
            now += delay;
            state = notified(warning_notification_decision(
                Some(&state),
                fingerprint,
                now,
            ));
        }

        assert_eq!(state.notifications, 6);
        assert!(matches!(
            warning_notification_decision(Some(&state), fingerprint, now + 24 * 60 * 60 - 1),
            WarningNotificationDecision::Suppress { .. }
        ));
        let state = notified(warning_notification_decision(
            Some(&state),
            fingerprint,
            now + 24 * 60 * 60,
        ));
        assert_eq!(state.notifications, 7);
    }

    #[test]
    fn changed_warning_notifies_immediately() {
        let previous = WarningBackoffState {
            fingerprint: "free_space".into(),
            last_notified: 100,
            notifications: 5,
        };
        let state = notified(warning_notification_decision(
            Some(&previous),
            "metadata_allocation",
            101,
        ));
        assert_eq!(
            state,
            WarningBackoffState {
                fingerprint: "metadata_allocation".into(),
                last_notified: 101,
                notifications: 1,
            }
        );
    }

    #[test]
    fn warning_state_round_trips_and_clears() {
        let path = env::temp_dir().join(format!(
            "btrfs-pressure-warning-state-{}",
            std::process::id()
        ));
        let state = WarningBackoffState {
            fingerprint: "free_space,metadata_allocation".into(),
            last_notified: 1234,
            notifications: 4,
        };

        save_warning_state(&path, &state).unwrap();
        assert_eq!(load_warning_state(&path).unwrap(), Some(state));
        clear_warning_state(Some(&path));
        assert_eq!(load_warning_state(&path).unwrap(), None);
    }

    #[test]
    fn command_timeout_is_reported() {
        let error =
            run_command("sh", &["-c", "sleep 1"], Duration::from_millis(10), &[]).unwrap_err();
        assert!(error.contains("timed out"));
    }
}
