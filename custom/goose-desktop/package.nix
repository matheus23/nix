{
  goose-desktop,
  goose-cli,
  callPackage,
  lib,
  stdenv,
  runCommand,
  patch,
  bash,
  coreutils,
  gnugrep,
  gnused,
  gawk,
  findutils,
}:

let
  nonoShell = callPackage ../nono-shell/package.nix { };
  backend = goose-cli.overrideAttrs (prev: {
    # similar is already vendored upstream. Only the root dependency edge changes.
    cargoDeps = runCommand "goose-context-editor-vendor" { } ''
      cp -R --reflink=auto ${prev.cargoDeps} "$out"
      chmod u+w "$out" "$out/Cargo.lock"
      ${patch}/bin/patch -d "$out" -p1 < ${./compaction-lock.patch}
    '';
    GOOSE_NONO_SHELL_BIN = "${nonoShell}/bin/nono-shell";
    GOOSE_COMPACTION_PATH = lib.makeBinPath [
      bash
      coreutils
      gnugrep
      gnused
      gawk
      findutils
    ];
    patches = (prev.patches or [ ]) ++ [
      ./no-model-context-reminder.patch
      ./elicitation-backend.patch
      ./preserve-client-prompt-id.patch
      ./models-context-length.patch
      ./gufo-reasoning-effort.patch
      ./offline-context-editor.patch
    ];
    doCheck = true;
    cargoTestFlags = [
      "-p"
      "goose"
      "--lib"
      "--features"
      "scheduler"
      "action_required_manager"
    ];
    postCheck = (prev.postCheck or "") + ''
      cargo test --offline --release --target ${stdenv.hostPlatform.rust.rustcTarget} -p goose --features scheduler --lib compaction_editor
      cargo test --offline --release --target ${stdenv.hostPlatform.rust.rustcTarget} -p goose --features scheduler --lib context_mgmt::tests
    '';
  });
in
(goose-desktop.override { goose-cli = backend; }).overrideAttrs (prev: {
  patches = (prev.patches or [ ]) ++ [
    ./sidebar-and-menu.patch
    ./center-chat-column.patch
    ./bounded-thinking.patch
    ./readable-permissions.patch
    ./elicitation-desktop.patch
    ./elicitation-choice-buttons.patch
    ./reconcile-user-message-echoes.patch
  ];

  postBuild = (prev.postBuild or "") + ''
    pnpm --dir desktop run typecheck
    pnpm --dir desktop exec vitest run src/acp/__tests__/elicitationRequests.test.ts src/components/ui/JsonSchemaForm.test.tsx src/acp/__tests__/localMessageEcho.test.ts src/acp/__tests__/sessionNotificationAdapter.test.ts src/acp/__tests__/chatSessionStore.test.ts src/acp/__tests__/prompt.test.ts
  '';

  postFixup = (prev.postFixup or "") + ''
    ln -s ${backend}/bin/goose "$out/bin/goose"
    # Native Wayland windows identify as "goose"; GNOME matches that against
    # the desktop filename, not just StartupWMClass (which covers X11).
    mv "$out/share/applications/goose-desktop.desktop" \
      "$out/share/applications/goose.desktop"
    substituteInPlace "$out/share/applications/goose.desktop" \
      --replace-fail "Exec=goose-desktop" "Exec=$out/bin/goose-desktop" \
      --replace-fail "Icon=goose-desktop" \
        "Icon=$out/share/icons/hicolor/scalable/apps/goose-desktop.svg"
  '';
})
