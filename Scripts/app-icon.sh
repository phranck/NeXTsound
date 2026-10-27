#!/bin/bash
# Renders the icons' subjects in Blender and writes an Icon Composer file for each from it and the shared vector layers:
# the driver for App/Application/AppIcon.icon, and the printed sheet for App/Icons/ProfileIcon.icon, the icon of a
# sound profile file. The first argument sets Blender's samples, 256 by default. Further arguments name the subjects
# to render, driver and sheet by default.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

blender=$(command -v blender) || {
    echo "Blender renders the icons' subjects; install it with: brew install --cask blender" >&2
    exit 1
}
samples=${1:-256}
shift || true
subjects=("$@")
if [ ${#subjects[@]} -eq 0 ]; then
    subjects=(driver sheet)
fi
work=$(mktemp -d /tmp/nxs-app-icon.XXXXXX)
trap 'rm -rf "$work"' EXIT
# The sheet's print takes Inter Tight's faces from files of their own, which app-icon-fonts.py fetches and writes
# with fontTools.
python3 "$root/Scripts/app-icon-fonts.py" "$work/fonts" > /dev/null
export NXS_ICON_FONTS="$work/fonts"
for subject in "${subjects[@]}"; do
    case "$subject" in
        driver) icon="$root/App/Application/AppIcon.icon" ;;
        sheet) icon="$root/App/Icons/ProfileIcon.icon" ;;
        *) echo "Unknown subject: $subject" >&2; exit 1 ;;
    esac
    if ! "$blender" -b --factory-startup -P "$root/Scripts/app-icon-render.py" -- "$subject" "$work/$subject.png" "$samples" \
        > "$work/$subject.log" 2>&1; then
        cat "$work/$subject.log" >&2
        exit 1
    fi
    python3 "$root/Scripts/app-icon-layers.py" "$work/$subject.png" "$icon"
done
