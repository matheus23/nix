# Sandboxed shell/file MCP server for goose (replaces the Developer extension).
{
  inputs,
  pkgs,
  ...
}:

{
  home.packages = [
    (pkgs.callPackage ../custom/nono-shell/package.nix {
      src = inputs.mcp-zoo-src;
    })
  ];
}
