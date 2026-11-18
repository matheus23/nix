# Source of the MCP servers in the private github.com/matheus23/mcp-zoo
# repository, shared by the packages built from it.
#
# Evaluation fetches it over SSH as root, so rebuild with `sudo -E
# nixos-rebuild switch`: -E passes your SSH agent through, which holds a key
# with access to the repository. GitHub's host key comes from
# programs.ssh.knownHosts in each machine's configuration.
#
# Pinned so a rebuild only ships commits you chose: push mcp-zoo, then set
# `rev` to the new commit.
builtins.fetchGit {
  url = "git@github.com:matheus23/mcp-zoo.git";
  ref = "main";
  rev = "cfe9ff194935edb02df582d7117888b3b46ab6d6";
}
