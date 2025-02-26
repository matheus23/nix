{ pkgs, config, ... }:

let
  unstable = import <nixos-unstable> { config = config.nixpkgs.config; };

  # Virtual Studio Code config
  vscode = pkgs.vscode-with-extensions.override {
    vscodeExtensions =
      with pkgs.vscode-extensions;
      [
        # rust-lang.rust-analyzer
        brettm12345.nixfmt-vscode
        # ms-vsliveshare.vsliveshare
        eamodio.gitlens
        elmtooling.elm-ls-vscode
        vadimcn.vscode-lldb
        denoland.vscode-deno
        svelte.svelte-vscode
        mkhl.direnv
      ]
      ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
        # https://github.com/NixOS/nixpkgs/blob/42d815d1026e57f7e6f178de5a280c14f7aba1a5/pkgs/misc/vscode-extensions/update_installed_exts.sh
        {
          name = "rust-analyzer";
          publisher = "rust-lang";
          version = "0.4.2313";
          sha256 = "0jsvqn6f0a9dlfjdh8m29g7smvi1ay6if2mlildwgibip4j2r5ha";
        }
        {
          name = "theme-atom-one-light";
          publisher = "b4456609";
          version = "0.2.4";
          sha256 = "08a7v7i9vap15ygahfh9gcmr0m1mzikh3w3h8ajan6skadb6zfpf";
        }
        {
          name = "Nix";
          publisher = "bbenoist";
          version = "1.0.1";
          sha256 = "0zd0n9f5z1f0ckzfjr38xw2zzmcxg1gjrava7yahg5cvdcw6l35b";
        }
        {
          name = "elm-ls-vscode";
          publisher = "elmTooling";
          version = "2.8.0";
          sha256 = "1yy1xya1jzcah6fg5p729z97ca6777x42b68iv4l4wyqv204fnzk";
        }
        {
          name = "tldraw-vscode";
          publisher = "tldraw-org";
          version = "2.0.11";
          sha256 = "0649kigssry5vvjmdf06g3fr2bsnjp0a7sb3dvazi9qwp00c80c9";
        }
        {
          name = "even-better-toml";
          publisher = "tamasfe";
          version = "0.19.0";
          sha256 = "0xfnprgbafy7sfdqwdw92lr8k3h3fbylvhq1swgv31akndm9191j";
        }
        {
          name = "wati";
          publisher = "NateLevin";
          version = "1.0.3";
          sha256 = "0halx02zjgsara63qqyrgnjc1w9mxcb8ir4ywsvwgcnk7kg1iczv";
        }
        {
          name = "vscode-wasm";
          publisher = "dtsvet";
          version = "1.4.0";
          sha256 = "0p3a8brwpbg3fkhpq257jp7dnydk5b89ramb5yqpdp4yaksvfry5";
        }
        {
          # required for ElmLS to work
          name = "vscode-test-explorer";
          publisher = "hbenl";
          version = "2.21.1";
          sha256 = "022lnkq278ic0h9ggpqcwb3x3ivpcqjimhgirixznq0zvwyrwz3w";
        }
        {
          # Dependency of vscode-test-explorer above
          name = "test-adapter-converter";
          publisher = "ms-vscode";
          version = "0.1.6";
          sha256 = "0pj4ln8g8dzri766h9grdvhknz2mdzwv0lmzkpy7l9w9xx8jsbsh";
        }
        {
          # Tailwind intellisense ... for deno (fresh)?
          name = "twind-intellisense";
          publisher = "sastan";
          version = "0.2.1";
          sha256 = "1lp7i2fw9ycr6x7rfw7zcr81pch250xw0pdg19xn3ic8wpdwdspp";
        }
        {
          # zig language server & more
          name = "vscode-zig";
          publisher = "ziglang";
          version = "0.5.1";
          sha256 = "1m25bbgfv8x8f0ywadjwsmh4myqgp8xwf5yjrkskgr8axj8ny36a";
        }
      ];
  };

  signingPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII4oFL+qMOmADJ+KGZwQ13Ma65zcEcXuF4JYjNrjvIr5 nixos git commit signing for philipp.krueger1@gmail.com";

  sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.cargo/bin"
    "/home/philipp/.deno/bin"
    "$PATH"
  ];

  _1password = pkgs._1password-gui;

