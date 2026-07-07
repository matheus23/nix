#!/usr/bin/env python3
"""btrfs-snap-scrub -- remove a file or directory from all btrfs snapshots that
share its data extents, in order to actually reclaim disk space.

This is NOT related to ``btrfs scrub`` (which verifies data checksums).

Background
----------
btrfs snapshots are read-only subvolumes. A file deleted from the live
filesystem is not gone from disk as long as some snapshot still references its
extents: the extents' reference count stays above zero and the space is not
freed. To reclaim the space you must remove the file from *every* subvolume
(snapshot, and the live one if it still holds a copy) that references those
extents.

This tool:
  1. Takes a path to a surviving copy of the file/dir (in the live FS or any
     snapshot) and derives its path relative to its subvolume.
  2. Walks the file's data extents and asks the kernel (LOGICAL_INO ioctl)
     exactly which subvolume roots still reference them.
  3. Finds every snapshot whose tree contains the file at that relative path
     and is reachable through a mounted subvolume.
  4. Reports which roots reference the extents but will NOT be scrubbed (so the
     space will NOT be fully freed) -- e.g. received/backup subvolumes,
     inaccessible (unmounted) subvolumes, or renamed copies.
  5. With ``--apply``: for each target snapshot, flips it read-write, removes
     the file, and flips it back to read-only, restoring state on failure or
     interruption. Finally syncs the filesystem.

Caveats
-------
* Editing a snapshot in place keeps its UUID but changes its content. This
  breaks btrbk's (and any send/receive's) incremental assumption that a parent
  snapshot is immutable. Expect to need a full (non-incremental) backup next
  cycle for any chain rooted at a scrubbed snapshot.
* Received (send/receive) subvolumes are refused by default: making them
  read-write via ``btrfs property`` leaves the Received UUID set and corrupts
  future incremental receive. Use ``--include-received`` to override (dangerous).
"""

import argparse
import os
import shutil
import subprocess
import sys
import uuid

try:
    import btrfs
    from btrfs.ctree import (
        Key,
        EXTENT_DATA_KEY,
        FILE_EXTENT_REG,
        ROOT_SUBVOL_RDONLY,
    )
except ImportError as exc:  # pragma: no cover
    sys.stderr.write(
        "error: the 'btrfs' python module is required (python-btrfs): %s\n" % exc
    )
    sys.exit(2)

NIL_UUID = uuid.UUID(int=0)
BTRFS_TOPLEVEL_ID = 5


# --------------------------------------------------------------------------- #
# small helpers
# --------------------------------------------------------------------------- #
def run(cmd):
    """Run a command, returning stdout text. Raise CalledProcessError on failure."""
    return subprocess.run(
        cmd, check=True, capture_output=True, text=True
    ).stdout


def human(n):
    n = float(n)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if abs(n) < 1024.0 or unit == "TiB":
            return "%.1f %s" % (n, unit)
        n /= 1024.0
    return "%.1f PiB" % n


def warn(msg):
    sys.stderr.write("warn: %s\n" % msg)


def die(msg, code=1):
    sys.stderr.write("error: %s\n" % msg)
    sys.exit(code)


def logv(msg, verbose):
    if verbose:
        sys.stderr.write("     %s\n" % msg)


# --------------------------------------------------------------------------- #
# btrfs mount discovery
# --------------------------------------------------------------------------- #
def btrfs_mounts_for(dev):
    """Return [(target, subvol_norm, subvolid_str)] for btrfs mounts on st_dev=dev."""
    mounts = []
    with open("/proc/mounts") as f:
        for line in f:
            parts = line.split()
            if len(parts) < 4:
                continue
            _dev, target, fstype, opts = parts[0], parts[1], parts[2], parts[3]
            if fstype != "btrfs":
                continue
            try:
                if os.stat(target).st_dev != dev:
                    continue
            except OSError:
                continue
            subvol = None
            subvolid = None
            for opt in opts.split(","):
                if opt.startswith("subvol="):
                    subvol = opt[len("subvol="):]
                elif opt.startswith("subvolid="):
                    subvolid = opt[len("subvolid="):]
            subvol_norm = subvol.lstrip("/") if subvol is not None else ""
            mounts.append((target, subvol_norm, subvolid))
    return mounts


