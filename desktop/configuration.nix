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
  hermes-agent = builtins.getFlake "github:NousResearch/hermes-agent/ea5a6c216b99319353bddc99b2a1a0c1b2241b6d";

  # hermesSubnet = "172.30.0.0/24";
  # hermesGateway = "172.30.0.1"; # host address on this bridge
  # lmstudioPort = 1234;
in
{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    <home-manager/nixos>
    hermes-agent.nixosModules.default
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "philipps-desktop"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

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
  };

  # install my home manager stuff
  home-manager.useGlobalPkgs = true;
  home-manager.users.philipp = import /home/philipp/program/nix/home-manager/home.nix;

  # enable nix flakes
  nix.settings.experimental-features = "nix-command flakes";

  # Install firefox.
  programs.firefox.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    snapper-gui
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

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

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

  # systemd.services.docker-network-hermes = {
  #   description = "Create the isolated docker network for hermes-agent";
  #   after = [
  #     "docker.service"
  #     "docker.socket"
  #   ];
  #   requires = [ "docker.service" ];
  #   wantedBy = [ "multi-user.target" ];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     RemainAfterExit = true;
  #   };
  #   path = [ config.virtualisation.docker.package ];
  #   script = ''
  #     docker network inspect hermes-net >/dev/null 2>&1 || \
  #       docker network create \
  #         --driver bridge \
  #         --subnet ${hermesSubnet} \
  #         --gateway ${hermesGateway} \
  #         hermes-net
  #   '';
  # };

  # # LM Studio listens on 0.0.0.0:1234, so the container can reach it via the
  # # bridge gateway (the host). Allow that port from the hermes subnet on the
  # # INPUT path (host-directed traffic).
  # networking.firewall.extraInputRules = ''
  #   ip saddr ${hermesSubnet} tcp dport ${toString lmstudioPort} accept
  # '';

  # # Egress isolation: the container reaches the internet via FORWARD, which
  # # docker routes through the DOCKER-USER chain. Drop all forwarded traffic
  # # from the hermes subnet (blocks internet) while allowing return traffic for
  # # already-established connections. Traffic to the host itself (LM Studio on
  # # the bridge gateway) goes through INPUT, not FORWARD, so it is unaffected.
  # networking.firewall.extraCommands = ''
  #   # Idempotent: delete any prior copies before re-inserting at the top.
  #   iptables -D DOCKER-USER -s ${hermesSubnet} -m state --state ESTABLISHED,RELATED -j RETURN 2>/dev/null || true
  #   iptables -D DOCKER-USER -s ${hermesSubnet} -j DROP 2>/dev/null || true

  #   iptables -I DOCKER-USER 1 -s ${hermesSubnet} -j DROP
  #   iptables -I DOCKER-USER 1 -s ${hermesSubnet} -m state --state ESTABLISHED,RELATED -j RETURN
  # '';
  # networking.firewall.extraStopCommands = ''
  #   iptables -D DOCKER-USER -s ${hermesSubnet} -m state --state ESTABLISHED,RELATED -j RETURN 2>/dev/null || true
  #   iptables -D DOCKER-USER -s ${hermesSubnet} -j DROP 2>/dev/null || true
  # '';

  services.hermes-agent = {
    enable = true;

    container.enable = true;
    # container.backend = "docker";

    # container.extraOptions = [
    #   "--network=hermes-net"
    #   "--add-host=host.docker.internal:host-gateway"
    # ];

    container.hostUsers = [ "philipp" ];

    # settings.model.base_url = "http://host.docker.internal:${toString lmstudioPort}/v1";
    settings.model.base_url = "http://localhost:1234/v1";
    settings.model.default = "qwen3.6-35b-a3b";

    environmentFiles = [ "/var/lib/hermes/env" ];
    addToSystemPackages = true;
  };

  # systemd.services.hermes-agent = {
  #   after = [ "docker-network-hermes.service" ];
  #   requires = [ "docker-network-hermes.service" ];
  # };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?

}
