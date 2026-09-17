"""Procedurally build and render Undertone's open half-twisted U ribbon.

Run with Blender 4.x:
  blender --background --python undertone_ribbon.py

The scene is intentionally a true 3D strip. It has a constant 0.86-unit
physical width and rotates exactly 180 degrees while travelling through the
lower U bend. The form is not based on, or traced from, a raster reference.
"""

from pathlib import Path
import math

import bpy
from mathutils import Vector


OUTPUT = Path(__file__).resolve().parent / "renders"
OUTPUT.mkdir(parents=True, exist_ok=True)

# Geometric parameters
RADIUS = 2.15
ARM = 2.25
WIDTH = 0.86
ROWS = 220
COLUMNS = 20
THICKNESS = 0.105
TWIST_START = 0.18
TWIST_END = 0.82


def smoothstep(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def centreline(t):
    """Return a point on: down left arm → semicircular bottom → up right arm."""
    total = ARM * 2.0 + math.pi * RADIUS
    distance = t * total
    if distance < ARM:
        return Vector((-RADIUS, 0.0, ARM * 0.5 - distance))
    if distance < ARM + math.pi * RADIUS:
        angle = math.pi - (distance - ARM) / RADIUS
        return Vector((RADIUS * math.cos(angle), 0.0, -ARM * 0.5 - RADIUS * math.sin(angle)))
    return Vector((RADIUS, 0.0, -ARM * 0.5 + (distance - ARM - math.pi * RADIUS)))


def sample(t):
    """Construct a stable ribbon frame and apply the half twist about its tangent."""
    epsilon = 0.0001
    point = centreline(t)
    tangent = (centreline(min(1.0, t + epsilon)) - centreline(max(0.0, t - epsilon))).normalized()
    depth_axis = Vector((0.0, -1.0, 0.0))
    planar_normal = depth_axis.cross(tangent).normalized()
    turn = smoothstep((t - TWIST_START) / (TWIST_END - TWIST_START))
    angle = math.pi * turn
    transverse = planar_normal * math.cos(angle) + depth_axis * math.sin(angle)
    return point, tangent, transverse


def color_at(t):
    # Cyan left face → electric violet at the fold → warm coral right face.
    stops = [
        (0.00, (0.025, 0.62, 1.00, 1.0)),
        (0.43, (0.18, 0.20, 1.00, 1.0)),
        (0.67, (0.89, 0.05, 0.93, 1.0)),
        (1.00, (1.00, 0.23, 0.44, 1.0)),
    ]
    for (a, first), (b, second) in zip(stops, stops[1:]):
        if t <= b:
            local = smoothstep((t - a) / (b - a))
            return tuple(first[i] * (1.0 - local) + second[i] * local for i in range(4))
    return stops[-1][1]


def material(name, color, roughness=0.20, metallic=0.08):
    result = bpy.data.materials.new(name)
    result.use_nodes = True
    shader = result.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Coat Weight"].default_value = 0.46
    shader.inputs["Coat Roughness"].default_value = 0.11
    return result


def make_ribbon():
    vertices = []
    faces = []
    for row in range(ROWS + 1):
        t = row / ROWS
        point, _, transverse = sample(t)
        for column in range(COLUMNS + 1):
            offset = (column / COLUMNS - 0.5) * WIDTH
            vertices.append(point + transverse * offset)
    for row in range(ROWS):
        for column in range(COLUMNS):
            base = row * (COLUMNS + 1) + column
            faces.append((base, base + 1, base + COLUMNS + 2, base + COLUMNS + 1))
    mesh = bpy.data.meshes.new("Undertone constant-width half-twist mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.clear()
    for row in range(ROWS):
        mesh.materials.append(material(f"Ribbon {row:03d}", color_at((row + 0.5) / ROWS)))
    for polygon in mesh.polygons:
        polygon.material_index = (polygon.index // COLUMNS)
        polygon.use_smooth = True
    ribbon = bpy.data.objects.new("Undertone ribbon — open 180 degree twist", mesh)
    bpy.context.collection.objects.link(ribbon)
    bevel = ribbon.modifiers.new("Soft physical edges", "BEVEL")
    bevel.width = THICKNESS
    bevel.segments = 4
    bevel.limit_method = "ANGLE"
    solidify = ribbon.modifiers.new("Constant thickness", "SOLIDIFY")
    solidify.thickness = THICKNESS
    solidify.offset = 0.0
    solidify.use_even_offset = True
    return ribbon


def make_background():
    bpy.ops.mesh.primitive_cube_add(location=(0.0, 0.72, -0.18), scale=(4.55, 0.18, 4.55))
    slab = bpy.context.object
    slab.name = "Liquid Glass background slab"
    bevel = slab.modifiers.new("Rounded app-icon corners", "BEVEL")
    bevel.width = 0.72
    bevel.segments = 12
    material_background = material("Background violet", (0.025, 0.015, 0.26, 1.0), roughness=0.28, metallic=0.0)
    slab.data.materials.append(material_background)
    return slab


def area(name, location, energy, size, color):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    object_ = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(object_)
    object_.location = location
    direction = Vector((0.0, 0.0, -0.25)) - object_.location
    object_.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def set_camera():
    data = bpy.data.cameras.new("Undertone icon camera")
    camera = bpy.data.objects.new("Undertone icon camera", data)
    bpy.context.collection.objects.link(camera)
    camera.location = (0.0, -14.0, -0.25)
    camera.rotation_euler = (math.radians(90), 0, 0)
    camera.rotation_euler = (Vector((0.0, 0.0, -0.25)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    data.type = "ORTHO"
    data.ortho_scale = 9.9
    bpy.context.scene.camera = camera


def configure_scene():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.world.color = (0.005, 0.003, 0.020)
    scene.view_settings.look = "AgX - Medium High Contrast"


def main():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    configure_scene()
    make_background()
    make_ribbon()
    area("Cyan key", (-4.0, -4.0, 5.0), 1150, 4.0, (0.22, 0.87, 1.0))
    area("Warm key", (4.0, -3.0, 3.0), 850, 3.0, (1.0, 0.32, 0.56))
    area("Soft overhead", (0.0, -2.2, 6.5), 700, 5.0, (0.58, 0.36, 1.0))
    set_camera()
    bpy.context.scene.render.filepath = str(OUTPUT / "undertone-ribbon-beauty.png")
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT.parent / "undertone-ribbon.blend"))
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
