#!/bin/bash
# Renders the app icon's driver in Blender and writes App/Application/AppIcon.icon from it and the vector layers.
# An optional argument sets Blender's samples, 256 by default.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

blender=$(command -v blender) || {
    echo "Blender renders the icon's driver; install it with: brew install --cask blender" >&2
    exit 1
}
work=$(mktemp -d /tmp/nxs-app-icon.XXXXXX)
trap 'rm -rf "$work"' EXIT
if ! "$blender" -b --factory-startup -P "$root/Scripts/app-icon-driver.py" -- "$work/driver.png" "${1:-256}" > "$work/blender.log" 2>&1; then
    cat "$work/blender.log" >&2
    exit 1
fi
python3 "$root/Scripts/app-icon-layers.py" "$work/driver.png" "$root/App/Application/AppIcon.icon"
