{
  description = "flakes";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    # fixes https://github.com/NixOS/nixpkgs/issues/298285
    # using nixpkgs from that branch until it's merged
    nixpkgs-androidenv.url = "github:hadilq/nixpkgs/androidenv-fix-ndk-toolchains";
    flake-utils.url = "github:numtide/flake-utils";
    command-utils.url = "github:expede/nix-command-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      nixpkgs-androidenv,
      command-utils,
      flake-utils,
      rust-overlay,
    }:
    flake-utils.lib.eachDefaultSystem (system: {
      # A devShell for tauri development
      devShells.tauri =
        let
          overlays = [ (import rust-overlay) ];
          pkgs = import nixpkgs {
            inherit system overlays;
            config.android_sdk.accept_license = true;
            config.allowUnfree = true;
          };

          androidenvPkgs = import nixpkgs-androidenv {
            inherit system overlays;
            config.android_sdk.accept_license = true;
            config.allowUnfree = true;
          };

          nightly-rustfmt = pkgs.rust-bin.nightly.latest.rustfmt;

          androidComposition = androidenvPkgs.androidenv.composeAndroidPackages {
            platformVersions = [
              "33"
              "32"
            ];
            buildToolsVersions = [ "30.0.3" ];
            includeEmulator = false; # haven't figured it out yet...
            includeNDK = true;
            # may need to wait for https://github.com/NixOS/nixpkgs/pull/300386 to land
            ndkVersion = "26.1.10909125";
          };
        in
        pkgs.mkShell rec {
          name = "tauri";
          nativeBuildInputs =
            with pkgs;
            [
              nightly-rustfmt
              direnv
              corepack # includes pnpm
              pkg-config
              # c libraries needed for tauri on linux desktop
              openssl
              glib.dev
              pango.dev
              libsoup_3.dev
              webkitgtk_4_1.dev
              # needed for rust android compilation (pnpm tauri android dev)
              llvmPackages_13.libcxx
              libxml2
              jdk17
              # android development tools
              androidComposition.androidsdk
              bashInteractive # In an effort to fix the terminal in NixOS: (https://www.reddit.com/r/NixOS/comments/ycde3d/vscode_terminal_not_working_properly/)
            ]
            ++ lib.optionals stdenv.isDarwin [
              darwin.apple_sdk.frameworks.Security
              darwin.apple_sdk.frameworks.CoreFoundation
              darwin.apple_sdk.frameworks.Foundation
            ];

          # env variables so tauri picks up our android sdk install
          ANDROID_SDK_ROOT = "${androidComposition.androidsdk}/libexec/android-sdk";
          ANDROID_NDK_ROOT = "${ANDROID_SDK_ROOT}/ndk-bundle";
          ANDROID_HOME = "${ANDROID_SDK_ROOT}";
          NDK_HOME = "${ANDROID_NDK_ROOT}";

          # For some reason that's needed for the android NDK's clang setup to work
          LD_LIBRARY_PATH = "${pkgs.libxml2.out}/lib";

          # Needed for `tauri android dev` to pick up the jdk
          JAVA_HOME = "${pkgs.jdk17}/lib/openjdk";
        };

      # a shell for gtk development
      devShells.gtk =
        let
          pkgs = import nixpkgs { inherit system; };
          unstable = import nixpkgs-unstable { inherit system; };
        in
        pkgs.mkShell {
          name = "gtk";
          nativeBuildInputs = with pkgs; [
            direnv
            glib
            cairo
            pango
            # atkmm
            # gdk-pixbuf
            gtk4
            graphene
            gtksourceview5
            libadwaita
            pkg-config
            bashInteractive # In an effort to fix the terminal in NixOS: (https://www.reddit.com/r/NixOS/comments/ycde3d/vscode_terminal_not_working_properly/)
          ];

          shellHook = '''';
        };

      # a shell for n0des development
      devShells.n0des =
        let
          pkgs = import nixpkgs { inherit system; };
          unstable = import nixpkgs-unstable { inherit system; };

          pgctl = "${pkgs.postgresql}/bin/pg_ctl";

          cmd = command-utils.cmd.${system};

          pw-drivers = unstable.playwright-driver.browsers;

          command_menu = command-utils.commands.${system} {
            db-start = cmd "Start the postgres database" ''${pgctl} -o "-k /tmp" -D "./.pg" -l postgres.log start'';
            db-stop = cmd "Stop the postgres database" ''${pgctl} -o "-k /tmp" -D "./.pg" stop'';
            db-reset = cmd "Reset the postgres database" ''db-stop && db-start && cargo sqlx database reset --source=ips/backend/migrations'';
          };
        in
        pkgs.mkShell {
          name = "n0des";
          nativeBuildInputs = with pkgs; [
            postgresql
            pgcli
            direnv
            command_menu
            sqlx-cli
            pkg-config
            openssl
            pw-drivers # for e2e playwright tests. **Needs to be same the same version as playwright npm package**
            bashInteractive # In an effort to fix the terminal in NixOS: (https://www.reddit.com/r/NixOS/comments/ycde3d/vscode_terminal_not_working_properly/)
          ];

          # TODO: These paths are all still relative. Should fix that
          shellHook = ''
            # For e2e playwright tests
            export PLAYWRIGHT_BROWSERS_PATH=${pw-drivers}
            export PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true

            # postgres
            export PGDATA="./.pg";
            export PGURL=postgres://philipp@localhost:5432/n0des

            # Setup env variables for easier sqlx CLI usage:
            export DATABASE_URL="$PGURL"

            # make pgcli use /tmp as unix domain socket, otherwise it'll try /run/postgresql, which doesn't work
            export PGHOST="/tmp"

            # Initialize a local database if necessary.
            if [ ! -e $PGDATA ]; then
              echo -e "\nInitializing PostgreSQL in $PGDATA\n"
              initdb $PGDATA --no-instructions -A trust -U philipp
              if pg_ctl -o '-k /tmp' -D $PGDATA start; then
                createdb n0des
                cargo sqlx mig run --source=ips/backend/migrations
                pg_ctl -o '-k /tmp' -D $PGDATA stop
              else
                echo "Unable to start PostgreSQL server on default port (:5432). Maybe a local database is already running?"
              fi
            fi

            if [ ! -e $PGDATA/postmaster.pid ]; then
              echo -e "\nPostgreSQL not running."
              echo
            else
              echo -e "\nPostgreSQL is running."

              echo -e "\nRunning pending sqlx migrations..."
              cargo sqlx mig run --source=ips/backend/migrations
              echo
            fi

            menu
          '';
        };

      # For running netsim/chuck locally
      devShells.netsim =
        let
          pkgs = import nixpkgs { inherit system; };

          ovsScripts = "${pkgs.openvswitch}/share/openvswitch/scripts";

          pyPkgs = with pkgs.python3Packages; [
            pyshark
            drawsvg
            dpkt
            humanfriendly
            mininet-python
          ];

          netsim = pkgs.writeScriptBin "netsim" ''
            #!/bin/sh

            echo "Running with PYTHONPATH: $PYTHONPATH"
            sudo PYTHONPATH=$PYTHONPATH python3 main.py $@
          '';

        in
        pkgs.mkShell {
          buildInputs =
            with pkgs;
            [
              inetutils
              mininet
              openvswitch
              iperf
              tshark
              python3
              netsim
            ]
            ++ pyPkgs;

          shellHook = ''
            export OVS_DBDIR=$(pwd)
            sudo ${ovsScripts}/ovs-ctl start \
              --db-file="$OVS_DBDIR/conf.db" \
              --system-id=random

            sudo ovs-vsctl show

            cleanup() {
              sudo ${ovsScripts}/ovs-ctl stop
              sudo rm $OVS_DBDIR/conf.db
            }
            trap cleanup EXIT
          '';
        };

      # a shell for egui development
      devShells.egui =
        let
          pkgs = import nixpkgs { inherit system; };
          unstable = import nixpkgs-unstable { inherit system; };
        in
        pkgs.mkShell rec {
          name = "egui";
          nativeBuildInputs = with pkgs; [
            cmake
            pkg-config
          ];

          buildInputs = with pkgs; [
            xorg.libX11
            xorg.libXrandr
            xorg.libXcursor
            xorg.libXi
            libxkbcommon
            libGL
            fontconfig
            wayland
          ];

          LD_LIBRARY_PATH = nixpkgs.lib.makeLibraryPath buildInputs;

          shellHook = '''';
        };

      # a shell for iroh-live development (includes AV & GPUI stuff)
      devShells.iroh-live =
        let
          pkgs = import nixpkgs { inherit system; };
        in
        pkgs.mkShell rec {
          name = "iroh-live";
          nativeBuildInputs = with pkgs; [
            pkg-config
            # libpipewire
            pipewire
            # LIBCLANG_PATH
            clang
            rustPlatform.bindgenHook
            # alsa.pc
            alsa-lib
            # egl.pc
            libGL
            # eglexternalplatform
            # libtoolize, aclocal, autoconf bin, required by webrtc-audio-processing-sys crate build
            libtool
            automake
            autoconf
            # ffmpeg-sys-next requirements
            ffmpeg
            # iroh-live-gpui
            libxkbcommon
            libgbm
            xorg.libxcb
          ];
        };

    });

}