def mount_of_path(path, mounts):
    """Return the mount whose target is the longest prefix of path, or None."""
    best = None
    for mnt in mounts:
        target = mnt[0]
        if path == target or path.startswith(target + "/"):
            if best is None or len(target) > len(best[0]):
                best = mnt
    return best


def accessible_path(toprel, mounts):
    """Map a toplevel-relative subvol path (e.g. "@home/.snapshots/1/snapshot")
    to a reachable absolute filesystem path via mount covering.

    A mount with subvol=/X (normalized to "X") covers any toplevel path equal
    to X or starting with "X/"; the accessible path is <mount_target>/<rest>.
    The most specific (longest) matching mount wins. A toplevel mount
    (subvol=/ or no subvol= option, normalized to "") covers everything.
    Returns None if no mount covers the path.
    """
    toprel = toprel.lstrip("/")
    best = None
    best_len = -1
    toplevel_mount = None
    for target, subvol_norm, _subvolid in mounts:
        if subvol_norm == "":
            toplevel_mount = target
            continue
        if toprel == subvol_norm or toprel.startswith(subvol_norm + "/"):
            rest = toprel[len(subvol_norm):].lstrip("/")
            cand = os.path.join(target, rest) if rest else target
            if len(subvol_norm) > best_len:
                best = cand
                best_len = len(subvol_norm)
    if best is not None:
        return best
    if toplevel_mount is not None:
        return os.path.join(toplevel_mount, toprel)
    return None


def resolve_accessible(rootid, mounts, list_mount):
    """Return an accessible absolute path for a subvolume rootid, or None.

      * If a mount's own subvolid matches rootid, that mount target is the path
        (handles subvols that are themselves mount targets, e.g. 256=@ at /,
        257=@home at /home).
      * Otherwise, `btrfs inspect-internal subvolid-resolve <rootid> <mount>`
        returns the subvol's path relative to the btrfs toplevel (subvolid 5)
        by walking the root backref tree -- it is filesystem-wide and works
        against any mount. We then map that toplevel-relative path to an
        accessible path via accessible_path() (mount covering).
    """
    for target, _subvol_norm, subvolid in mounts:
        if subvolid is not None:
            try:
                if int(subvolid) == rootid:
                    return target
            except ValueError:
                pass
    toprel = None
    try:
        toprel = run(
            ["btrfs", "inspect-internal", "subvolid-resolve", str(rootid), list_mount]
        ).strip()
    except subprocess.CalledProcessError:
        pass
    if not toprel:
        return None
    return accessible_path(toprel, mounts)


def property_get_ro(path):
    """Best-effort read of the read-only flag. Returns True/False or None."""
    try:
        out = run(["btrfs", "property", "get", "-ts", path, "ro"]).strip().lower()
    except subprocess.CalledProcessError:
        return None
    if "true" in out:
        return True
    if "false" in out:
        return False
    return None


# --------------------------------------------------------------------------- #
# extent / reference inspection (python-btrfs)
# --------------------------------------------------------------------------- #
def file_extent_vaddrs(fs, tree, inum):
    """Yield logical addresses (disk_bytenr) of regular data extents of inum."""
    min_key = Key(inum, EXTENT_DATA_KEY, 0)
    max_key = Key(inum, EXTENT_DATA_KEY + 1, 0) - 1
    for header, data in btrfs.ioctl.search_v2(fs.fd, tree, min_key, max_key):
        fe = btrfs.ctree.FileExtentItem(header, data)
        if fe.type == FILE_EXTENT_REG and fe.disk_bytenr != 0:
            yield fe.disk_bytenr


