#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
build_dir="$project_dir/.build/pingly"
app_dir="$project_dir/dist/Pingly.app"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
module_cache="$build_dir/module-cache"

mkdir -p "$build_dir" "$module_cache" "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

source_files=("$project_dir"/Sources/Pingly/*.swift)

CLANG_MODULE_CACHE_PATH="$module_cache" xcrun swiftc \
  -sdk "$sdk_path" \
  -target arm64-apple-macosx13.0 \
  -parse-as-library \
  "${source_files[@]}" \
  -o "$app_dir/Contents/MacOS/Pingly" \
  -framework SwiftUI \
  -framework AppKit \
  -framework ServiceManagement

cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
xcrun actool "$project_dir/Resources/Assets.xcassets" \
  --compile "$app_dir/Contents/Resources" \
  --platform macosx \
  --minimum-deployment-target 13.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$build_dir/asset-info.plist" \
  >/dev/null

touch "$app_dir"
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
