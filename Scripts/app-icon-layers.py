#!/usr/bin/env python3
"""Write the app icon's Icon Composer file from its vector layers and the driver that app-icon-driver.py renders."""

import json
import os
import shutil
import sys

CANVAS = 1024
# The display's dot grid: 25 dots a side, 40 pixels apart.
PITCH = 40
DOT_RADIUS = 10
# The glass rim macOS draws around every icon smears the top two rows of dots, so the grid starts below them.
FIRST_ROW = 2
# The dim area under the curve ends on the row above the stripes.
LAST_FILL_ROW = 18

# The LAYERED colors from top to bottom, the ones FrontPanelPalette and FrontPanelHeaderMetrics.stripeColors hold. The
# icon is drawn outside the app, so it keeps its own copy.
STRIPES = ["#C64616", "#FBAC3E", "#758C34", "#2B7488"]
STRIPE_HEIGHT = 54
STRIPE_GAP = 16
# The blue phosphor theme's bright and ghost steps, as PhosphorTheme holds them, and a dimmed step for the area under
# the curve. The glass is the display's, a little lighter at the top.
PHOSPHOR = "#7AEBFF"
GHOST = "#1B3438"
DIMMED = "#2A5961"
GLASS_TOP, GLASS_BOTTOM = "#16232B", "#05080A"

# The curve's control points in grid columns and rows: a bass lift on the left, a dip that passes behind the driver's
# top, a presence peak on the right, and a dip toward the right edge.
WAVE_POINTS = [
    (0, 7.0), (2, 3.6), (3.5, 2.0), (5.5, 2.4), (8, 4.6), (11, 6.0), (14, 4.6), (16.5, 2.4), (18, 2.2), (19.5, 4.6),
    (21, 9.5), (22.5, 7.6), (24, 5.6),
]


def srgb(hex_color):
    red, green, blue = (int(hex_color[index:index + 2], 16) / 255 for index in (1, 3, 5))
    return f"srgb:{red:.5f},{green:.5f},{blue:.5f},1.00000"


def svg(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}">{body}</svg>\n'


def dots(cells, color):
    """Circles on the grid for the (column, row) cells, in the order given."""
    first = (CANVAS - (CANVAS // PITCH - 1) * PITCH) / 2
    return "".join(
        f'<circle cx="{first + column * PITCH:.1f}" cy="{first + row * PITCH:.1f}" r="{DOT_RADIUS}" fill="{color}"/>'
        for column, row in cells
    )


def curve_rows():
    """The curve's row in every column: a cardinal spline through `WAVE_POINTS`, rounded to whole rows."""
    rows = []
    for column in range(CANVAS // PITCH):
        index = max(position for position, (point_column, _) in enumerate(WAVE_POINTS[:-1]) if point_column <= column)
        before = WAVE_POINTS[max(index - 1, 0)]
        start, end = WAVE_POINTS[index], WAVE_POINTS[index + 1]
        after = WAVE_POINTS[min(index + 2, len(WAVE_POINTS) - 1)]
        span = end[0] - start[0]
        fraction = (column - start[0]) / span
        start_slope = (end[1] - before[1]) / (end[0] - before[0]) * span
        end_slope = (after[1] - start[1]) / (after[0] - start[0]) * span
        row = (
            (2 * fraction**3 - 3 * fraction**2 + 1) * start[1]
            + (fraction**3 - 2 * fraction**2 + fraction) * start_slope
            + (-2 * fraction**3 + 3 * fraction**2) * end[1]
            + (fraction**3 - fraction**2) * end_slope
        )
        rows.append(round(row))
    return rows


def curve_and_area():
    """The curve's lit cells, joined from column to column, and the dim cells under it down to `LAST_FILL_ROW`."""
    rows = curve_rows()
    lit, area = set(), set()
    for column, row in enumerate(rows):
        previous = rows[column - 1] if column else row
        lit.update((column, joined) for joined in range(min(row, previous), max(row, previous) + 1))
        area.update((column, below) for below in range(max(row, previous) + 1, LAST_FILL_ROW + 1))
    return sorted(lit), sorted(area - lit)


def stripes():
    top = CANVAS - (len(STRIPES) * STRIPE_HEIGHT + (len(STRIPES) - 1) * STRIPE_GAP)
    return "".join(
        f'<rect x="0" y="{top + index * (STRIPE_HEIGHT + STRIPE_GAP)}" width="{CANVAS}" height="{STRIPE_HEIGHT}" fill="{color}"/>'
        for index, color in enumerate(STRIPES)
    )


def group(layers, glass):
    """A group of layers, front first. Without glass, it casts no shadow and catches no highlights."""
    entry = {
        "blur-material": None,
        "hidden": False,
        "layers": [{"hidden": False, "image-name": image, "name": os.path.splitext(image)[0]} for image in layers],
        "shadow": {"kind": "neutral", "opacity": 0.5} if glass else {"kind": "none", "opacity": 0},
        "translucency": {"enabled": False, "value": 0.5},
    }
    if not glass:
        entry["specular"] = False
    return entry


if len(sys.argv) != 3 or not sys.argv[2].endswith(".icon"):
    raise SystemExit("Usage: app-icon-layers.py DRIVER.png OUTPUT.icon")
driver, icon = sys.argv[1], sys.argv[2]
shutil.rmtree(icon, ignore_errors=True)
os.makedirs(os.path.join(icon, "Assets"))
lit, area = curve_and_area()
ghosts = [(column, row) for row in range(FIRST_ROW, CANVAS // PITCH) for column in range(CANVAS // PITCH)]
vectors = {
    "0-ghosts.svg": dots(ghosts, GHOST),
    "1-area.svg": dots(area, DIMMED),
    "2-curve.svg": dots(lit, PHOSPHOR),
    "3-stripes.svg": stripes(),
}
for name, body in vectors.items():
    with open(os.path.join(icon, "Assets", name), "w") as file:
        file.write(svg(body))
shutil.copyfile(driver, os.path.join(icon, "Assets", "4-driver.png"))
# The driver brings its own light and shadow from Blender, so the system adds neither to it.
document = {
    "fill": {
        "linear-gradient": [srgb(GLASS_TOP), srgb(GLASS_BOTTOM)],
        "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 1}},
    },
    "groups": [
        group(["4-driver.png"], glass=False),
        group(["3-stripes.svg"], glass=True),
        group(["2-curve.svg", "1-area.svg"], glass=True),
        group(["0-ghosts.svg"], glass=False),
    ],
    "supported-platforms": {"squares": ["macOS"]},
}
with open(os.path.join(icon, "icon.json"), "w") as file:
    json.dump(document, file, indent=2)
    file.write("\n")
print(f"Wrote {icon}: {len(lit)} lit dots, {len(area)} dim dots")
