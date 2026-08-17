#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h}"
build_dir="$root_dir/build"
app_dir="$build_dir/BOOX Remote.app"
iconset_dir="$build_dir/AppIcon.iconset"

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$build_dir/module-cache" "$build_dir/icon-source"

swiftc \
  -swift-version 5 \
  -parse-as-library \
  -O \
  -module-cache-path "$build_dir/module-cache" \
  -o "$app_dir/Contents/MacOS/BOOX Remote" \
  "$root_dir/Sources/BooxRemoteApp.swift" \
  -framework SwiftUI \
  -framework AppKit

cp "$root_dir/Info.plist" "$app_dir/Contents/Info.plist"

mkdir -p "$iconset_dir"
qlmanage -t -s 1024 -o "$build_dir/icon-source" "$root_dir/Assets/AppIcon.svg" >/dev/null
source_icon="$build_dir/icon-source/AppIcon.svg.png"

for spec in \
  '16 icon_16x16.png' '32 icon_16x16@2x.png' \
  '32 icon_32x32.png' '64 icon_32x32@2x.png' \
  '128 icon_128x128.png' '256 icon_128x128@2x.png' \
  '256 icon_256x256.png' '512 icon_256x256@2x.png' \
  '512 icon_512x512.png' '1024 icon_512x512@2x.png'; do
  size="${spec%% *}"
  name="${spec#* }"
  sips -z "$size" "$size" "$source_icon" --out "$iconset_dir/$name" >/dev/null
done

iconutil -c icns "$iconset_dir" -o "$build_dir/AppIcon.icns"
cp "$build_dir/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$app_dir"

echo "Built: $app_dir"
