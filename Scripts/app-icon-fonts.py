#!/usr/bin/env python3
"""Write the Inter Tight faces the profile icon's print uses into a directory, one static file per face.

Google publishes Inter Tight as two variable fonts, and Blender sets a variable font only at its default weight, so
this script fetches both from a pinned commit of Google's font repository, checks their SHA-256 digests, and
instantiates each face at its weight. Usage: app-icon-fonts.py DIRECTORY
"""

import hashlib
import logging
import os
import sys
import urllib.parse
import urllib.request

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

# fontTools reports every table it rewrites while instantiating, none of which the icon depends on.
logging.getLogger("fontTools").setLevel(logging.ERROR)

SOURCE = "https://raw.githubusercontent.com/google/fonts/0b58fb370093f9a9f4ff785d94405710b79de67c/ofl/intertight/"
VARIABLE_FONTS = {
    "InterTight[wght].ttf": "b81b73dcb64df3c230cabade7df6c5773bf863233f24c9ee51087519f1f88b6f",
    "InterTight-Italic[wght].ttf": "15d3edf0c3d2560658529b8c4c7398d06c730a4695484c680b6c9ca9e4385be2",
}
# Each face's file, the variable font it comes from, and its weight on the font's wght axis.
FACES = {
    "InterTight-SemiBold.ttf": ("InterTight[wght].ttf", 600),
    "InterTight-SemiBoldItalic.ttf": ("InterTight-Italic[wght].ttf", 600),
    "InterTight-Bold.ttf": ("InterTight[wght].ttf", 700),
}


def fetched(name):
    """The variable font `name` from the pinned commit, refused unless its digest is the pinned one."""
    with urllib.request.urlopen(SOURCE + urllib.parse.quote(name)) as response:
        data = response.read()
    digest = hashlib.sha256(data).hexdigest()
    if digest != VARIABLE_FONTS[name]:
        raise SystemExit(f"{name} has SHA-256 {digest}, expected {VARIABLE_FONTS[name]}")
    return data


if len(sys.argv) != 2:
    raise SystemExit("Usage: app-icon-fonts.py DIRECTORY")
directory = sys.argv[1]
os.makedirs(directory, exist_ok=True)
for name in VARIABLE_FONTS:
    with open(os.path.join(directory, name), "wb") as file:
        file.write(fetched(name))
for face, (source, weight) in FACES.items():
    font = instancer.instantiateVariableFont(TTFont(os.path.join(directory, source)), {"wght": weight})
    font.save(os.path.join(directory, face))
print(f"Wrote {len(FACES)} Inter Tight faces to {directory}")
