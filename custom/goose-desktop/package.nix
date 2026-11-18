{ goose-desktop, goose-cli }:

let
  backend = goose-cli.overrideAttrs (prev: {
    patches = (prev.patches or [ ]) ++ [
      ./no-model-context-reminder.patch
      ./elicitation-backend.patch
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
  });
in
(goose-desktop.override { goose-cli = backend; }).overrideAttrs (prev: {
  patches = (prev.patches or [ ]) ++ [
    ./sidebar-and-menu.patch
    ./center-chat-column.patch
    ./bounded-thinking.patch
    ./readable-permissions.patch
    ./elicitation-desktop.patch
  ];

  postBuild = (prev.postBuild or "") + ''
    pnpm --dir desktop run typecheck
    pnpm --dir desktop exec vitest run src/acp/__tests__/elicitationRequests.test.ts
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
