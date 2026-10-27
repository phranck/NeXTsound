#!/usr/bin/env python3
"""Render one of the icons' subjects in Blender, seen from the front, with its shadow on a transparent background: the
speaker driver of the app icon, or the printed sheet of the sound profile file's icon.

Blender runs it: blender -b --factory-startup -P app-icon-render.py -- SUBJECT OUTPUT.png [SAMPLES]
SUBJECT is driver or sheet.
"""

import math
import os
import sys

import bpy

CANVAS = 1024
# The driver's diameter and the height of its center on the icon's canvas, in pixels. Its lower edge reaches into the
# red stripe, which app-icon-layers.py draws from 760 pixels down. The sheet stands on the same center.
DRIVER_DIAMETER = 620
DRIVER_CENTER_Y = 490
# The model is 2 units wide, so this scale shows it at its diameter on the canvas.
ORTHO_SCALE = 2.0 * CANVAS / DRIVER_DIAMETER
# The panel behind the subject, which catches its shadow and shows nothing else.
SHADOW_PLANE_DEPTH = -0.36

# The sheet in model units, in the proportions of A4, and the height of its center on the canvas in pixels, so its lower
# edge ends in the red stripe as the driver's does. The folded corner's legs run along its top and right edges, and
# the fold lifts its tip off the paper.
SHEET_WIDTH = 1.62
SHEET_HEIGHT = 2.29
SHEET_CENTER_Y = 460
SHEET_THICKNESS = 0.012
FOLD = 0.37
FOLD_LIFT = 0.03
# The print on the sheet in Inter Tight: a quote justified between the margins, which flows around the folded corner,
# and a printer's line centered near the bottom edge.
QUOTE = (
    "“Sometimes life hits you in the head with a brick. Don’t lose faith. I’m convinced that the only thing that "
    "kept me going was that I loved what I did. You’ve got to find what you love. And that is as true for your work "
    "as it is for your lovers. Your work is going to fill a large part of your life, and the only way to be truly "
    "satisfied is to do what you believe is great work. And the only way to do great work is to love what you do. "
    "If you haven't found it yet, keep looking. Don't settle. As with all matters of the heart, you'll know when you "
    "find it. And, like any great relationship, it just gets better and better as the years roll on. So keep "
    "looking. Don’t settle.”"
)
# The quote is set in SemiBold Italic, the attribution in Bold behind an em dash, and the printer's line in SemiBold.
ATTRIBUTION = chr(0x2014) + " Steve Jobs"
FOOTER = "-- printed on a NeXT Laser Printer, 400 dpi --"
# The directory that NXS_ICON_FONTS names holds the faces that app-icon-fonts.py writes, one file per face. They fill
# the upright, italic and bold slots of Blender's text.
FONT_DIRECTORY = os.environ.get("NXS_ICON_FONTS", "")
UPRIGHT, ITALIC, BOLD = "InterTight-SemiBold.ttf", "InterTight-SemiBoldItalic.ttf", "InterTight-Bold.ttf"
# The quote takes the largest size in this range that fits the sheet, which the script finds in this many halvings.
PRINT_SIZES = (0.05, 0.16)
PRINT_SIZE_STEPS = 14
FOOTER_SIZE = 0.065
PRINT_MARGIN = 0.13
# The space the print keeps from the folded corner, wide enough beside it to show that the lines end there, and
# small below it, and from the footer above which it ends.
FOLD_CLEARANCE = 0.11
FOLD_CLEARANCE_BELOW = 0.03
FOOTER_CLEARANCE = 0.08
FOOTER_TOP = 0.17
LINE_SPACING = 1.25

arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if not 2 <= len(arguments) <= 3 or arguments[0] not in ("driver", "sheet"):
    raise SystemExit("Usage: blender -b --factory-startup -P app-icon-render.py -- driver|sheet OUTPUT.png [SAMPLES]")
