# Letta Code CLI and its nono-sandboxed `le-nono` wrapper.
{
  pkgs,
  unstable,
  ...
}:

let
  secureNode = import ../custom/nodejs-security.nix { pkgs = unstable; };
  letta-code = pkgs.callPackage ../custom/letta-code/package.nix {
    nodejs_22 = secureNode.nodejs_22;
  };
in
{
  home.packages = [
    letta-code
    (pkgs.callPackage ./le-nono.nix { inherit unstable letta-code; })
  ];
}
