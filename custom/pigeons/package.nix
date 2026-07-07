{
  lib,
  rustPlatform,
}:

let
  # pigeons is a private repo (n0-computer/pigeons) with no public release
  # yet, so we build straight from the local working tree. Swap this for a
  # `fetchFromGitHub` call (owner "rustonbsd", repo "pigeons", tag <version>)
  # once the project is published publicly.
  root = /home/philipp/program/work/pigeons;

  src = lib.cleanSourceWith {
    name = "pigeons-src";
    src = lib.cleanSource root;
    filter =
      path: type:
      let
        s = toString path;
        rootS = toString root;
        excluded = [
          (rootS + "/target")
          (rootS + "/nix")
          (rootS + "/.github")
          (rootS + "/.claude")
          (rootS + "/media")
          (rootS + "/install.sh")
        ];
        inExcluded = builtins.any (e: s == e || lib.hasPrefix (e + "/") s) excluded;
      in
      s == rootS || !inExcluded;
  };
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "pigeons";
  version = "0.1.1";

  inherit src;

  cargoHash = "sha256-6jfGZNsjqgUY/Yt1Ts64Q2vIB6j5urmMWfFHT+Rhr6U=";

  meta = {
    description = "carrier pigeons for your SSH connections — SSH without an IP, behind NAT/firewall";
    homepage = "https://github.com/n0-computer/pigeons";
    license = lib.licenses.mit;
    mainProgram = "pigeons";
    platforms = lib.platforms.linux;
  };
})
