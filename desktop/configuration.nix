# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  pkgs,
  ...
}:

let
  pigeons = pkgs.callPackage ../custom/pigeons/package.nix { };
  btrfs-pressure-monitor = pkgs.callPackage ../custom/btrfs-pressure-monitor/package.nix { };
in
{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    <home-manager/nixos>
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_6_18; # needed to fix WiFi driver not advertising P2P-device

  # Expand GPU-visible memory for ROCm on Strix Halo (gfx1151).
  # Default GTT aperture is ~62 GB; ds4 needs ~124 GB for the 60 GiB model + runtime buffers.
  boot.kernelParams = [
    "amd_iommu=off"
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

  networking.hostName = "philipps-desktop"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Enable networking
  networking.networkmanager.enable = true;

  services.dbus.packages = [ pkgs.miraclecast ];

  # Set your time zone.
  time.timeZone = "Europe/Berlin";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_DE.UTF-8";
    LC_IDENTIFICATION = "de_DE.UTF-8";
    LC_MEASUREMENT = "de_DE.UTF-8";
    LC_MONETARY = "de_DE.UTF-8";
    LC_NAME = "de_DE.UTF-8";
    LC_NUMERIC = "de_DE.UTF-8";
    LC_PAPER = "de_DE.UTF-8";
    LC_TELEPHONE = "de_DE.UTF-8";
    LC_TIME = "de_DE.UTF-8";
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.displayManager.gdm.enable = true;
  services.displayManager.gdm.autoSuspend = false;
  services.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "de";
    variant = "";
  };

  # Configure console keymap
  console.keyMap = "de";

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

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
  ];

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.philipp = {
    isNormalUser = true;
    description = "Philipp Pohl-Krüger";
    extraGroups = [
      "networkmanager"
      "wheel"
      "i2c"
    ];
    packages = with pkgs; [
      home-manager
      rustup
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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4gDlyPtlzJJ5IvuQXSaB3d8uhOrpTYUzon+CLHqPIM philipp.krueger1@gmail.com"
    ];
  };

  # install my home manager stuff
  home-manager.useGlobalPkgs = true;
  home-manager.users.philipp = import /home/philipp/program/nix/home-manager/home.nix;

  # enable nix flakes
  nix.settings.experimental-features = "nix-command flakes";

  # Install firefox.
  programs.firefox.enable = true;

  # Install adb
  programs.adb.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    snapper-gui
    socat
    bubblewrap
    pigeons
    btrfs-pressure-monitor
  ];

  # needed for steam?
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # needed for Steam (32-bit games)
  };

  programs.steam.enable = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # pigeons roost: always-on carrier pigeon for SSH. Runs as root at boot, so
  # the endpoint ID is published to /etc/pigeons/endpoint_id and readable via
  # `pigeons service status`. Do NOT also run `pigeons service install` — the
  # unit is defined here declaratively. Restart with:
  #   sudo systemctl restart pigeons
  # Tail logs with: journalctl -u pigeons -f
  systemd.services.pigeons = {
    description = "pigeons roost — carrier pigeon SSH tunnel";
    after = [
      "network-online.target"
      "NetworkManager-wait-online.service"
      "nss-lookup.target"
    ];
    wants = [
      "network-online.target"
      "NetworkManager-wait-online.service"
      "nss-lookup.target"
    ];
    wantedBy = [ ]; # manual start only: sudo systemctl start ds4-server
    serviceConfig = {
      Type = "simple";
      Environment = "RUST_LOG=info";
      ExecStart = "${pigeons}/bin/pigeons roost";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  # ds4 inference server — DeepSeek V4 Flash on ROCm (Strix Halo).
  # Serves OpenAI/Anthropic-compatible HTTP API on 127.0.0.1:8000.
  # Logs: journalctl -u ds4-server -f
  # Models live in ~/.lmstudio/models/antirez/deepseekV4Flash/
  systemd.services.ds4-server = {
    description = "ds4 inference server (DeepSeek V4 Flash, ROCm)";
    after = [ "network.target" ];
    wantedBy = [ ]; # manual start only: sudo systemctl start ds4-server
    serviceConfig = {
      Type = "simple";
      User = "philipp";
      Group = "users";
      SupplementaryGroups = [
        "render"
        "video"
      ];
      ExecStart = "/home/philipp/.nix-profile/bin/ds4-server --rocm --host 127.0.0.1 --port 8421 -m /home/philipp/.lmstudio/models/antirez/deepseekV4Flash/DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix.gguf --mtp /home/philipp/.lmstudio/models/antirez/deepseekV4Flash/DeepSeek-V4-Flash-DSpark-support.gguf --dspark --ctx 409600 --kv-disk-dir /home/philipp/.ds4/server-kv --kv-disk-space-mb 8192";
      Restart = "on-failure";
      RestartSec = 10;
      # Model loads in under a minute
      TimeoutStartSec = 120;
    };
  };

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  # Load i2c_dev kernel module for OpenRGB I2C/SMBus access
  boot.extraModprobeConfig = ''
    options i2c_dev major=89
  '';
  boot.kernelModules = [ "i2c_dev" ];

  # I2C device permissions for OpenRGB
  services.udev.extraRules = ''
    SUBSYSTEM=="i2c-dev", GROUP="i2c", MODE="0660"
  '';

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [
    1234 # lmstudio
  ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Snapper - btrfs snapshots for rollback
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
