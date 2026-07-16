# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  config,
  pkgs,
  lib,
  ...
}:

let
  pigeons = pkgs.callPackage ../custom/pigeons/package.nix { };
in
{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    # Manually added some quirks to fix WiFi
    <nixos-hardware/lenovo/thinkpad/t14/amd/gen3>

    <home-manager/nixos>
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  # boot.loader.systemd-boot.conigurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot/efi";

  # this was needed to get gnome-keyring to actually be able to
  # have wayland access and be able to show a dialog for auth
  systemd.user.services.gcr-ssh-agent = {
    after = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
  };

  # Enable virtual camera kernel module

  # Make some extra kernel modules available to NixOS
  boot.extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback.out ];

  # Activate kernel modules (choose from built-ins and extra ones)
  boot.kernelModules = [
    # Virtual Camera
    "v4l2loopback"
    # Virtual Microphone, built-in
    "snd-aloop"
  ];

  # Set initial kernel module settings
  boot.extraModprobeConfig = ''
    # exclusive_caps: Skype, Zoom, Teams etc. will only show device when actually streaming
    # card_label: Name of virtual camera, how it'll show up in Skype, Zoom, Teams
    # https://github.com/umlaeute/v4l2loopback
    options v4l2loopback exclusive_caps=1 card_label="Virtual Camera"
  '';

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  # time.timeZone = "Europe/Berlin";
  time.timeZone = lib.mkForce null; # allow TZ to be set by desktop user

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

  # Enable fingerprint reader
  services.fprintd.enable = true;

  # Enable the GNOME Desktop Environment.
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "de";
    variant = "";
  };

  # try tlp over ppd:
  services.power-profiles-daemon.enable = false;
  services.tlp = {
    enable = true;
    settings = {
      RESTORE_THRESHOLDS_ON_BAT = 1;
      # CPU_BOOST_ON_AC = 1;
      # CPU_BOOST_ON_BAT = 0;
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "performance";
    };
  };
  # thermald for better performance?
  services.thermald.enable = true;
  # OOOOH yeah so much better, thank you https://github.com/NixOS/nixpkgs/issues/211345#issuecomment-1387032707

  # Configure console keymap
  console.keyMap = "de";

  # Enable CUPS to print documents.
  # Actually, disable CUPS. I don't need it right now https://news.ycombinator.com/item?id=41662596
  services.printing.enable = false;

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

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.philipp = {
    isNormalUser = true;
    description = "Philipp Pohl-Krüger";
    extraGroups = [
      "networkmanager"
      "wheel"
      # "docker" # had to disable docker after 25.11, but .. this gives the philipp user a sudo workaround it really shouldn't have anyways...
      "adbusers"
    ];
    packages = with pkgs; [ ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4gDlyPtlzJJ5IvuQXSaB3d8uhOrpTYUzon+CLHqPIM philipp.krueger1@gmail.com"
    ];
  };

  # Home manager
  home-manager.useGlobalPkgs = true;
  home-manager.users.philipp = import /home/philipp/program/nix/home/home-manager/home.nix;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = [
    pkgs.wget
    pkgs.curl
    pkgs.gedit
    pkgs.gnome-tweaks
    pkgs.vlc
    pkgs.usbutils
    pkgs.git
    pkgs.rustup
    pkgs.gcc
    pkgs.bash
    pkgs.gnumake
    pkgs.home-manager
    pkgs.rsync
    pkgs.pavucontrol
    (pkgs.callPackage ../custom/pigeons/package.nix { })
  ];

  # virtualisation.docker.enable = true; # couldn't enable after 25.11 update

  programs.steam = {
    enable = true;
    # Open ports in the firewall for Steam Remote Play
    remotePlay.openFirewall = true;
    # Open ports in the firewall for Source Dedicated Server
    dedicatedServer.openFirewall = true;
  };

  # Android development
  programs.adb.enable = true;
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      1420 # used by tauri/vite
      1421 # used for HMR by tauri/vite
    ];
    allowedUDPPortRanges = [
      # {
      #   from = 4000;
      #   to = 4007;
      # }
    ];
  };

  # Fonts!
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    liberation_ttf
    fira-code
    fira-code-symbols
  ];

  # Possible ZSH workaround https://github.com/nix-community/home-manager/issues/2751#issuecomment-1048682643
  programs.zsh.enable = true;

  # Enable nix ld (https://github.com/Mic92/nix-ld)
  # I need this to support running downloaded binaries.
  # Currently that is at least the fission cli & kubo
  programs.nix-ld.enable = true;

  # Sets up all the libraries to load
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc
    zlib
    # fuse3
    icu
    zlib
    nss
    openssl
    curl
    expat
    openssl_1_1.out
    gmp.out
    ncurses.out
    zlib.out
  ];

  # For the above nix-ld stuff (openssl_1_1.out)
  nixpkgs.config.permittedInsecurePackages = [
    "openssl-1.1.1u"
    "openssl-1.1.1w"
    "electron-25.9.0"
  ];

  nix.settings.experimental-features = "nix-command flakes";

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   pinentryFlavor = "gtk2";
  # };
  # services.pcscd.enable = true;

  # List services that you want to enable:

  # pigeons roost: always-on carrier pigeon for SSH. Runs as root at boot, so
  # the endpoint ID is published to /etc/pigeons/endpoint_id and readable via
  # `pigeons service status`. Do NOT also run `pigeons service install` — the
  # unit is defined here declaratively. Restart with:
  #   sudo systemctl restart pigeons
  # Tail logs with: journalctl -u pigeons -f
  systemd.services.pigeons = {
    description = "pigeons roost — carrier pigeon SSH tunnel";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
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

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.11"; # Did you read the comment?
}
