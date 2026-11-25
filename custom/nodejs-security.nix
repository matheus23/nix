{ pkgs }:

let
  # Drop once nixpkgs ships Node >= 22.23.4 and >= 24.22.1
  patched =
    base: version: hash:
    if pkgs.lib.versionAtLeast base.version version then
      base
    else
      base.overrideAttrs (old: {
        inherit version;
        src = pkgs.fetchurl {
          url = "https://nodejs.org/dist/v${version}/node-v${version}.tar.xz";
          inherit hash;
        };
        # Use bundled deps + CA roots from the security release
        configureFlags = builtins.filter (
          flag:
          flag != "--openssl-use-def-ca-store"
          && !builtins.any (name: flag == "--shared-${name}" || pkgs.lib.hasPrefix "--shared-${name}-" flag) [
            "openssl"
            "cares"
            "sqlite"
            "brotli"
          ]
        ) old.configureFlags;
        postInstall =
          builtins.replaceStrings [ "${pkgs.lib.getDev pkgs.openssl}/include/*" ] [ "" ]
            old.postInstall;
      });
in
{
  nodejs_22 = pkgs.nodejs_22.override {
    nodejs-slim =
      patched pkgs.nodejs-slim_22 "22.23.4"
        "sha256:7b9adc82d612d0a2a863d96c46de2292552e250cee51956ebbe0146c42aacae9";
  };
  nodejs_24 = pkgs.nodejs_24.override {
    nodejs-slim =
      patched pkgs.nodejs-slim_24 "24.22.1"
        "sha256:4f5379796280cdaeb0c2f358fd04b6a16cc4fb7dfa83b5a8c91a9d963b435231";
  };
}
