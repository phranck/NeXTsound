#!/usr/bin/env python3
"""Render the app icon's speaker driver in Blender, seen from the front, with its shadow on a transparent background.

Blender runs it: blender -b --factory-startup -P app-icon-driver.py -- OUTPUT.png [SAMPLES]
"""

import math
import sys

import bpy

CANVAS = 1024
# The driver's diameter and the height of its center on the icon's canvas, in pixels. Its lower edge reaches into the
# red stripe, which app-icon-layers.py draws from 760 pixels down.
DRIVER_DIAMETER = 620
DRIVER_CENTER_Y = 490
# The model is 2 units wide, so this scale shows it at its diameter on the canvas.
ORTHO_SCALE = 2.0 * CANVAS / DRIVER_DIAMETER
# The panel behind the driver, which catches the driver's shadow and shows nothing else.
SHADOW_PLANE_DEPTH = -0.36

arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if not 1 <= len(arguments) <= 2:
    raise SystemExit("Usage: blender -b --factory-startup -P app-icon-driver.py -- OUTPUT.png [SAMPLES]")
output = arguments[0]
samples = int(arguments[1]) if len(arguments) == 2 else 256


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


def area_light(name, location, size, energy):
    """A soft area light aimed at the driver's center."""
    bpy.ops.object.light_add(type="AREA", location=location)
    light = bpy.context.active_object
    light.name = name
    light.data.size = size
    light.data.energy = energy
    light.rotation_euler = (-light.location).to_track_quat("-Z", "Y").to_euler()


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

# The front flange, whose boolean cut leaves an empty material slot behind, so its material replaces every slot.
flange = ring("flange", 1.0, 0.80, 0.08, 0.04)
gunmetal = material("gunmetal", "#5E6268", 1.0, 0.32)
add_bump(gunmetal, "ShaderNodeTexNoise", 0.04, 180.0)
flange.data.materials.clear()
flange.data.materials.append(gunmetal)

bpy.ops.mesh.primitive_torus_add(major_radius=0.71, minor_radius=0.092, major_segments=256, minor_segments=48, location=(0, 0, 0))
surround = bpy.context.active_object
smooth(surround)
surround.data.materials.append(material("rubber", "#18191B", 0.0, 0.55))

bpy.ops.mesh.primitive_cone_add(vertices=256, radius1=0.22, radius2=0.63, depth=0.3, end_fill_type="NOTHING", location=(0, 0, -0.15))
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

bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, SHADOW_PLANE_DEPTH))
bpy.context.active_object.is_shadow_catcher = True

# The key light falls from the upper left, as it does on the front panel, and casts the shadow onto the stripes.
area_light("key", (-3.2, 3.6, 6.0), 3.5, 1400)
area_light("fill", (3.5, -2.5, 5.0), 4.0, 350)
area_light("rim", (0.0, 4.5, 1.4), 2.5, 500)

# Moving the camera down by the canvas pixels between its middle and the driver's center shows the driver there.
bpy.ops.object.camera_add(location=(0, -(CANVAS / 2 - DRIVER_CENTER_Y) * ORTHO_SCALE / CANVAS, 10), rotation=(0, 0, 0))
camera = bpy.context.active_object
camera.data.type = "ORTHO"
camera.data.ortho_scale = ORTHO_SCALE
scene.camera = camera

scene.render.filepath = output
bpy.ops.render.render(write_still=True)
print("Rendered", output)
