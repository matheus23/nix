# Shared NixOS configuration imported by both desktop and laptop hosts.
{
  inputs,
  lib,
  pkgs,
  unstable,
  ...
}:

let
  pigeons = pkgs.callPackage ./custom/pigeons/package.nix {
    src = inputs.pigeons-src;
  };
in
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
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

  # Bootloader defaults.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable networking.
  networking.networkmanager.enable = true;

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

  # Enable the X11 windowing system and GNOME.
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # Configure keymap in X11 and console.
  services.xserver.xkb = {
    layout = "de";
    variant = "";
  };
  console.keyMap = "de";

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Base user account; host configs extend extraGroups, packages, and SSH keys.
  users.users.philipp = {
    isNormalUser = true;
    description = "Philipp Pohl-Krüger";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4gDlyPtlzJJ5IvuQXSaB3d8uhOrpTYUzon+CLHqPIM philipp.krueger1@gmail.com"
    ];
  };

  # Shared Home Manager configuration; hosts may extend home-manager.users.philipp.
  home-manager.useGlobalPkgs = true;
  home-manager.extraSpecialArgs = {
    inherit inputs unstable;
  };
  home-manager.users.philipp.imports = [ ./home-manager/home.nix ];

  # Enable nix flakes and pin the `nixpkgs` registry entry to this flake's input.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.registry.nixpkgs.flake = inputs.nixpkgs;

  # Allow unfree packages.
  nixpkgs.config.allowUnfree = true;

  # Support running unpatched dynamically linked binaries (e.g. Claude Code, kubo).
  programs.nix-ld.enable = true;

  programs.steam.enable = true;

  environment.systemPackages = [
    pigeons
  ];

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
      Environment = lib.mkDefault "RUST_LOG=info";
      ExecStart = "${pigeons}/bin/pigeons roost";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  # Known host key for GitHub SSH fetches.
  programs.ssh.knownHosts."github.com".publicKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
}
