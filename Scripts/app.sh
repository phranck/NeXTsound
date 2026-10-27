#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
select_xcode
bash "$root/Scripts/bootstrap-tools.sh"
bash "$root/Scripts/bootstrap-picotool-usb.sh"
bash "$root/Scripts/firmware.sh"

NXS_XCODEGEN_VERSION=$(jq -r '.tools.xcodegen.version' "$manifest")
NXS_MACOS_MINIMUM=$(xcrun swift package --package-path "$root/App/Workbench" dump-package | \
    jq -er '.platforms[] | select(.platformName == "macos") | .version')
metadata=$(xcrun swift run --package-path "$root/App/Workbench" NeXTsoundWorkbenchRender --document-type)
NXS_PROFILE_IDENTIFIER=$(jq -er '.identifier' <<< "$metadata")
NXS_PROFILE_EXTENSION=$(jq -er '.file_extension' <<< "$metadata")
NXS_PROFILE_LEGACY_EXTENSION=$(jq -er '.legacy_file_extension' <<< "$metadata")
read -r NXS_APP_VERSION NXS_BUILD_NUMBER < <(bash "$root/Scripts/app-version.sh")
export NXS_XCODEGEN_VERSION NXS_MACOS_MINIMUM NXS_PROFILE_IDENTIFIER NXS_PROFILE_EXTENSION NXS_PROFILE_LEGACY_EXTENSION
export NXS_APP_VERSION NXS_BUILD_NUMBER
generator=$(tool_executable xcodegen)
"$generator" generate --spec "$root/App/project.yml" --project "$root/App"

for configuration in Debug Release; do
    xcodebuild -quiet -project "$root/App/NeXTsound.xcodeproj" -scheme NeXTsound \
        -configuration "$configuration" -destination 'generic/platform=macOS' \
        -derivedDataPath "$root/.build/macOS" build
    printf '%s app: %s\n' "$configuration" "$root/.build/macOS/Build/Products/$configuration/NeXTsound.app"
done
printf 'App version %s, build %s\n' "$NXS_APP_VERSION" "$NXS_BUILD_NUMBER"