def referencing_inodes(fs, vaddr):
    """Return list of Inode(inum, offset, root) referencing the extent at vaddr.

    Uses LOGICAL_INO_V2 with ignore_offset (kernel >= 4.15) so that any inode
    referencing any block of the extent is returned. Retries with a larger
    buffer when the kernel reports truncated results.
    """
    bufsize = 4096
    while True:
        inodes, missing = btrfs.ioctl.logical_ino_v2(
            fs.fd, vaddr, bufsize=bufsize, ignore_offset=True
        )
        if missing == 0 or bufsize >= 16 * 1024 * 1024:
            return inodes
        bufsize = min(bufsize + missing, 16 * 1024 * 1024)


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #
def parse_args(argv):
    ap = argparse.ArgumentParser(
        prog="btrfs-snap-scrub",
        description=(
            "Remove a file or directory from all btrfs snapshots sharing its "
            "extents to reclaim disk space. NOT related to `btrfs scrub`."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "By default the tool only prints a plan (dry-run). Pass --apply to "
            "perform deletions.\n\n"
            "Point PATH at any surviving copy of the file (in the live FS or in a "
            "snapshot). If you already deleted it from the live FS, point at a "
            "snapshot copy."
        ),
    )
    ap.add_argument("path", help="path to the file/dir to scrub (live FS or a snapshot)")
    ap.add_argument("--apply", action="store_true", help="actually perform deletions (default: dry-run)")
    ap.add_argument("-y", "--yes", action="store_true", help="skip confirmation prompt (use with --apply)")
    ap.add_argument("--no-extent-check", action="store_true", help="skip extent-reference analysis")
    ap.add_argument(
        "--include-received",
        action="store_true",
        help="also scrub received (send/receive) subvolumes [DANGEROUS: corrupts incremental receive]",
    )
    ap.add_argument(
        "--skip-live",
        action="store_true",
        help="do not delete from the live subvolume (extents there will not be freed)",
    )
    ap.add_argument("--no-sync", action="store_true", help="skip final `btrfs filesystem sync`")
    ap.add_argument("-v", "--verbose", action="store_true", help="verbose progress on stderr")
    return ap.parse_args(argv)


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])

    target = os.path.abspath(os.path.expanduser(args.path))
    if not os.path.lexists(target):
        die("path not found: %s -- point at a surviving copy (live or a snapshot)" % target)

    if os.geteuid() != 0:
        die("must run as root (needs btrfs property / subvolume ioctls)")

    is_dir = os.path.isdir(target) and not os.path.islink(target)
    inum = os.stat(target, follow_symlinks=False).st_ino
    dev = os.stat(target).st_dev

    mounts = btrfs_mounts_for(dev)
    if not mounts:
        die("could not find a btrfs mount for %s" % target)
    live_mount = mount_of_path(target, mounts)
    live_rootid = int(live_mount[2]) if live_mount and live_mount[2] else None

    if live_rootid is None:
        die("could not determine the subvolume id of the live mount for %s" % target)

    # reference copy: derive relpath within its subvolume + the subvol root id
    with btrfs.FileSystem(target) as fs:
        res = btrfs.ioctl.ino_lookup(fs.fd, objectid=inum)
        ref_root = res.treeid
        # The INO_LOOKUP ioctl appends a trailing '/' to the path. Strip it,
        # otherwise isfile()/isdir() reject the candidate (trailing slash means
        # "directory") and the path-based scrub set comes back empty.
        relpath = res.name_bytes.decode("utf-8", "surrogateescape").rstrip("/")
        if not relpath:
            die("refusing to scrub a subvolume root itself; point at a file/dir inside it")

        subvols = {ri.objectid: ri for ri in fs.subvolumes()}

        # files whose extents drive the extent-aware reference check
        ref_files = []  # list of (inum, abspath)
        if is_dir:
            for root, _dirs, files in os.walk(target):
                for fn in files:
                    p = os.path.join(root, fn)
                    if os.path.islink(p):
                        continue
                    try:
                        st = os.stat(p)
                    except OSError:
                        continue
                    ref_files.append((st.st_ino, p))
        else:
            ref_files.append((inum, target))

        extent_roots = {}  # rootid -> set(inum)
        ref_total_size = 0
        if not args.no_extent_check:
            for finum, fp in ref_files:
                try:
                    ref_total_size += os.path.getsize(fp)
                except OSError:
                    pass
                for vaddr in file_extent_vaddrs(fs, ref_root, finum):
                    inodes = referencing_inodes(fs, vaddr)
                    for inode in inodes:
                        extent_roots.setdefault(inode.root, set()).add(inode.inum)
                    logv("extent vaddr %d -> %d root(s)" % (vaddr, len(inodes)), args.verbose)

    # ---- build scrub set ----
    # Only resolve subvolumes that actually matter: the live subvol + any root
    # that references the file's extents (when extent check is on). Resolving all
    # subvols is slow (subvolid-resolve per mount each) and produces a noisy
    # "inaccessible" list of subvols unrelated to the target. With
    # --no-extent-check, fall back to resolving all subvols for a path scan.
    if not args.no_extent_check:
        relevant_roots = set(extent_roots) | {live_rootid}
    else:
        relevant_roots = set(subvols) - {BTRFS_TOPLEVEL_ID}

    acc_map = {}  # rootid -> accessible absolute path or None
    scrub = []
    inaccessible = []
    for rootid in sorted(relevant_roots):
        ri = subvols.get(rootid)
        if ri is None:
            continue
        acc = resolve_accessible(rootid, mounts, live_mount[0])
        acc_map[rootid] = acc
        if acc is None:
            inaccessible.append((rootid, ri))
            continue
        candidate = os.path.join(acc, relpath) if relpath else acc
        if is_dir:
            present = os.path.isdir(candidate)
        else:
            present = os.path.isfile(candidate) or os.path.islink(candidate)
        if not present:
            continue
        logv("rootid %d -> %s" % (rootid, acc), args.verbose)
        scrub.append(
            {
                "rootid": rootid,
                "root": ri,
                "access": acc,
                "target": candidate,
                "ro": bool(ri.flags & ROOT_SUBVOL_RDONLY),
                "received": ri.received_uuid != NIL_UUID,
                "live": rootid == live_rootid,
            }
        )

    # ---- filters ----
    skipped_received = []
    skipped_live = []
    final = []
    for s in sorted(scrub, key=lambda x: x["rootid"]):
        if s["rootid"] == live_rootid and args.skip_live:
            skipped_live.append(s)
            continue
        if s["received"] and not args.include_received:
            skipped_received.append(s)
            continue
        final.append(s)

    # ---- completeness analysis: which referencing roots are NOT scrubbed? ----
    unfreed = []
    if not args.no_extent_check:
        scrub_ids = {s["rootid"] for s in final}
        for rootid in sorted(extent_roots):
            if rootid in scrub_ids:
                continue
            ri = subvols.get(rootid)
            if rootid == live_rootid and args.skip_live:
                reason = "live subvolume (--skip-live)"
            elif any(s["rootid"] == rootid for s in skipped_received):
                reason = "received subvolume (use --include-received to override)"
            elif ri is None:
                reason = "root not found in subvolume tree (deleted/toplevel?)"
            else:
                acc = acc_map.get(rootid)
                reason = (
                    "inaccessible (not reachable through any mount)"
                    if acc is None
                    else "extent referenced but file not at expected path (renamed?)"
                )
            unfreed.append((rootid, reason))

    # ---- print plan ----
    print("target      : %s" % target)
    print("type        : %s" % ("directory" if is_dir else "file"))
    print("rel. path   : %s  (within subvolume rootid %d)" % (relpath, ref_root))
    print("live subvol : rootid %d  (%s)" % (live_rootid, live_mount[0]))
    if not args.no_extent_check and ref_files:
        print("ref. size   : %s across %d file(s)" % (human(ref_total_size), len(ref_files)))
    print()

    def row(rootid, access, ro, received, extra=""):
        flag = ("ro " if ro else "rw ") + ("recv" if received else "    ")
        print("  %-8s %-5s %s%s" % (rootid, flag, access, ("  " + extra) if extra else ""))

    print("Will scrub (%d):" % len(final))
    if final:
        for s in final:
            row(s["rootid"], s["access"], s["ro"], s["received"],
                "(live)" if s.get("live") else "")
    else:
        print("  (none)")

    if skipped_received:
        print("\nSkipped -- received subvolumes (%d) [extents there will NOT be freed]:" % len(skipped_received))
        for s in skipped_received:
            row(s["rootid"], s["access"], s["ro"], s["received"])

    if skipped_live:
        print("\nSkipped -- live subvolume (%d) [extents there will NOT be freed]:" % len(skipped_live))
        for s in skipped_live:
            row(s["rootid"], s["access"], s["ro"], s["received"])

    if inaccessible:
        print("\nInaccessible subvolumes (%d) [not reachable through any mount]:" % len(inaccessible))
        for rootid, ri in inaccessible:
            print("  %-8d rootid (uuid %s)" % (rootid, ri.uuid))

    if unfreed:
        print(
            "\n!! %d root(s) still reference the extents after scrubbing -> space will NOT be fully freed:"
            % len(unfreed)
        )
        for rootid, reason in unfreed:
            print("    rootid %-8d  %s" % (rootid, reason))
    elif not args.no_extent_check and extent_roots:
        print("\nAll extent-referencing roots are in the scrub set -> space should be reclaimed.")

    if not args.apply:
        print("\n(dry-run; pass --apply to perform deletions)")
        return 0

    # ---- confirmation ----
    if not args.yes:
        sys.stderr.write(
            "\nAbout to %s the target from %d subvolume(s) and modify read-only snapshots.\n"
            "This breaks incremental send/receive for affected chains. Continue? [y/N] "
            % ("rm -rf" if is_dir else "rm", len(final))
        )
        try:
            ans = sys.stdin.readline().strip().lower()
        except KeyboardInterrupt:
            print()
            return 130
        if ans not in ("y", "yes"):
            print("aborted")
            return 1

    # ---- execute ----
    avail_before = free_bytes(live_mount[0])
    errors = 0
    interrupted = False
    try:
        for s in final:
            acc = s["access"]
            tgt = s["target"]
            # re-check ro right before flipping (guard against concurrent changes)
            cur_ro = property_get_ro(acc)
            was_ro = cur_ro if cur_ro is not None else s["ro"]
            try:
                if was_ro:
                    run(["btrfs", "property", "set", "-ts", acc, "ro", "false"])
                if is_dir:
                    shutil.rmtree(tgt)
                else:
                    os.remove(tgt)
                print("scrubbed  rootid %-8d  %s" % (s["rootid"], tgt))
            except OSError as e:
                warn("failed to remove %s: %s" % (tgt, e))
                errors += 1
            except subprocess.CalledProcessError as e:
                warn("btrfs command failed on %s: %s" % (acc, (e.stderr or "").strip()))
                errors += 1
            finally:
                # Always restore read-only state, even on interruption or error.
                if was_ro:
                    try:
                        run(["btrfs", "property", "set", "-ts", acc, "ro", "true"])
                    except subprocess.CalledProcessError as e:
                        warn("FAILED to restore read-only on %s: %s -- fix manually!"
                             % (acc, (e.stderr or "").strip()))
    except KeyboardInterrupt:
        interrupted = True
        sys.stderr.write("\nInterrupted -- read-only state restored by cleanup.\n")

    if not args.no_sync and final and not interrupted:
        sys.stderr.write("syncing filesystem (this may take a while)...\n")
        try:
            run(["btrfs", "filesystem", "sync", live_mount[0]])
        except subprocess.CalledProcessError as e:
            warn("sync failed: %s" % (e.stderr or "").strip())

    avail_after = free_bytes(live_mount[0])
    if avail_before is not None and avail_after is not None:
        delta = avail_after - avail_before
        sign = "+" if delta >= 0 else ""
        print("\nfree space: %s -> %s  (%s%s)"
              % (human(avail_before), human(avail_after), sign, human(delta)))

    if interrupted:
        die("interrupted", 130)
    if errors:
        die("completed with %d error(s)" % errors)
    return 0


def free_bytes(mountpoint):
    try:
        st = os.statvfs(mountpoint)
        return st.f_bavail * st.f_frsize
    except OSError:
        return None


if __name__ == "__main__":
    sys.exit(main())
