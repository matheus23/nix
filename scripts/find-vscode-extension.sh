#! /usr/bin/env nix-shell
#! nix-shell -i bash -p curl jq unzip

# Based on
# https://github.com/NixOS/nixpkgs/blob/42d815d1026e57f7e6f178de5a280c14f7aba1a5/pkgs/misc/vscode-extensions/update_installed_exts.sh

N="$1.$2"

# Create a tempdir for the extension download.
EXTTMP=$(mktemp -d -t vscode_exts_XXXXXXXX)

URL="https://$1.gallery.vsassets.io/_apis/public/gallery/publisher/$1/extension/$2/latest/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage"

# Quietly but delicately curl down the file, blowing up at the first sign of trouble.
curl --silent --show-error --retry 3 --fail -X GET -o "$EXTTMP/$N.zip" "$URL"
# Unpack the file we need to stdout then pull out the version
VER=$(jq -r '.version' <(unzip -qc "$EXTTMP/$N.zip" "extension/package.json"))
# Calculate the hash
HASH=$(nix-hash --flat --sri --type sha256 "$EXTTMP/$N.zip")

# Clean up.
rm -Rf "$EXTTMP"
# I don't like 'rm -Rf' lurking in my scripts but this seems appropriate.

cat <<-EOF
  {
    name = "$2";
    publisher = "$1";
    version = "$VER";
    hash = "$HASH";
  }
EOF
