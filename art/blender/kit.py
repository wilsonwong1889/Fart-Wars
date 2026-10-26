"""Shared helpers for the Fart Wars art scripts (Blender 4.2+ / 5.x).

Run the scripts with Blender's Python, either a desktop Blender:
    blender --background --python art/blender/build_weapons.py
or the bpy module (pip install bpy):
    python art/blender/build_weapons.py

Conventions, matching Roblox once exported (FBX: forward -Z, up +Y):
    Blender +X = Roblox +X (right)
    Blender +Y = Roblox -Z (forward, along the barrel)
    Blender +Z = Roblox +Y (up)
    1 Blender unit = 1 stud
"""

import json
import math
import os

import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
EXPORT = os.path.join(ROOT, "art", "export")

# Blender -> Roblox basis change (a proper rotation).
C = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))


def to_roblox(v):
    """A Blender point or direction in Roblox axes."""
    return Vector((v[0], v[2], -v[1]))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # No .blend1 backups next to the exports.
    bpy.context.preferences.filepaths.save_version = 0
    scene = bpy.context.scene
    scene.unit_settings.system = "NONE"
    return scene


def srgb(r, g, b):
    """0-255 sRGB to Blender's linear colour."""

    def channel(c):
        c = c / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return (channel(r), channel(g), channel(b), 1.0)


def material(name, color, metallic=0.0, roughness=0.45, emission=0.0, transmission=0.0, alpha=1.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission > 0:
        bsdf.inputs["Emission Color"].default_value = color
        bsdf.inputs["Emission Strength"].default_value = emission
    if transmission > 0:
        bsdf.inputs["Transmission Weight"].default_value = transmission
        bsdf.inputs["IOR"].default_value = 1.45
    if alpha < 1:
        bsdf.inputs["Alpha"].default_value = alpha
        try:
            mat.surface_render_method = "BLENDED"
        except AttributeError:
            pass
    mat.diffuse_color = color
    return mat


def active(obj):
    for other in bpy.context.selected_objects:
        other.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply_modifiers(obj):
    active(obj)
    for modifier in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=modifier.name)


def smooth(obj, angle=40):
    active(obj)
    bpy.ops.object.shade_smooth()
    try:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(angle))
    except (AttributeError, RuntimeError, TypeError):
        pass


class Builder:
    """Builds one weapon from primitives, keeping a record of each piece
    (for the game's stand-in model and icons) and joining the pieces by
    role into one mesh each (the MeshParts the game imports)."""

    def __init__(self, name, roles):
        self.name = name
        self.roles = roles  # role -> {"material": Material, "roblox": {...}}
        self.objects = {role: [] for role in roles}
        self.pieces = []

    def _record(self, obj, role, shape, size, extra=None):
        bpy.context.view_layer.update()
        world = obj.matrix_world
        rotation = C @ world.to_3x3().normalized() @ C.transposed()
        if shape == "cylinder":
            # Roblox cylinders run along their X axis.
            rotation = rotation @ Matrix.Rotation(math.radians(90), 3, "Z")
        center = to_roblox(world.translation)
        record = {
            "role": role,
            "shape": shape,
            "size": [round(s, 4) for s in size],
            "cframe": [round(center.x, 4), round(center.y, 4), round(center.z, 4)]
            + [round(rotation[r][c], 5) for r in range(3) for c in range(3)],
        }
        if extra:
            record.update(extra)
        self.pieces.append(record)

    def _finish(self, obj, role):
        obj.name = f"{self.name}_{role}_{len(self.objects[role])}"
        obj.data.materials.clear()
        obj.data.materials.append(self.roles[role]["material"])
        self.objects[role].append(obj)
        return obj

    def box(self, role, size, center, bevel=0.06, rotation=(0, 0, 0)):
        """A bevelled block: size and center in Blender axes (x, y, z)."""
        bpy.ops.mesh.primitive_cube_add(size=1, location=center, rotation=[math.radians(a) for a in rotation])
        obj = bpy.context.active_object
        obj.scale = size
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        if bevel > 0:
            mod = obj.modifiers.new("Bevel", "BEVEL")
            mod.width = bevel
            mod.segments = 3
            mod.limit_method = "ANGLE"
        self._record(obj, role, "block", (size[0], size[2], size[1]), {"corner": bevel})
        return self._finish(obj, role)

    def cyl(self, role, radius, length, center, axis="Y", radius2=None, vertices=28, bevel=0.02):
        """A cylinder (or a cone with radius2) along a Blender axis."""
        rotation = {"X": (0, math.radians(90), 0), "Y": (math.radians(90), 0, 0), "Z": (0, 0, 0)}[axis]
        if radius2 is None:
            bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=length, location=center, rotation=rotation)
        else:
            bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius, radius2=radius2, depth=length, location=center, rotation=rotation)
        obj = bpy.context.active_object
        if bevel > 0:
            mod = obj.modifiers.new("Bevel", "BEVEL")
            mod.width = bevel
            mod.segments = 2
            mod.limit_method = "ANGLE"
        diameter = 2 * max(radius, radius2 or 0)
        self._record(obj, role, "cylinder", (length, diameter, diameter))
        return self._finish(obj, role)

    def ball(self, role, radius, center, scale=(1, 1, 1)):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=radius, location=center)
        obj = bpy.context.active_object
        obj.scale = scale
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        size = (2 * radius * scale[0], 2 * radius * scale[2], 2 * radius * scale[1])
        self._record(obj, role, "ball" if scale == (1, 1, 1) else "block", size, {"corner": radius})
        return self._finish(obj, role)

    def ring(self, role, major, minor, center, axis="Y", standin=True):
        rotation = {"X": (0, math.radians(90), 0), "Y": (math.radians(90), 0, 0), "Z": (0, 0, 0)}[axis]
        bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=32, minor_segments=10, location=center, rotation=rotation)
        obj = bpy.context.active_object
        # A torus stands in as a short cylinder.
        extra = {"ring": True}
        if not standin:
            extra["standin"] = False
        self._record(obj, role, "cylinder", (2 * minor, 2 * (major + minor), 2 * (major + minor)), extra)
        return self._finish(obj, role)

    def join(self):
        """One mesh per role, transforms applied, smooth shaded. Returns
        {role: object}."""
        joined = {}
        for role, objects in self.objects.items():
            if not objects:
                continue
            for obj in objects:
                apply_modifiers(obj)
            for obj in bpy.context.selected_objects:
                obj.select_set(False)
            for obj in objects:
                obj.select_set(True)
            bpy.context.view_layer.objects.active = objects[0]
            if len(objects) > 1:
                bpy.ops.object.join()
            obj = bpy.context.active_object
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            obj.name = role
            obj.data.name = f"{self.name}_{role}"
            smooth(obj)
            joined[role] = obj
        return joined


