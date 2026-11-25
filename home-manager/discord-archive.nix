# Local Discord gateway tap + SQLite archive (queried by goose over MCP).
{
  config,
  inputs,
  lib,
  pkgs,
  unstable,
  ...
}:

let
  discord-archive = pkgs.callPackage ../custom/discord-archive/package.nix {
    src = inputs.mcp-zoo-src;
  };

  # From `discord-archive tap --print-flags`; SPKI hash is per-host (~/.local/share/discord-archive/tap/key.pem)
  tapFlags = [
    "--proxy-pac-url=data:application/x-ns-proxy-autoconfig;base64,ZnVuY3Rpb24gRmluZFByb3h5Rm9yVVJMKHVybCwgaG9zdCkgewogIGlmIChzaEV4cE1hdGNoKGhvc3QsICJnYXRld2F5Ki5kaXNjb3JkLmdnIikpIHJldHVybiAiUFJPWFkgMTI3LjAuMC4xOjg5NzE7IERJUkVDVCI7CiAgcmV0dXJuICJESVJFQ1QiOwp9Cg=="
    "--ignore-certificate-errors-spki-list=${config.custom.discord-archive.spkiHash}"
  ];
in
{
  options.custom.discord-archive.spkiHash = lib.mkOption {
    type = lib.types.str;
    description = "SPKI hash from `discord-archive tap --print-flags` for this host's tap/key.pem.";
  };

  config = {
    home.packages = [
      discord-archive
      (unstable.discord.override {
        # Wrapper interpolates commandLineArgs unquoted, and the PAC URL has a `;`
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
  };
}