subject, output = arguments[0], arguments[1]
samples = int(arguments[2]) if len(arguments) == 3 else 256


def linear(hex_color):
    """A 24-bit sRGB value in the linear values Blender's shaders take."""
    channels = (int(hex_color[index:index + 2], 16) / 255 for index in (1, 3, 5))
    return tuple(value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4 for value in channels)


def material(name, color, metallic, roughness):
    """A Principled BSDF material."""
    result = bpy.data.materials.new(name)
    shader = result.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*linear(color), 1)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    return result


def add_bump(target, texture_type, strength, scale, **settings):
    """Gives a material a fine relief from a procedural texture in object space."""
    tree = target.node_tree
    shader = tree.nodes.get("Principled BSDF")
    coordinates = tree.nodes.new("ShaderNodeTexCoord")
    texture = tree.nodes.new(texture_type)
    texture.inputs["Scale"].default_value = scale
    for key, value in settings.items():
        setattr(texture, key, value)
    bump = tree.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = strength
    tree.links.new(coordinates.outputs["Object"], texture.inputs["Vector"])
    tree.links.new(texture.outputs.get("Fac") or texture.outputs[0], bump.inputs["Height"])
    tree.links.new(bump.outputs["Normal"], shader.inputs["Normal"])


def smooth(item):
    for polygon in item.data.polygons:
        polygon.use_smooth = True


def ring(name, outer, inner, depth, top):
    """A flat ring with beveled edges whose front face lies at `top`."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=256, radius=outer, depth=depth, location=(0, 0, top - depth / 2))
    body = bpy.context.active_object
    body.name = name
    bpy.ops.mesh.primitive_cylinder_add(vertices=256, radius=inner, depth=depth * 4, location=(0, 0, top - depth / 2))
    hole = bpy.context.active_object
    cut = body.modifiers.new("hole", "BOOLEAN")
    cut.operation = "DIFFERENCE"
    cut.object = hole
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.modifier_apply(modifier=cut.name)
    bpy.data.objects.remove(hole, do_unlink=True)
    bevel = body.modifiers.new("bevel", "BEVEL")
    bevel.width = 0.012
    bevel.segments = 4
    smooth(body)
    return body


def panel(name, corners, thickness, surface):
    """A flat polygon through `corners`, given the thickness of paper toward the back."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(corners, [], [list(range(len(corners)))])
    item = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(item)
    solidify = item.modifiers.new("thickness", "SOLIDIFY")
    solidify.thickness = thickness
    solidify.offset = -1
    item.data.materials.append(surface)
    return item


def printed(name, body, ink, boxes=1):
    """A text object in Inter Tight on the sheet's front, whose lines fill `boxes` text boxes in turn. With more than one,
    it breaks at whole words and justifies every line but the last."""
    curve = bpy.data.curves.new(name, type="FONT")
    curve.body = body
    curve.font, curve.font_italic, curve.font_bold = (
        bpy.data.fonts.load(os.path.join(FONT_DIRECTORY, face), check_existing=True) for face in (UPRIGHT, ITALIC, BOLD)
    )
    curve.space_line = LINE_SPACING
    curve.align_x = "JUSTIFY" if boxes > 1 else "LEFT"
    curve.align_y = "TOP"
    item = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(item)
    curve.materials.append(ink)
    # A text curve starts with one box, and Blender's operator adds each further one to the active object.
    bpy.context.view_layer.objects.active = item
    for _ in range(boxes - 1):
        bpy.ops.font.textbox_add()
    return item


def set_text(item, size, boxes=()):
    """Sets the text at `size` into `boxes`, given as x, y, width and height from the object's origin, and returns the
    top and the bottom of the set text in the object's own coordinates. Blender sets the first line above the origin,
    so a caller places the text by the measured top."""
    item.data.size = size
    for box, (x, y, width, height) in zip(item.data.text_boxes, boxes):
        box.x, box.y, box.width, box.height = x, y, width, height
    bpy.context.view_layer.update()
    evaluated = item.evaluated_get(bpy.context.evaluated_depsgraph_get())
    heights = [vertex.co.y for vertex in evaluated.to_mesh().vertices]
    evaluated.to_mesh_clear()
    return max(heights), min(heights)


