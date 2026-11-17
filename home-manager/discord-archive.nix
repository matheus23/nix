# Records Discord into a local SQLite archive that goose queries over MCP
# (`discord-archive serve`, which only reads).
#
# The tap service is the archive's only writer. Discord routes only its
# gateway WebSocket through it (channel names and live messages), and every
# 30 minutes it imports Discord's HTTP cache, which holds the history Discord
# loaded while scrolling back. If the tap is down, Discord's PAC script falls
# back to a direct connection and nothing is recorded.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  unstable = import <nixos-unstable> { config = config.nixpkgs.config; };
  discord-archive = pkgs.callPackage ../custom/discord-archive/package.nix { };

  # Output of `discord-archive tap --print-flags`. The SPKI hash belongs to the
  # key in ~/.local/share/discord-archive/tap/key.pem; if that key is ever
  # regenerated, update the flags here.
  tapFlags = [
    "--proxy-pac-url=data:application/x-ns-proxy-autoconfig;base64,ZnVuY3Rpb24gRmluZFByb3h5Rm9yVVJMKHVybCwgaG9zdCkgewogIGlmIChzaEV4cE1hdGNoKGhvc3QsICJnYXRld2F5Ki5kaXNjb3JkLmdnIikpIHJldHVybiAiUFJPWFkgMTI3LjAuMC4xOjg5NzE7IERJUkVDVCI7CiAgcmV0dXJuICJESVJFQ1QiOwp9Cg=="
    "--ignore-certificate-errors-spki-list=iinWnh0zDru6ToeSSHL4daigcE77KK12KnYX3IWwrys="
  ];
in
{
  home.packages = [
    discord-archive
    (unstable.discord.override {
      # The wrapper pastes this string unquoted into a shell script, and the
      # PAC data URL contains a `;`, so each flag must be shell-quoted.
      commandLineArgs = lib.escapeShellArgs tapFlags;
    })
  ];

  systemd.user.services.discord-archive-tap = {
    Unit.Description = "Record Discord's gateway and HTTP cache into the discord-archive database";
    Service = {
      ExecStart = "${discord-archive}/bin/discord-archive tap";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
