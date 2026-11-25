# Laptop-specific NixOS configuration. Shared settings live in ../common.nix.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  pigeons = pkgs.callPackage ../custom/pigeons/package.nix {
    src = inputs.pigeons-src;
  };
in
{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    # Hardware quirks for ThinkPad T14 Gen 3 AMD (incl. WiFi).
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-t14-amd-gen3
  ];

  # Laptop ESP mount point (511 MiB ESP — cap boot entries so it stays below full).
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.loader.efi.efiSysMountPoint = "/boot/efi";

  # Enable virtual camera and virtual microphone kernel modules.
  boot.extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback.out ];

  boot.kernelModules = [
    # Virtual Camera
    "v4l2loopback"
    # Virtual Microphone, built-in
    "snd-aloop"
  ];

  boot.extraModprobeConfig = ''
    # exclusive_caps: Skype, Zoom, Teams etc. will only show device when actually streaming
    # card_label: Name of virtual camera, how it'll show up in Skype, Zoom, Teams
    # https://github.com/umlaeute/v4l2loopback
    options v4l2loopback exclusive_caps=1 card_label="Virtual Camera"
  '';

  networking.hostName = "nixos";

  # Allow timezone to be set dynamically by the desktop user.
  time.timeZone = lib.mkForce null;

  # Enable fingerprint reader.
  services.fprintd.enable = true;

  # Use tlp over power-profiles-daemon.
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
  # thermald for better performance: https://github.com/NixOS/nixpkgs/issues/211345#issuecomment-1387032707
  services.thermald.enable = true;

  # Disable CUPS on laptop: https://news.ycombinator.com/item?id=41662596
  services.printing.enable = false;

  # Dedicated system user for the agent container's pigeons roost.
  # Runs separately from the main pigeons service so it gets its own
  # endpoint identity, delivering to the container's sshd on port 2222.
  # Get the endpoint ID with: journalctl -u pigeons-agent -b | grep "id:"
  users.users.pigeons-agent = {
    isSystemUser = true;
    group = "pigeons-agent";
    home = "/var/lib/pigeons-agent";
    createHome = true;
  };
  users.groups.pigeons-agent = { };

  environment.systemPackages = with pkgs; [
    android-tools
    wget
    curl
    gedit
    gnome-tweaks
    vlc
    usbutils
    git
    rustup
    gcc
    bash
    gnumake
    home-manager
    rsync
    pavucontrol
  ];

  # virtualisation.docker.enable = true; # couldn't enable after 25.11 update

  programs.steam = {
    # Open ports in the firewall for Steam Remote Play
    remotePlay.openFirewall = true;
    # Open ports in the firewall for Source Dedicated Server
    dedicatedServer.openFirewall = true;
  };

  # Laptop-specific Home Manager settings (letta-code / nono-shell are desktop-only for now).
  home-manager.users.philipp.custom.discord-archive.spkiHash =
    "Qz1SMdBbcL2Mu17BB9q31qlkKyKKUeyIav3KIhtYZKE=";

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      # 1420 # used by tauri/vite
      # 1421 # used for HMR by tauri/vite
    ];
  };

  # Fonts.
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

  # Extra libraries for nix-ld (fission cli, kubo, etc.).
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc
    zlib
    icu
    nss
    openssl
    curl
    expat
    # openssl_1_1.out
    gmp.out
    ncurses.out
    zlib.out
  ];

  # Verbose iroh logging on the laptop roost.
  systemd.services.pigeons.serviceConfig.Environment = "RUST_LOG=info,iroh=debug";

  # Second pigeons roost for the agent container. Delivers incoming pigeons
  # to the agent-box container's sshd on port 2222 (localhost only).
  # Runs as a separate user so it gets a distinct endpoint identity from
  # the main roost. Tail logs: journalctl -u pigeons-agent -f
  systemd.services.pigeons-agent = {
    description = "pigeons roost — agent container tunnel";
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
      Environment = "RUST_LOG=info,iroh=debug";
      ExecStart = "${pigeons}/bin/pigeons roost --ssh-port 2222";
      Restart = "on-failure";
      RestartSec = 3;
      User = "pigeons-agent";
      Group = "pigeons-agent";
    };
  };

  # Declarative container for the sandboxed agent. Shares the host network
  # (privateNetwork = false) so the pigeons-agent roost can reach it on
  # 127.0.0.1:2222. The agent SSHes in as the `agent` user and gets a
  # fully isolated filesystem — no access to the host's /home or /etc.
  containers.agent-box = {
    autoStart = true;
    privateNetwork = false;
    config =
      { config, pkgs, ... }:
      {
        services.openssh = {
          enable = true;
          settings.PasswordAuthentication = false;
          settings.PermitRootLogin = "no";
          listenAddresses = [
            {
              addr = "127.0.0.1";
              port = 2222;
            }
          ];
        };

        users.users.agent = {
          isNormalUser = true;
          shell = pkgs.bashInteractive;
          openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF3d6FTFTHA4TteYiXhZd9qm95nvkjPIi+RCrEB1nMUT oc-agent@desktop"
          ];
        };

        environment.systemPackages = with pkgs; [
          git
          curl
          wget
        ];

        nix.settings.experimental-features = "nix-command flakes";
        nixpkgs.config.allowUnfree = true;

        system.stateVersion = "25.05";
      };
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.11"; # Did you read the comment?
}