def area_light(name, location, size, energy):
    """A soft area light aimed at the subject's center."""
    bpy.ops.object.light_add(type="AREA", location=location)
    light = bpy.context.active_object
    light.name = name
    light.data.size = size
    light.data.energy = energy
    light.rotation_euler = (-light.location).to_track_quat("-Z", "Y").to_euler()


def driver():
    """The speaker driver: flange, surround, cone, dust cap and four screws."""
    # The front flange, whose boolean cut leaves an empty material slot behind, so its material replaces every slot.
    flange = ring("flange", 1.0, 0.80, 0.08, 0.04)
    gunmetal = material("gunmetal", "#5E6268", 1.0, 0.32)
    add_bump(gunmetal, "ShaderNodeTexNoise", 0.04, 180.0)
    flange.data.materials.clear()
    flange.data.materials.append(gunmetal)

    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.71, minor_radius=0.092, major_segments=256, minor_segments=48, location=(0, 0, 0)
    )
    surround = bpy.context.active_object
    smooth(surround)
    surround.data.materials.append(material("rubber", "#18191B", 0.0, 0.55))

    bpy.ops.mesh.primitive_cone_add(
        vertices=256, radius1=0.22, radius2=0.63, depth=0.3, end_fill_type="NOTHING", location=(0, 0, -0.15)
    )
    cone = bpy.context.active_object
    smooth(cone)
    paper = material("paper", "#1C1E21", 0.0, 0.68)
    add_bump(paper, "ShaderNodeTexWave", 0.3, 7.0, wave_type="RINGS")
    cone.data.materials.append(paper)

    bpy.ops.mesh.primitive_uv_sphere_add(segments=128, ring_count=64, radius=0.25, location=(0, 0, -0.29))
    cap = bpy.context.active_object
    cap.scale = (1, 1, 0.32)
    smooth(cap)
    aluminum = material("aluminum", "#AEB2B7", 1.0, 0.38)
    add_bump(aluminum, "ShaderNodeTexNoise", 0.02, 260.0)
    cap.data.materials.append(aluminum)

    chrome = material("chrome", "#D8DADD", 1.0, 0.12)
    for angle in (45, 135, 225, 315):
        screw_x, screw_y = 0.9 * math.cos(math.radians(angle)), 0.9 * math.sin(math.radians(angle))
        bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=0.045, location=(screw_x, screw_y, 0.04))
        screw = bpy.context.active_object
        screw.scale = (1, 1, 0.45)
        smooth(screw)
        screw.data.materials.append(chrome)


