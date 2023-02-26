{ pkgs, ... }:

let
  # Virtual Studio Code config
  vscode = pkgs.vscode-with-extensions.override {
    vscodeExtensions = with pkgs.vscode-extensions;
      [
        matklad.rust-analyzer
        brettm12345.nixfmt-vscode
        ms-vsliveshare.vsliveshare
        eamodio.gitlens
        elmtooling.elm-ls-vscode
        vadimcn.vscode-lldb # LLVM debugger for debugging rust
        denoland.vscode-deno
      ] ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
        # https://github.com/NixOS/nixpkgs/blob/42d815d1026e57f7e6f178de5a280c14f7aba1a5/pkgs/misc/vscode-extensions/update_installed_exts.sh
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
          version = "2.6.0";
          sha256 = "1nsykffx8byyaqr23dql96l25gbwr4rzai0jziw7g5s5hbnmrlc8";
        }
        {
          name = "tldraw-vscode";
          publisher = "tldraw-org";
          version = "1.25.2";
          sha256 = "1vsvlbbmrlify1awqhdsfhb50kf2g0sxwja5096jyn9rqjks2l84";
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
        { # required for ElmLS to work
          name = "vscode-test-explorer";
          publisher = "hbenl";
          version = "2.21.1";
          sha256 = "022lnkq278ic0h9ggpqcwb3x3ivpcqjimhgirixznq0zvwyrwz3w";
        }
        { # Dependency of vscode-test-explorer above
          name = "test-adapter-converter";
          publisher = "ms-vscode";
          version = "0.1.6";
          sha256 = "0pj4ln8g8dzri766h9grdvhknz2mdzwv0lmzkpy7l9w9xx8jsbsh";
        }
        { # Tailwind intellisense ... for deno (fresh)?
          name = "twind-intellisense";
          publisher = "sastan";
          version = "0.2.1";
          sha256 = "1lp7i2fw9ycr6x7rfw7zcr81pch250xw0pdg19xn3ic8wpdwdspp";
        }
      ];
  };

  tdesktop = pkgs.symlinkJoin {
    name = "tdesktop";
    paths = [ pkgs.tdesktop ];
    buildInputs = [ pkgs.makeWrapper ];
    # Unfortunately doesn't seem to have an effect
    postBuild = ''
      wrapProgram $out/bin/telegram-desktop --set XCURSOR_SIZE 24
    '';
  };

  signingPubKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII4oFL+qMOmADJ+KGZwQ13Ma65zcEcXuF4JYjNrjvIr5 nixos git commit signing for philipp.krueger1@gmail.com";

  sessionPath =
    [ "$HOME/.local/bin" "$HOME/.cargo/bin" "/home/philipp/.deno/bin" "$PATH" ];

  _1password = pkgs._1password-gui;

in {
  home.username = "philipp";
  home.homeDirectory = "/home/philipp";
  home.stateVersion = "22.11";

  nixpkgs.config.allowUnfree = true;

  home.sessionPath = sessionPath;

  # I hoped that this fixes home.sessionPath for me under gnome
  # It doesn't.
  home.file.".profile" = {
    executable = true;
    text = "source $HOME/.nix-profile/etc/profile.d/hm-session-vars.sh";
  };

  programs.home-manager.enable = true;

  # VSCode settings "sync"
  home.file.".config/Code/User/settings.json".text =
    builtins.readFile ./vscode/settings.json;

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

  programs.gh = { enable = true; };

  programs.firefox = { enable = true; };

  programs.obs-studio = {
    enable = true;
    plugins = with pkgs.obs-studio-plugins; [ obs-backgroundremoval ];
  };

  home.packages = [
    vscode
    tdesktop
    _1password
    (pkgs.spotify.override { deviceScaleFactor = 2; })
    pkgs.discord
    pkgs.zoom-us
    pkgs.chromium
    pkgs.yarn
    pkgs.nodejs
    pkgs.nixfmt
    pkgs.neofetch # for fun (prints system info)
    pkgs.obsidian
    pkgs.yq
    pkgs.pre-commit
    pkgs.ffmpeg
    pkgs.elmPackages.elm-format
    pkgs.elmPackages.elm
    pkgs.signal-desktop
    pkgs.steam-run
    pkgs.deno
  ];

  # Scripts
  home.file.".local/bin/fisload" = {
    executable = true;
    text = ''
      #!/bin/sh
      LOAD=~/.config/fission-"$1"
      DST=~/.config/fission

      if test -e "$DST"; then
        echo "Please fisunload first";
        exit 1;
      fi

      if test -e "$LOAD"; then
        mv "$LOAD" "$DST"
      else
        echo "Cannot load $1: Not found.";
        exit 1;
      fi

      fission whoami
    '';
  };

  home.file.".local/bin/fisunload" = {
    executable = true;
    text = ''
      #!/bin/sh
      USERNAME="$(yq -r .username ~/.config/fission/config.yaml)"
      mv ~/.config/fission ~/.config/fission-"$USERNAME"

      if [ -z "$1" ]
          then
              exit 0
          else
              fisload "$1"
      fi
    '';
  };
}
