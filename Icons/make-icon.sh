#!/usr/bin/env bash
# Renders the master PNG (make-icon.swift) and assembles Icons/AppIcon.icns.
# The bundler (swift package bundle-app) copies that into the .app.
set -euo pipefail
cd "$(dirname "$0")/.."
work="$(mktemp -d)"
swift Icons/make-icon.swift "$work/icon_1024.png" 1024
iconset="$work/AppIcon.iconset"; mkdir -p "$iconset"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s"   "$work/icon_1024.png" --out "$iconset/icon_${s}x${s}.png"     >/dev/null
  d=$((s * 2)); sips -z "$d" "$d" "$work/icon_1024.png" --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o Icons/AppIcon.icns
cp "$work/icon_1024.png" Icons/preview.png   # for review only; not committed
echo "wrote Icons/AppIcon.icns"
