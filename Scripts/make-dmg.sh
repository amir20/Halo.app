#!/usr/bin/env bash
# Builds Halo.app and packages it into a drag-to-install Halo.dmg.
#
#   ./Scripts/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="Halo.app"
DMG="Halo.dmg"
VOL="Halo"

# 1. Build the .app (release binary + Info.plist + icon + ad-hoc signature).
#    --disable-sandbox lets the plugin run codesign; --allow-writing-to-package-
#    directory lets it write the bundle into the repo.
swift package --disable-sandbox --allow-writing-to-package-directory bundle-app Halo

# 2. Stage the DMG contents: the app plus a symlink to /Applications, so the
#    window shows the classic "drag Halo into Applications" layout.
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$APP" "$staging/"
ln -s /Applications "$staging/Applications"

# 3. Build a compressed (UDZO) disk image.
rm -f "$DMG"
hdiutil create -volname "$VOL" -srcfolder "$staging" -ov -format UDZO "$DMG" >/dev/null
echo "✅ Built $DMG"
