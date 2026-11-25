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

  # Mozilla bug 2083449
  security.pki.caCertificateBlacklist = [
    "Comodo AAA Services root"
  ];

  environment.sessionVariables = {
    SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
    NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;

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

  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.xserver.xkb = {
    layout = "de";
    variant = "";
  };
  console.keyMap = "de";

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

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

  home-manager.useGlobalPkgs = true;
  home-manager.extraSpecialArgs = {
    inherit inputs unstable;
  };
  home-manager.users.philipp.imports = [ ./home-manager/home.nix ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.registry.nixpkgs.flake = inputs.nixpkgs;

  nixpkgs.config.allowUnfree = true;

  programs.nix-ld.enable = true;
  programs.steam.enable = true;

  environment.systemPackages = [
    pigeons
  ];

  # Declarative pigeons roost (don't also run `pigeons service install`).
  # Endpoint ID is published to /etc/pigeons/endpoint_id.
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

  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  programs.ssh.knownHosts."github.com".publicKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
}
