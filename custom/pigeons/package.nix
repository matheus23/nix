{
  lib,
  rustPlatform,
}:

let
  # pigeons lives in a private repo (n0-computer/pigeons). `builtins.fetchGit`
  # clones it over SSH at *evaluation* time, using your ssh-agent / ~/.ssh keys
  # and known_hosts — exactly like a normal `git clone git@github.com:...`.
  #
  # Implications:
  #   - Evaluation must run as a user that can SSH to GitHub. So build with
  #     `nixos-rebuild switch` *without* sudo (nixos-rebuild escalates for the
  #     activation step on its own), or `sudo -E nixos-rebuild switch` to
  #     forward SSH_AUTH_SOCK to root. `sudo nixos-rebuild switch` will fail
  #     because root has no GitHub key.
  #   - The fetched checkout is cached in the Nix store keyed by `rev`, so only
  #     the first eval after a bump touches the network.
  #   - To update pigeons: bump `rev` (and `cargoHash` if Cargo.lock changed —
  #     set it to lib.fakeHash, rebuild, paste the hash from the error).
  src = builtins.fetchGit {
    url = "ssh://git@github.com/n0-computer/pigeons.git";
    ref = "refs/heads/main";
    rev = "0685098c954cc7bf10f008dbce697b3a834db58b";
    shallow = true;
  };
in
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
