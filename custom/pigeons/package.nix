{
  lib,
  rustPlatform,
  src,
}:

# pigeons lives in a private repo (n0-computer/pigeons), pinned via the
# `pigeons-src` flake input in flake.nix.
#
# To update pigeons: bump `rev` on `inputs.pigeons-src` in flake.nix, run
# `nix flake lock`, and update `cargoHash` below if Cargo.lock changed
# (set it to lib.fakeHash, rebuild, paste the hash from the error).
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "pigeons";
  version = "0.1.1";

  inherit src;

  cargoHash = "sha256-I9hW0UCFC5eWu/ECs55XsSB3FTKbGQPsy07SskMSbOo=";

  meta = {
    description = "carrier pigeons for your SSH connections — SSH without an IP, behind NAT/firewall";
    homepage = "https://github.com/n0-computer/pigeons";
    license = lib.licenses.mit;
    mainProgram = "pigeons";
    platforms = lib.platforms.linux;
  };
})