in
{
  home.username = "philipp";
  home.homeDirectory = "/home/philipp";
  home.stateVersion = "22.11";

  nixpkgs.config.allowUnfree = true;
  # I wish I knew what needed this. :|
  nixpkgs.config.permittedInsecurePackages = [
    "electron-24.8.6"
    "electron-25.9.0"
  ];

  home.sessionPath = sessionPath;

  # I hoped that this fixes home.sessionPath for me under gnome
  # It doesn't.
  home.file.".profile" = {
    executable = true;
    text = "source $HOME/.nix-profile/etc/profile.d/hm-session-vars.sh";
  };

  # Let's also try this
  programs.bash.initExtra = "source $HOME/.nix-profile/etc/profile.d/hm-session-vars.sh";

  programs.home-manager.enable = true;

  # VSCode settings "sync"
  home.file.".config/Code/User/settings.json".text = builtins.readFile ./vscode/settings.json;

  # Git stuff

  programs.git = {
    enable = true;
    userName = "Philipp Krüger";
    userEmail = "philipp.krueger1@gmail.com";
    signing.key = signingPubKey;
    signing.signByDefault = true;

    extraConfig = {
      init.defaultBranchName = "main";
      init.defaultbranch = "main";
      pull.ff = "only";
      core.excludesfile = "/home/philipp/.config/git/gitignore_global";

      rerere.enabled = "true";

      # https://calebhearth.com/sign-git-with-ssh
      gpg.format = "ssh";
      gpg.ssh.allowedSignersFile = "/home/philipp/.ssh/allowed_signers";

      # Configure 1password as signer (https://blog.1password.com/1password-ssh-agent/):
      # gpg.ssh.program = "${_1password}/share/1password/op-ssh-sign";
      # can't get it to work :( I get "agent returned an error" when invoking op-ssh-sign
    };
  };

  home.file.".ssh/allowed_signers".text = ''
    * ${signingPubKey}
  '';

  programs.gh = {
    enable = true;
  };

  programs.firefox = {
    enable = true;
  };

  programs.obs-studio = {
    enable = true;
    plugins = with pkgs.obs-studio-plugins; [ obs-backgroundremoval ];
  };

  home.packages = [
    vscode
    _1password
    (pkgs.spotify.override { deviceScaleFactor = 2; })
    pkgs.discord
    pkgs.zoom-us
    pkgs.chromium
    pkgs.yarn
    pkgs.nodejs_23
    pkgs.nixfmt-rfc-style
    pkgs.neofetch # for fun (prints system info)
    pkgs.obsidian
    pkgs.yq
    pkgs.jq
    pkgs.pre-commit
    pkgs.ffmpeg
    pkgs.elmPackages.elm-format
    pkgs.elmPackages.elm
    unstable.signal-desktop # we need unstable for the latest version, so it actually works.
    pkgs.steam-run
    pkgs.deno
    pkgs.slack
    pkgs.brave
    pkgs.cargo-nextest
    pkgs.cargo-audit
    pkgs.cargo-deny
    pkgs.cargo-modules
    pkgs.cargo-workspaces
    pkgs.cargo-insta
    pkgs.cargo-udeps
    pkgs.cargo-bloat
    pkgs.cargo-make
    pkgs.cargo-watch
    pkgs.cargo-release
    pkgs.cargo-semver-checks
    # (import ../custom/wesnoth.nix { pkgs = pkgs; })
    pkgs.figma-linux
    pkgs.kubo
    # Fonts
    # (import ../custom/ideal-fonts.nix { pkgs = pkgs; }) # Couldn't get this to be picked up by figma-linux.
    pkgs.overpass
    pkgs.gimp
    # pkgs.fuse3
    pkgs.protobuf
    pkgs.tailscale
    pkgs.linuxKernel.packages.linux_6_1.perf # need to update this with the current compiler version
    pkgs.hotspot
    pkgs.binaryen
    # unstable.wasm-bindgen-cli
    pkgs.zig
    pkgs.prismlauncher # minecraft (with mods)
    pkgs.nfs-utils
    pkgs.nix-index
    pkgs.rust-analyzer
    pkgs.shotcut
    pkgs.musescore
    pkgs.direnv
    pkgs.maestral
    pkgs.maestral-gui
    pkgs.lnav # this is really a pretty decent log viewer
    pkgs.git-filter-repo
    unstable.zed-editor
  ];

  dconf.settings = {
    # Let gnome handle my time zone
    "org/gnome/desktop/datetime" = {
      automatic-timezone = true;
    };
  };
}
