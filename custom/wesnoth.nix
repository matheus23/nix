# { lib, stdenv, fetchFromGitHub, cmake, pkg-config, SDL2, SDL2_image, SDL2_mixer
# , SDL2_net, SDL2_ttf, pango, gettext, boost, libvorbis, fribidi, dbus, libpng
# , pcre, openssl, icu, Cocoa, Foundation }:

{ pkgs ? import <nixpkgs> { } }:

with pkgs;

stdenv.mkDerivation rec {
  pname = "wesnoth";
  version = "1.17.14";

  src = fetchFromGitHub {
    repo = "wesnoth";
    owner = "wesnoth";
    rev = version;
    hash = "sha256-Ip7OIVV/nsNUNiBeeWSoRlBE2kbPpmGlGxiDdRfGXOo=";
    fetchSubmodules = true;
  };

  # This is a hack to get around wesnoth's CMakeLists.txt script
  # checking for whether the project was submodule-cloned.
  preConfigure = ''
    mkdir src/modules/lua/.git
  '';

  nativeBuildInputs = [ cmake pkg-config ];

  buildInputs = [
    SDL2
    SDL2_image
    SDL2_mixer
    SDL2_net
    SDL2_ttf
    pango
    gettext
    boost
    libvorbis
    fribidi
    dbus
    libpng
    pcre
    openssl
    icu
    curl
  ] ++ lib.optionals stdenv.isDarwin [ Cocoa Foundation ];

  NIX_LDFLAGS = lib.optionalString stdenv.isDarwin "-framework AppKit";

  meta = with lib; {
    description =
      "The Battle for Wesnoth, a free, turn-based strategy game with a fantasy theme";
    longDescription = ''
      The Battle for Wesnoth is a Free, turn-based tactical strategy
      game with a high fantasy theme, featuring both single-player, and
      online/hotseat multiplayer combat. Fight a desperate battle to
      reclaim the throne of Wesnoth, or take hand in any number of other
      adventures.
    '';

    homepage = "https://www.wesnoth.org/";
    license = licenses.gpl2Plus;
    maintainers = with maintainers; [ abbradar ];
    platforms = platforms.unix;
  };
}
