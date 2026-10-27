#!/bin/bash
# Renders App/Icons/ProfileIcon.icon, the icon of a sound profile file, to App/Generated/ProfileIcon.icns, which the
# app bundles and the profile type names in UTTypeIconFile. Icon Composer's ictool renders every size an .icns holds
# with the system's glass and mask. The ictool that xcrun finds is a different tool without --export-image.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ictool="${DEVELOPER_DIR:-$(xcode-select -p)}/../Applications/Icon Composer.app/Contents/Executables/ictool"
work=$(mktemp -d /tmp/nxs-profile-icon.XXXXXX)
trap 'rm -rf "$work"' EXIT
iconset="$work/ProfileIcon.iconset"
mkdir -p "$iconset" "$root/App/Generated"
for size in 16 32 128 256 512; do
    for scale in 1 2; do
        suffix=$([ "$scale" = 2 ] && echo "@2x" || true)
        image="$iconset/icon_${size}x${size}${suffix}.png"
        "$ictool" "$root/App/Icons/ProfileIcon.icon" --export-image --output-file "$image" --platform macOS \
            --rendition Default --width "$size" --height "$size" --scale "$scale" > /dev/null
        if [ ! -s "$image" ]; then
            echo "ictool rendered no $image" >&2
            exit 1
        fi
    done
done
iconutil -c icns "$iconset" -o "$root/App/Generated/ProfileIcon.icns"
