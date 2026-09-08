#!/bin/zsh
#
# Builds CoverArtwall and assembles it into a double-clickable .app bundle
# at dist/Cover Artwall.app.
#
# Set UNIVERSAL=1 to build a universal (arm64 + x86_64) binary, as used for
# release/Homebrew artifacts. Local dev builds default to the host arch.

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_name="Cover Artwall"
executable_name="CoverArtwall"
dist_dir="$project_dir/dist"
app_bundle="$dist_dir/$app_name.app"

echo "Building release binary..."
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  swift build --package-path "$project_dir" -c release --arch arm64 --arch x86_64
  built_binary="$project_dir/.build/apple/Products/Release/$executable_name"
else
  swift build --package-path "$project_dir" -c release
  built_binary="$project_dir/.build/release/$executable_name"
fi

echo "Assembling app bundle..."
rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"

cp "$built_binary" "$app_bundle/Contents/MacOS/$executable_name"
chmod +x "$app_bundle/Contents/MacOS/$executable_name"
cp "$project_dir/Resources/Info.plist" "$app_bundle/Contents/Info.plist"

echo "Ad-hoc code signing..."
codesign --force --deep --sign - "$app_bundle"

echo "Built: $app_bundle"
echo "Drag it into /Applications, then launch it."
