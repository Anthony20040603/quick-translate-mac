#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/quicktranslate-clang-cache"
swift build -c release -debug-info-format none --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
bin_dir="$(swift build -c release --show-bin-path --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security)"
icon_dir="$project_dir/.build/icon-compile"
mkdir -p "$icon_dir"
xcrun actool "$project_dir/Resources/Untitled.icon" --compile "$icon_dir" \
  --platform macosx --minimum-deployment-target 14.0 --app-icon Untitled \
  --output-partial-info-plist "$icon_dir/icon-info.plist" --output-format human-readable-text
xcrun swift "$project_dir/scripts/render-menu-icon.swift" "$project_dir/Resources" "$icon_dir/MenuBarIcon.pdf"
app_dir="$project_dir/build/QuickTranslate.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/QuickTranslate" "$app_dir/Contents/MacOS/QuickTranslate"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/LICENSE" "$project_dir/NOTICE.md" "$app_dir/Contents/Resources/"
cp "$icon_dir/Assets.car" "$icon_dir/Untitled.icns" "$icon_dir/MenuBarIcon.pdf" "$app_dir/Contents/Resources/"
codesign --force --sign - --identifier com.anthony.quicktranslate.mac "$app_dir"
touch "$app_dir"
print "已生成：$app_dir"