def bounds(obj):
    """The object's box in Roblox axes: (center, size)."""
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    points = [to_roblox(c) for c in corners]
    lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return (lo + hi) / 2, hi - lo


def triangles(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=1, sort_keys=True)
        f.write("\n")


def render_setup(scene, size, samples=48):
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x = size[0]
    scene.render.resolution_y = size[1]
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.9, 0.9, 1.0, 1)
    background.inputs["Strength"].default_value = 0.7
    scene.world = world


def freestyle(scene, thickness=2.0):
    """Clean dark outlines on renders (Freestyle, which Cycles supports)."""
    scene.render.use_freestyle = True
    scene.render.line_thickness_mode = "ABSOLUTE"
    scene.render.line_thickness = thickness
    layer = scene.view_layers[0]
    layer.use_freestyle = True
    settings = layer.freestyle_settings
    lineset = settings.linesets[0] if settings.linesets else settings.linesets.new("Lines")
    lineset.select_by_visibility = True
    lineset.select_by_edge_types = True
    lineset.select_silhouette = True
    lineset.select_border = True
    lineset.select_crease = True
    style = lineset.linestyle or bpy.data.linestyles.new("Outline")
    lineset.linestyle = style
    style.color = (0.03, 0.025, 0.05)
    style.thickness = thickness


def light(name, kind, location, energy, rotation=(0, 0, 0), size=1.0):
    data = bpy.data.lights.new(name, kind)
    data.energy = energy
    if kind == "AREA":
        data.size = size
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    obj.rotation_euler = [math.radians(a) for a in rotation]
    bpy.context.scene.collection.objects.link(obj)
    return obj


def camera(location, target, ortho_scale=None):
    data = bpy.data.cameras.new("Camera")
    obj = bpy.data.objects.new("Camera", data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    direction = Vector(target) - Vector(location)
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    if ortho_scale:
        data.type = "ORTHO"
        data.ortho_scale = ortho_scale
    bpy.context.scene.camera = obj
    return obj


def outline(obj, thickness=0.035):
    """A cartoon outline for renders (an inverted hull)."""
    mat = bpy.data.materials.get("Outline")
    if not mat:
        mat = bpy.data.materials.new("Outline")
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        nodes.clear()
        out = nodes.new("ShaderNodeOutputMaterial")
        emit = nodes.new("ShaderNodeEmission")
        emit.inputs["Color"].default_value = (0.02, 0.015, 0.03, 1)
        geometry = nodes.new("ShaderNodeNewGeometry")
        transparent = nodes.new("ShaderNodeBsdfTransparent")
        mix = nodes.new("ShaderNodeMixShader")
        links = mat.node_tree.links
        # The hull's normals are flipped: the side facing the camera is a
        # back face (see through it), the far side draws the outline.
        links.new(geometry.outputs["Backfacing"], mix.inputs["Fac"])
        links.new(emit.outputs["Emission"], mix.inputs[1])
        links.new(transparent.outputs["BSDF"], mix.inputs[2])
        links.new(mix.outputs["Shader"], out.inputs["Surface"])
        mat.use_backface_culling = False
    obj.data.materials.append(mat)
    mod = obj.modifiers.new("Outline", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = 1
    mod.use_flip_normals = True
    mod.material_offset = len(obj.data.materials) - 1
