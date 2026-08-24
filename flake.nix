{
  description = "flakes";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.11";
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
              llvmPackages.libcxx
              libxml2
              jdk17
              # android development tools
              androidComposition.androidsdk
              bashInteractive # In an effort to fix the terminal in NixOS: (https://www.reddit.com/r/NixOS/comments/ycde3d/vscode_terminal_not_working_properly/)
              # for iroh-ble-transport
              dbus
              nasm
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

          test-compose = pkgs.writeText "svc-test-compose.yml" ''
            name: svc-test

            services:
              stripe-mock:
                image: stripe/stripe-mock:latest@sha256:24f145e3dfffda8b55c09ca3babf5dcd117e49138a93590c7dd617f03be41117
                ports:
                  - "127.0.0.1:12111:12111"
                restart: unless-stopped

              ses:
                image: dasprid/aws-ses-v2-local@sha256:051c11414ff3be674d3218db0e9539ca2e42a4e5f0efb65133064fe5d54fa7e4
                ports:
                  - "127.0.0.1:8005:8005"
                restart: unless-stopped

              greenmail:
                image: greenmail/standalone:2.1.2@sha256:572d22796908375678119a13fabfcdc5416c9003404ab975fe824692fe02ba03
                ports:
                  - "127.0.0.1:3025:3025"
                  - "127.0.0.1:3143:3143"
                environment:
                  GREENMAIL_OPTS: -Dgreenmail.setup.test.all -Dgreenmail.hostname=0.0.0.0 -Dgreenmail.auth.disabled -Dgreenmail.verbose
                  JAVA_OPTS: -Djava.net.preferIPv4Stack=true -Xmx256m
                restart: unless-stopped
          '';

          command_menu = command-utils.commands.${system} {
            db-start = cmd "Start the postgres database" ''${pgctl} -o "-k /tmp -c max_connections=300" -D "$PGDATA" -l "$PWD/.data/postgres.log" start'';
            db-stop = cmd "Stop the postgres database" ''${pgctl} -o "-k /tmp" -D "$PGDATA" stop'';
            db-reset = cmd "Reset the postgres database" "db-stop && db-start && cargo sqlx database reset --source=backend/migrations";
            test-services-up = cmd "Start Stripe, SES, and Greenmail test services" ''
              set -e
              docker compose -f ${test-compose} up -d
              for service in stripe-mock:12111 ses:8005 greenmail-smtp:3025 greenmail-imap:3143; do
                name="''${service%:*}"
                port="''${service#*:}"
                for attempt in $(seq 1 30); do
                  if nc -z 127.0.0.1 "$port" 2>/dev/null; then
                    echo "$name is ready on 127.0.0.1:$port"
                    break
                  fi
                  if [ "$attempt" -eq 30 ]; then
                    echo "$name did not become ready on 127.0.0.1:$port" >&2
                    docker compose -f ${test-compose} logs
                    exit 1
                  fi
                  sleep 1
                done
              done
            '';
            test-services-down = cmd "Stop Stripe, SES, and Greenmail test services" ''docker compose -f ${test-compose} down'';
            svc-test = cmd "Run svc workspace tests with local service dependencies" ''test-services-up && cargo nextest run --workspace --no-fail-fast'';
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
            netcat
            pkg-config
            openssl
            pw-drivers # for e2e playwright tests. **Needs to be same the same version as playwright npm package**
            bashInteractive # In an effort to fix the terminal in NixOS: (https://www.reddit.com/r/NixOS/comments/ycde3d/vscode_terminal_not_working_properly/)
            stripe-cli
          ] ++ [
            unstable.docker-client
            unstable.docker-compose
          ];

          shellHook = ''
            # For e2e playwright tests
            export PLAYWRIGHT_BROWSERS_PATH=${pw-drivers}
            export PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true

            # Use the desktop's rootless Podman service through its Docker-compatible API.
            export DOCKER_HOST="unix:///run/user/$(id -u)/podman/podman.sock"

            # Keep local application and npm state inside svc's ignored .data directory.
            export XDG_DATA_HOME="$PWD/.data"
            export NPM_CONFIG_CACHE="$PWD/.data/npm-cache"
            mkdir -p "$XDG_DATA_HOME" "$NPM_CONFIG_CACHE"

            # postgres
            export PGDATA="$PWD/.data/postgres"
            export PGURL=postgres://philipp@127.0.0.1:5432/iroh_services

            # Setup env variables for easier sqlx CLI usage:
            export DATABASE_URL="$PGURL"
            export SQLX_OFFLINE=true

            # make pgcli use /tmp as unix domain socket, otherwise it'll try /run/postgresql, which doesn't work
            export PGHOST="/tmp"

            # Initialize a local database if necessary.
            if [ ! -e "$PGDATA/PG_VERSION" ]; then
              echo -e "\nInitializing PostgreSQL in $PGDATA\n"
              mkdir -p "$(dirname "$PGDATA")"
              initdb "$PGDATA" --no-instructions -A trust -U philipp
              if pg_ctl -o '-k /tmp -c max_connections=300' -D "$PGDATA" -l "$PWD/.data/postgres.log" start; then
                createdb iroh_services
                pg_ctl -o '-k /tmp' -D "$PGDATA" stop
              else
                echo "Unable to start PostgreSQL server on default port (:5432). Maybe a local database is already running?"
              fi
            fi

            if ! pg_ctl -D "$PGDATA" status > /dev/null 2>&1; then
              echo -e "\nPostgreSQL not running."
              echo
            else
              echo -e "\nPostgreSQL is running."
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
            vulkan-headers
            vulkan-loader

            libva # for cros-libva
            nasm # for building rav1d
          ];
        };

      # a shell for anything that requires running playwright
      devShells.playwright =
        let
          pkgs = import nixpkgs { inherit system; };
          unstable = import nixpkgs-unstable { inherit system; };
          pw-drivers = unstable.playwright-driver.browsers;
        in
        pkgs.mkShell {
          name = "playwright";

          nativeBuildInputs = with pkgs; [
            pkg-config
            openssl
            pw-drivers # for e2e playwright tests. **Needs to be same the same version as playwright npm package**
            bashInteractive # In an effort to fix the terminal in NixOS: (https://www.reddit.com/r/NixOS/comments/ycde3d/vscode_terminal_not_working_properly/)
          ];

          # For playwright tests
          PLAYWRIGHT_BROWSERS_PATH = "${pw-drivers}";
          PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
        };

      # a shell for dioxus development
      devShells.dioxus =
        let
          pkgs = import nixpkgs { inherit system; };
          unstable = import nixpkgs-unstable { inherit system; };
        in
        pkgs.mkShell {
          name = "dioxus";

          nativeBuildInputs = with pkgs; [
            pkg-config
            openssl
            unstable.dioxus-cli

            # a bunch of glib stuff
            glib
            cairo
            pango
            gdk-pixbuf
            gtk3
            # graphene
            # gtksourceview5
            # libadwaita

            # atk seem to be required
            atkmm

            # webkitgtk
            webkitgtk_4_1

            # required for n0me
            xdo
            sqlite
          ];
        };

      # adapted from https://github.com/bevyengine/bevy/blob/latest/docs/linux_dependencies.md#nix
      devShells.bevy =
        let
          pkgs = import nixpkgs { inherit system; };
          # unstable = import nixpkgs-unstable { inherit system; };
          # tracy = import ./custom/tracy.nix { inherit unstable; };
        in
        with pkgs;
        mkShell {
          buildInputs = [
            pkg-config
          ]
          ++ lib.optionals (lib.strings.hasInfix "linux" system) [
            # for Linux
            # Audio (Linux only)
            alsa-lib
            # Cross Platform 3D Graphics API
            vulkan-loader
            # For debugging around vulkan
            vulkan-tools
            # Other dependencies
            libudev-zero
            xorg.libX11
            xorg.libXcursor
            xorg.libXi
            xorg.libXrandr
            libxkbcommon
            wayland # had to add this myself
            # meh let's just add this, it's really useful
            # tracy
            bashInteractive # In an effort to fix the terminal in NixOS: (https://www.reddit.com/r/NixOS/comments/ycde3d/vscode_terminal_not_working_properly/)
          ];
          LD_LIBRARY_PATH = lib.makeLibraryPath [
            vulkan-loader
            xorg.libX11
            xorg.libXi
            xorg.libXcursor
            libxkbcommon
          ];
        };

      # a shell for building llama.cpp
      devShells.llama-cpp =
        let
          pkgs = import nixpkgs { inherit system; };
          # CMake's FindVulkan.cmake looks for:
          #   $VULKAN_SDK/include/vulkan/vulkan.h  (from vulkan-headers)
          #   $VULKAN_SDK/lib/libvulkan.so         (from vulkan-loader)
          # The patched ggml-vulkan CMakeLists also appends $VULKAN_SDK to
          # CMAKE_PREFIX_PATH so find_package(SPIRV-Headers CONFIG) succeeds,
          # which requires:
          #   $VULKAN_SDK/share/cmake/SPIRV-Headers/SPIRV-HeadersConfig.cmake
          #                                        (from spirv-headers)
          vulkan-combined = pkgs.symlinkJoin {
            name = "vulkan-combined";
            paths = with pkgs; [
              vulkan-headers
              vulkan-loader
              spirv-headers
            ];
          };
        in
        pkgs.mkShell rec {
          name = "llama-cpp";
          nativeBuildInputs = with pkgs; [
            pkg-config
            cmake
            ninja
            # LIBCLANG_PATH - keep clang on PATH for compiler, libclang for bindgen
            clang
            llvmPackages_20.libclang

            vulkan-headers
            vulkan-loader
            vulkan-validation-layers
            vulkan-tools        # vulkaninfo
            shaderc.bin         # glslc - required by find_package(Vulkan COMPONENTS glslc REQUIRED)
            spirv-headers
            renderdoc           # Graphics debugger
            tracy               # Graphics profiler
            vulkan-tools-lunarg # vkconfig
          ];

          LIBCLANG_PATH = "${pkgs.llvmPackages_20.libclang.lib}/lib";
          # vulkan-loader needed at runtime to dlopen libvulkan.so
          LD_LIBRARY_PATH = "${pkgs.vulkan-loader}/lib";
          # Single SDK root with headers, loader, and SPIRV-Headers cmake config
          VULKAN_SDK = "${vulkan-combined}";
          VK_LAYER_PATH = "${pkgs.vulkan-validation-layers}/share/vulkan/explicit_layer.d";
        };

      # ...
    });

}
