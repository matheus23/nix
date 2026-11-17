# nono-shell: an MCP server for goose that runs shell commands and file edits
# inside a nono sandbox (Landlock + seccomp). The agent asks for more access
# per call; the user approves it in goose's form. It replaces the Developer
# extension's unsandboxed shell, write and edit tools, so that extension is
# disabled in ~/.config/goose/config.yaml.
{ pkgs, ... }:

{
  home.packages = [ (pkgs.callPackage ../custom/nono-shell/package.nix { }) ];
}
