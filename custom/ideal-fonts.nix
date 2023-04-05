{ pkgs ? import <nixpkgs> { } }:

with pkgs;

stdenvNoCC.mkDerivation rec {
  pname = "ideal-fonts";
  version = "20230404T175907Z-001";

  nativeBuildInputs = [ unzip ];
  buildInputs = [ unzip ];

  src = ../../fonts/IDEAL-20230404T175907Z-001.zip;

  installPhase = ''
    runHook preInstall

    echo "$PWD"
    ls 'PP Fragment'/otf/*.otf
    ls 'PP Fragment'/ttf/*.ttf
    ls 'Uncut Sans'/Static/*.otf
    ls 'Uncut Sans'/Static/*.ttf

    install -Dm644 -t $out/share/fonts/opentype */*/*.otf
    install -Dm644 -t $out/share/fonts/truetype */*/*.ttf

    install -Dm644 -t $out/share/fonts/opentype */*/*.otf
    install -Dm644 -t $out/share/fonts/truetype */*/*.ttf

    runHook postInstall
  '';

  # install -Dm644 "Uncut Sans/*.ttf" -t $out/share/fonts/truetype
  # install -Dm644 "PP Fragment/variable/*.ttf" -t $out/share/fonts/truetype

  meta = with lib; {
    description = "The Fission Branding's IDEAL fonts";
    longDescription = ''
      The Fission Branding's IDEAL font set including PP Fragment and Uncut Sans,
      but excluding Overpass Mono, since that's available on nixpkgs.
    '';

    homepage = "";
    license = {
      shortName = "Proprietary";
      free = false;
      deprecated = false;
    };
    maintainers = [ ];
    platforms = platforms.unix;
  };
}
