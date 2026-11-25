# Desktop-specific NixOS configuration. Shared settings live in ../common.nix.
{
  pkgs,
  unstable,
  ...
}:

let
  btrfs-pressure-monitor = pkgs.callPackage ../custom/btrfs-pressure-monitor/package.nix { };
in
{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./llama-server.nix
    ./gufo-server.nix
  ];

  boot.kernelPackages = pkgs.linuxPackages_6_18; # needed to fix WiFi driver not advertising P2P-device

  # Expand GPU-visible memory to 124 GiB for large ROCm models on Strix Halo.
  boot.kernelParams = [
    "amdgpu.gttsize=126976"
    "ttm.pages_limit=32505856"
    "ttm.page_pool_size=32505856"
  ];

  # Keep /nix/store outside snapper's root snapshots. NixOS applies the public
  # read-only store bind from boot.nixStoreMountOpts; the daemon keeps its private
  # writable view.
  fileSystems."/nix/store" = {
    device = "/dev/disk/by-uuid/18fb10b7-1f41-4b2d-8c2a-d86825840375";
    fsType = "btrfs";
    options = [ "subvol=@nixstore" ];
  };

  networking.hostName = "philipps-desktop";

  services.dbus.packages = [ pkgs.miraclecast ];

  # Set your time zone.
  time.timeZone = "Europe/Berlin";

  services.displayManager.gdm.autoSuspend = false;

  # Set shell history to append instead of replace.
  programs.bash.interactiveShellInit = ''
    shopt -s histappend
  '';

  # Enable CUPS to print documents.
  services.printing.enable = true;

  virtualisation.podman.enable = true;

  virtualisation.oci-containers = {
    backend = "podman";

    containers.wbo = {
      image = "docker.io/lovasoa/wbo:latest";
      ports = [ "127.0.0.1:5001:80" ];
      volumes = [
        "/var/lib/wbo:/opt/app/server-data"
      ];
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/wbo 0750 1000 1000 -"
    # Separate subvolumes keep downloaded weights out of home snapshots.
    # Existing ordinary directories must be migrated manually first.
    "v /home/philipp/.local/share/models 0755 philipp users -"
    "v /home/philipp/.lmstudio/models 0755 philipp users -"
  ];

  users.users.philipp = {
    extraGroups = [ "i2c" ];
    packages = with pkgs; [
      home-manager
      unstable.rustup
      wget
      curl
      gnome-tweaks
      vlc
      usbutils
      git
      gcc
      gnumake
      openrgb
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILBpGNJCiAT2fYCZjVKHlnubTqUIpGWMRQiOdtC05kUy browser"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEnU+OsWjdqZ0JnF1r8aAIjSsbKkX2XYDUcyvbOk7vr0 fairphone"
    ];
  };

  # Desktop-specific Home Manager settings.
  home-manager.users.philipp = {
    imports = [
      ../home-manager/letta-code.nix
      ../home-manager/nono-shell.nix
    ];
    custom.discord-archive.spkiHash = "iinWnh0zDru6ToeSSHL4daigcE77KK12KnYX3IWwrys=";
  };

  # Install firefox.
  programs.firefox.enable = true;
  programs.firefox.package = unstable.firefox;

  environment.systemPackages = with pkgs; [
    android-tools
    snapper-gui
    socat
    bubblewrap
    btrfs-pressure-monitor
  ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true; # needed for Steam (32-bit games)
  };

  # Load i2c_dev kernel module for OpenRGB I2C/SMBus access.
  boot.extraModprobeConfig = ''
    options i2c_dev major=89
  '';
  boot.kernelModules = [ "i2c_dev" ];

  # I2C device permissions for OpenRGB.
  services.udev.extraRules = ''
    SUBSYSTEM=="i2c-dev", GROUP="i2c", MODE="0660"
  '';

  # Snapper - btrfs snapshots for rollback.
  services.snapper.snapshotRootOnBoot = true;
  services.snapper.configs.root = {
    SUBVOLUME = "/";
    ALLOW_USERS = [ "philipp" ];
    TIMELINE_CREATE = true;
    TIMELINE_CLEANUP = true;
    TIMELINE_LIMIT_HOURLY = 24;
    TIMELINE_LIMIT_DAILY = 5;
    TIMELINE_LIMIT_WEEKLY = 3;
    TIMELINE_LIMIT_MONTHLY = 3;
    TIMELINE_LIMIT_YEARLY = 0;
    # snapshotRootOnBoot creates cleanup=number snapshots, which the timeline
    # cleanup never touches. Without these they accumulate forever.
    NUMBER_CLEANUP = true;
    NUMBER_LIMIT = 10;
    NUMBER_LIMIT_IMPORTANT = 5;
  };

  services.snapper.configs.home = {
    SUBVOLUME = "/home";
    ALLOW_USERS = [ "philipp" ];
    TIMELINE_CREATE = true;
    TIMELINE_CLEANUP = true;
    TIMELINE_LIMIT_HOURLY = 24;
    TIMELINE_LIMIT_DAILY = 5;
    TIMELINE_LIMIT_WEEKLY = 3;
    TIMELINE_LIMIT_MONTHLY = 3;
    TIMELINE_LIMIT_YEARLY = 0;
  };

  # Report Btrfs space and allocation pressure without taking cleanup actions.
  systemd.services.btrfs-pressure-monitor = {
    description = "Check Btrfs disk and allocation pressure";
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "philipp";
      Group = "users";
      ExecStart = "${btrfs-pressure-monitor}/bin/btrfs-pressure-check";
      TimeoutStartSec = "2m";
      StateDirectory = "btrfs-pressure-monitor";
      StateDirectoryMode = "0700";
      UMask = "0077";
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      PrivateTmp = true;
      NoNewPrivileges = true;
      ProtectControlGroups = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      RestrictAddressFamilies = [ "AF_UNIX" ];
    };
  };

  systemd.timers.btrfs-pressure-monitor = {
    description = "Periodically check Btrfs disk and allocation pressure";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "10m";
      AccuracySec = "1m";
      Persistent = true;
    };
  };

  # Capture pressure immediately before the existing daily snapshot cleanup.
  systemd.services.snapper-cleanup = {
    wants = [ "btrfs-pressure-monitor.service" ];
    after = [ "btrfs-pressure-monitor.service" ];
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?
}