def sheet():
    """A printed sheet of paper with its top right corner folded over onto its front."""
    center = (DRIVER_CENTER_Y - SHEET_CENTER_Y) * ORTHO_SCALE / CANVAS
    right, top, bottom = SHEET_WIDTH / 2, center + SHEET_HEIGHT / 2, center - SHEET_HEIGHT / 2
    front = material("paper", "#EDEBE4", 0.0, 0.82)
    add_bump(front, "ShaderNodeTexNoise", 0.02, 140.0)
    back = material("paper back", "#D9D5CB", 0.0, 0.85)
    outline = [(-right, bottom, 0), (right, bottom, 0), (right, top - FOLD, 0), (right - FOLD, top, 0), (-right, top, 0)]
    panel("sheet", outline, SHEET_THICKNESS, front)
    # The corner folded across the line between the ends of its legs, so its tip lies on the sheet's front.
    flap = [(right, top - FOLD, 0.002), (right - FOLD, top, 0.002), (right - FOLD, top - FOLD, FOLD_LIFT)]
    panel("fold", flap, SHEET_THICKNESS / 2, back)
    # Black ink without a specular reflection, which would otherwise lighten it under the key light.
    ink = material("ink", "#000000", 0.0, 1.0)
    ink.node_tree.nodes.get("Principled BSDF").inputs["Specular IOR Level"].default_value = 0
    # The print starts a margin below the top edge. Its lines beside the folded corner end a clear gap short of it, and
    # the lines below run across the full measure down to the footer. The narrow box holds whole lines, Blender's line
    # pitch being the size times the spacing, so the lines below keep the same pitch.
    width = SHEET_WIDTH - 2 * PRINT_MARGIN
    beside_width = width - (FOLD + FOLD_CLEARANCE - PRINT_MARGIN)
    corner_depth = FOLD + FOLD_CLEARANCE_BELOW - PRINT_MARGIN
    height = SHEET_HEIGHT - PRINT_MARGIN - FOOTER_TOP - FOOTER_CLEARANCE
    quote = printed("print", QUOTE + "\n" + ATTRIBUTION, ink, boxes=2)
    for index, character in enumerate(quote.data.body_format):
        character.use_italic = index < len(QUOTE)
        character.use_bold = index > len(QUOTE)

    def set_quote(size):
        pitch = size * LINE_SPACING
        beside = math.ceil(corner_depth / pitch) * pitch
        return set_text(quote, size, [(0, 0, beside_width, beside), (0, -beside, width, height - beside)])

    # The largest size whose set quote fits the height above the footer, found by halving the range of sizes.
    smallest, largest = PRINT_SIZES
    for _ in range(PRINT_SIZE_STEPS):
        size = (smallest + largest) / 2
        text_top, text_bottom = set_quote(size)
        if text_top - text_bottom <= height:
            smallest = size
        else:
            largest = size
    text_top, _ = set_quote(smallest)
    quote.location = (-right + PRINT_MARGIN, top - PRINT_MARGIN - text_top, 0.001)
    print(f"Quote set at size {smallest:.4f}")

    footer = printed("footer", FOOTER, ink)
    footer.data.align_x = "CENTER"
    footer_top, _ = set_text(footer, FOOTER_SIZE)
    footer.location = (0, bottom + FOOTER_TOP - footer_top, 0.001)


bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = samples
scene.cycles.use_denoising = True
scene.render.resolution_x = CANVAS
scene.render.resolution_y = CANVAS
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.view_settings.view_transform = "AgX"
preferences = bpy.context.preferences.addons["cycles"].preferences
preferences.compute_device_type = "METAL"
preferences.get_devices()
for device in preferences.devices:
    device.use = True
scene.cycles.device = "GPU"

world = bpy.data.worlds.new("World")
scene.world = world
world.node_tree.nodes["Background"].inputs["Color"].default_value = (*linear("#2A2E33"), 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6

{"driver": driver, "sheet": sheet}[subject]()

bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, SHADOW_PLANE_DEPTH))
bpy.context.active_object.is_shadow_catcher = True

# The key light falls from the upper left, as it does on the front panel, and casts the shadow onto the stripes.
area_light("key", (-3.2, 3.6, 6.0), 3.5, 1400)
area_light("fill", (3.5, -2.5, 5.0), 4.0, 350)
area_light("rim", (0.0, 4.5, 1.4), 2.5, 500)

# Moving the camera down by the canvas pixels between its middle and the subject's center shows the subject there.
bpy.ops.object.camera_add(location=(0, -(CANVAS / 2 - DRIVER_CENTER_Y) * ORTHO_SCALE / CANVAS, 10), rotation=(0, 0, 0))
camera = bpy.context.active_object
camera.data.type = "ORTHO"
camera.data.ortho_scale = ORTHO_SCALE
scene.camera = camera

scene.render.filepath = output
bpy.ops.render.render(write_still=True)
print("Rendered", output)
