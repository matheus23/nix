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
    ./llama-server.nix
    ./gufo-server.nix
    <home-manager/nixos>
  ];

  # Distrust compromised intermediates chaining to this root (Mozilla bug 2083449).
  security.pki.caCertificateBlacklist = [
    "Comodo AAA Services root"
  ];

  # Set trust paths at login for desktop apps as well as terminal processes.
  environment.sessionVariables = {
    SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
    NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
  };

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
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

  # Set shell history to append instead of replace
  programs.bash.interactiveShellInit = ''
    shopt -s histappend
  '';

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
    # Separate subvolumes keep downloaded weights out of home snapshots.
    # Existing ordinary directories must be migrated manually first.
    "v /home/philipp/.local/share/models 0755 philipp users -"
    "v /home/philipp/.lmstudio/models 0755 philipp users -"
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
      (import <nixos-unstable> { config = pkgs.config; }).rustup
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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILBpGNJCiAT2fYCZjVKHlnubTqUIpGWMRQiOdtC05kUy browser"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEnU+OsWjdqZ0JnF1r8aAIjSsbKkX2XYDUcyvbOk7vr0 fairphone"
    ];
  };

  # install my home manager stuff
  home-manager.useGlobalPkgs = true;
  home-manager.users.philipp = import /home/philipp/program/nix/home-manager/home.nix;

  # enable nix flakes
  nix.settings.experimental-features = "nix-command flakes";

  # Claude Desktop downloads its own Claude Code executables after installation.
  programs.nix-ld.enable = true;

  # Install firefox.
  programs.firefox.enable = true;
  programs.firefox.package =
    (import <nixos-unstable> { config = pkgs.config; }).firefox;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    android-tools
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
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      Environment = "RUST_LOG=info";
      ExecStart = "${pigeons}/bin/pigeons roost";
      Restart = "on-failure";
      RestartSec = 3;
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
