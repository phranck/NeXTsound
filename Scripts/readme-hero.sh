#!/bin/bash
# Renders the README's hero image from the connected front panel, so it shows the panel as the code draws it.
# Neither Gitea nor GitHub keeps a border-radius in README HTML, so the rounded corners are cut into the file:
# 48 pixels at 1720 pixels wide, which is 24 points where the README shows it at width 860.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

width=1720
radius=48
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

xcrun swift run --package-path "$root/App/Workbench" NeXTsoundWorkbenchRender "$work" >/dev/null
sips -Z "$width" "$work/front-panel-connected@2x.png" --out "$work/scaled.png" >/dev/null

cat > "$work/round.swift" <<'SWIFT'
import AppKit

let arguments = CommandLine.arguments
guard
    let source = NSImage(contentsOfFile: arguments[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil),
    let radius = Double(arguments[3]),
    let space = CGColorSpace(name: CGColorSpace.sRGB),
    let context = CGContext(
        data: nil,
        width: source.width,
        height: source.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
else {
    exit(1)
}
let bounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
context.clip()
context.draw(source, in: bounds)
guard
    let rounded = context.makeImage(),
    let data = NSBitmapImageRep(cgImage: rounded).representation(using: .png, properties: [:])
else {
    exit(1)
}
try data.write(to: URL(fileURLWithPath: arguments[2]))
SWIFT
xcrun swift "$work/round.swift" "$work/scaled.png" "$work/rounded.png" "$radius"

destination="$root/Documentation/Images/front-panel.png"
pngquant --quality 85-98 --speed 1 --strip --force --output "$destination" "$work/rounded.png"
printf 'README hero written to %s\n' "$destination"
