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
    ./hardware-configuration.nix
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-t14-amd-gen3
  ];

  # 511 MiB ESP
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.loader.efi.efiSysMountPoint = "/boot/efi";

  # Virtual camera & mic
  boot.extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback.out ];

  boot.kernelModules = [
    "v4l2loopback"
    "snd-aloop"
  ];

  boot.extraModprobeConfig = ''
    # https://github.com/umlaeute/v4l2loopback
    options v4l2loopback exclusive_caps=1 card_label="Virtual Camera"
  '';

  networking.hostName = "nixos";

  time.timeZone = lib.mkForce null; # let GNOME manage timezone

  services.fprintd.enable = true;

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
  # thermald for better performance? https://github.com/NixOS/nixpkgs/issues/211345#issuecomment-1387032707
  services.thermald.enable = true;

  # Actually, disable CUPS. I don't need it right now https://news.ycombinator.com/item?id=41662596
  services.printing.enable = false;

  # Dedicated user for the agent-box pigeons roost (port 2222)
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
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };

  home-manager.users.philipp.custom.discord-archive.spkiHash =
    "Qz1SMdBbcL2Mu17BB9q31qlkKyKKUeyIav3KIhtYZKE=";

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      # 1420 # used by tauri/vite
      # 1421 # used for HMR by tauri/vite
    ];
  };

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

  systemd.services.pigeons.serviceConfig.Environment = "RUST_LOG=info,iroh=debug";

  # Separate roost for agent-box sshd on 127.0.0.1:2222 (endpoint ID in journalctl -u pigeons-agent)
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

  # Sandboxed agent container, reachable via pigeons-agent on 127.0.0.1:2222
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

  system.stateVersion = "22.11";
}
