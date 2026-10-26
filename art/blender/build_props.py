"""Builds the map's props in Blender and exports them for Roblox.

    python art/blender/build_props.py
    blender --background --python art/blender/build_props.py

Each prop is modelled at the exact size of the map part it dresses (the
part stays as the collision and line-of-sight box; the mesh is drawn over
it), so cover and sightlines don't change. Writes art/export/props/:
    <Prop>.fbx    one mesh, named after the prop, for Studio's 3D importer
    <Prop>.png    a preview render
    Props.blend   every prop in one Blender scene, to edit by hand
    all.png       the previews together
    plaza.png     Porcelain Plaza laid out as in the map, dressed
and src/shared/Config/PropArt.luau (each mesh's size, to check imports).

Cylinders run along Blender X (Roblox X, the axis of a Roblox cylinder
part); blocks are sized x (width), y (depth, Roblox -Z), z (height, Roblox
+Y). The front of an asymmetric prop faces Blender +Y (Roblox -Z).
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402  (before bmesh: the bpy module provides it)
import bmesh  # noqa: E402
import numpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import kit  # noqa: E402

OUT = os.path.join(kit.EXPORT, "props")

PORCELAIN = (240, 240, 235)
CHROME = (200, 205, 215)


def mesh_object(name, bm):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def lathe(name, profile, steps=48, closed=False):
    """Revolves (axial, radius) points around Blender X. A radius of 0 at
    an end closes it; `closed` joins the last point back to the first (a
    ring, like a seat or a band)."""
    bm = bmesh.new()
    rings = []
    for a, r in profile:
        ring = []
        if r <= 1e-6:
            ring = [bm.verts.new((a, 0, 0))]
        else:
            for i in range(steps):
                t = 2 * math.pi * i / steps
                ring.append(bm.verts.new((a, r * math.cos(t), r * math.sin(t))))
        rings.append(ring)
    pairs = [(rings[i], rings[i + 1]) for i in range(len(rings) - 1)]
    if closed:
        pairs.append((rings[-1], rings[0]))
    for a, b in pairs:
        if len(a) == 1 and len(b) > 1:
            for j in range(steps):
                bm.faces.new((a[0], b[(j + 1) % steps], b[j]))
        elif len(b) == 1 and len(a) > 1:
            for j in range(steps):
                bm.faces.new((a[j], a[(j + 1) % steps], b[0]))
        elif len(a) > 1 and len(b) > 1:
            for j in range(steps):
                bm.faces.new((a[j], a[(j + 1) % steps], b[(j + 1) % steps], b[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_object(name, bm)


def rounded_box(name, size, center=(0, 0, 0), bevel=0.3, segments=3):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "ANGLE"
    return obj


def cylinder(name, radius, length, center=(0, 0, 0), axis="X", vertices=32, bevel=0.0):
    rotation = {"X": (0, math.radians(90), 0), "Y": (math.radians(90), 0, 0), "Z": (0, 0, 0)}[axis]
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=length, location=center, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
    return obj


def torus(name, major, minor, center=(0, 0, 0), axis="X"):
    rotation = {"X": (0, math.radians(90), 0), "Y": (math.radians(90), 0, 0), "Z": (0, 0, 0)}[axis]
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=48, minor_segments=12, location=center, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    return obj


def join(name, objects):
    for obj in objects:
        kit.apply_modifiers(obj)
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1:
        bpy.ops.object.join()
    obj = bpy.context.active_object
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.name = name
    obj.data.name = name
    return obj


# Each prop fills the box of the part it was modelled on (PROPS below)
# exactly, so scaling the mesh to that part doesn't stretch it.


def toilet_tank():
    # ThroneTank: 16 wide, 4 deep, 14 tall. The front (Blender +Y) faces
    # the bowl, with a panel and the flush lever.
    return [
        rounded_box("Body", (15.6, 3.4, 12.6), (0, -0.2, -0.5), bevel=1.0, segments=4),
        rounded_box("Plinth", (16, 3.8, 1.2), (0, -0.1, -6.4), bevel=0.4),
        rounded_box("Shoulder", (16, 3.6, 1.0), (0, -0.2, 6.5), bevel=0.4),
        rounded_box("Panel", (11, 0.6, 7), (0, 1.6, 0.2), bevel=0.3),
        cylinder("LeverBase", 0.9, 0.5, (-5.6, 1.75, 3.6), axis="Y", vertices=24, bevel=0.1),
        rounded_box("Lever", (3.2, 0.5, 0.7), (-4.3, 1.75, 3.6), bevel=0.2),
    ]


def tank_lid():
    # ThroneLid: 17 wide, 5 deep, 1 tall.
    return [
        rounded_box("Slab", (17, 5, 0.7), (0, 0, -0.15), bevel=0.3),
        rounded_box("Top", (15.6, 4.2, 0.4), (0, 0, 0.3), bevel=0.18),
    ]


def toilet_bowl():
    # ThroneBowl: 6 along X (up), 12 across. A pedestal flaring out to the
    # rim at +X, hollow inside.
    profile = [
        (-3.0, 0.0), (-3.0, 3.6), (-2.7, 3.75), (-1.7, 3.3), (-0.7, 3.8),
        (0.5, 4.8), (1.7, 5.6), (2.6, 6.0), (3.0, 5.75), (3.0, 4.7),
        (2.4, 4.2), (1.0, 3.0), (0.2, 1.6), (-0.1, 0.0),
    ]
    return [lathe("Bowl", profile)]


def toilet_seat():
    # ThroneSeat: 1 along X, 13 across: a rounded ring.
    profile = [
        (-0.5, 4.4), (-0.5, 6.1), (-0.35, 6.45), (0.0, 6.5), (0.35, 6.4),
        (0.5, 6.0), (0.5, 4.8), (0.35, 4.3), (0.0, 4.15), (-0.35, 4.2),
    ]
    return [lathe("Seat", profile, steps=64, closed=True)]


def bean_can():
    # BeanCan: 10 along X (up), 8 across, with rims, ridges and a ring pull.
    profile = [
        (-5.0, 0.0), (-5.0, 3.55), (-4.85, 4.0), (-4.5, 3.85), (-4.2, 3.9),
        (-3.6, 3.9), (-3.4, 3.8), (-3.2, 3.9), (3.2, 3.9), (3.4, 3.8),
        (3.6, 3.9), (4.2, 3.9), (4.5, 3.85), (4.85, 4.0), (5.0, 3.55),
        (4.8, 3.3), (4.8, 0.0),
    ]
    can = lathe("Can", profile)
    pull = torus("Pull", 0.7, 0.14, (4.86, 1.6, 0))
    rivet = cylinder("Rivet", 0.35, 0.2, (4.85, 0.6, 0), axis="X", vertices=16)
    return [can, pull, rivet]


def bean_label():
    # BeanLabel: 4 along X, 8.4 across: a sleeve round the can.
    profile = [(-2.0, 3.95), (-2.0, 4.12), (-1.9, 4.2), (1.9, 4.2), (2.0, 4.12), (2.0, 3.95)]
    return [lathe("Label", profile, steps=64, closed=True)]


def gas_barrel():
    # Barrel: 5 along X (up), 4 across, with rolling hoops and a bung.
    profile = [
        (-2.5, 0.0), (-2.5, 1.7), (-2.35, 1.9), (-2.2, 1.85), (-1.4, 1.95),
        (-1.25, 2.0), (-1.1, 1.95), (1.1, 1.95), (1.25, 2.0),
        (1.4, 1.95), (2.2, 1.85), (2.35, 1.9), (2.5, 1.7), (2.35, 1.6),
        (2.35, 0.0),
    ]
    barrel = lathe("Barrel", profile)
    bung = cylinder("Bung", 0.35, 0.2, (2.4, 0.9, 0), axis="X", vertices=16)
    return [barrel, bung]


def barrel_band():
    # Band: 0.6 along X, 4.2 across: the glowing hazard stripe.
    profile = [(-0.3, 1.98), (-0.3, 2.06), (-0.22, 2.1), (0.22, 2.1), (0.3, 2.06), (0.3, 1.98)]
    return [lathe("Band", profile, closed=True)]


def crate():
    # Crate: 8 wide, 8 deep, 6 tall: corner posts, rails and braces, each
    # a little behind the one before so no two faces meet (they'd flicker).
    w, d, h = 8, 8, 6
    parts = [rounded_box("Core", (w - 0.6, d - 0.6, h - 0.6), bevel=0.15)]
    for x in (-w / 2 + 0.35, w / 2 - 0.35):
        for y in (-d / 2 + 0.35, d / 2 - 0.35):
            parts.append(rounded_box("Post", (0.7, 0.7, h), (x, y, 0), bevel=0.12))
    for z in (-h / 2 + 0.4, h / 2 - 0.4):
        for y in (-d / 2 + 0.3, d / 2 - 0.3):
            parts.append(rounded_box("RailX", (w - 0.8, 0.5, 0.7), (0, y, z), bevel=0.1))
        for x in (-w / 2 + 0.3, w / 2 - 0.3):
            parts.append(rounded_box("RailY", (0.5, d - 0.8, 0.7), (x, 0, z), bevel=0.1))
    angle = math.atan2(h - 1.6, w - 1.6)
    for y in (-d / 2 + 0.33, d / 2 - 0.33):
        brace = rounded_box("Brace", (math.hypot(w - 1.6, h - 1.6), 0.4, 0.6), (0, y, 0), bevel=0.1)
        brace.rotation_euler = (0, -angle, 0)
        parts.append(brace)
    for x in (-w / 2 + 0.33, w / 2 - 0.33):
        brace = rounded_box("Brace", (0.4, math.hypot(d - 1.6, h - 1.6), 0.6), (x, 0, 0), bevel=0.1)
        brace.rotation_euler = (angle, 0, 0)
        parts.append(brace)
    return parts


def cover_wall():
    # PlazaWall: 10 wide, 2 deep, 5 tall: blocks under a cap.
    parts = [
        rounded_box("Block", (9.8, 1.8, 4.2), (0, 0, -0.3), bevel=0.25),
        rounded_box("Cap", (10, 2, 0.6), (0, 0, 2.2), bevel=0.2),
        rounded_box("Base", (10, 2, 0.4), (0, 0, -2.3), bevel=0.12),
    ]
    for z in (-1.0, 0.6):
        parts.append(rounded_box("Ridge", (9.9, 1.9, 0.14), (0, 0, z), bevel=0.05))
    for x in (-2.5, 2.5):
        parts.append(rounded_box("Joint", (0.14, 1.9, 4.0), (x, 0, -0.3), bevel=0.05))
    return parts


def bean():
    # The Bean Rain pickup: 2.4 long, 1.6 across, curved like a bean.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=1)
    obj = bpy.context.active_object
    obj.name = "Bean"
    for vertex in obj.data.vertices:
        x, y, z = vertex.co
        vertex.co.x = x * 1.2
        vertex.co.y = y * 0.8 - 0.3 * x * x
        vertex.co.z = z * 0.8
    return [obj]


# (prop, the map part it is modelled on, builder, preview colour, whether
# its long axis is Blender X standing up in the map).
PROPS = [
    ("ToiletTank", "ThroneTank", toilet_tank, (240, 240, 235), False),
    ("TankLid", "ThroneLid", tank_lid, (150, 120, 200), False),
    ("ToiletBowl", "ThroneBowl", toilet_bowl, (240, 240, 235), True),
    ("ToiletSeat", "ThroneSeat", toilet_seat, (150, 120, 200), True),
    ("BeanCan", "BeanCan", bean_can, (196, 92, 40), True),
    ("BeanLabel", "BeanLabel", bean_label, (240, 210, 120), True),
    ("GasBarrel", "Barrel", gas_barrel, (70, 110, 60), True),
    ("BarrelBand", "Band", barrel_band, (190, 240, 60), True),
    ("Crate", "Crate", crate, (120, 90, 50), False),
    ("CoverWall", "PlazaWall", cover_wall, (70, 62, 86), False),
    ("Bean", "Bean", bean, (196, 92, 40), False),
]


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def render(obj, path, upright, color):
    scene = bpy.context.scene
    kit.render_setup(scene, (420, 420), samples=40)
    kit.freestyle(scene, 1.6)
    # Near-white porcelain would burn out under the same lights.
    scene.view_settings.exposure = -0.8 if min(color) > 200 else 0
    if upright:
        # Stand it up the way the map does (Blender X to up), for the
        # picture only: the FBX is already written.
        obj.rotation_euler = (0, math.radians(-90), 0)
        bpy.context.view_layer.update()
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    center = (lo + hi) / 2
    radius = (hi - lo).length / 2
    kit.camera(center + Vector((0.9, 1.4, 0.75)).normalized() * radius * 3.0, center)
    scene.camera.data.lens = 50
    power = radius * radius
    for name, offset, energy, size in (
        ("Key", (1.2, 1.6, 2.2), 160, 2.0),
        ("Fill", (-2.0, 0.8, 0.8), 60, 3.0),
        ("Rim", (-0.6, -2.0, 1.4), 90, 2.0),
    ):
        lamp = kit.light(name, "AREA", tuple(center + Vector(offset) * radius), energy * power, size=radius * size)
        aim(lamp, center)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def build(name, modelled_on, builder, color, upright):
    kit.reset()
    obj = join(name, builder())
    kit.smooth(obj, 35)
    center, size = kit.bounds(obj)
    mat = kit.material(name, kit.srgb(*color), roughness=0.45)
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    kit.active(obj)
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(OUT, f"{name}.fbx"),
        use_selection=True,
        object_types={"MESH"},
        axis_forward="-Z",
        axis_up="Y",
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        mesh_smooth_type="FACE",
        add_leaf_bones=False,
        bake_anim=False,
    )
    entry = {
        "name": name,
        "modelledOn": modelled_on,
        "size": [round(s, 4) for s in size],
        "triangles": kit.triangles(obj),
    }
    render(obj, os.path.join(OUT, f"{name}.png"), upright, color)
    return entry


def contact_sheet(names, columns=4):
    images = [bpy.data.images.load(os.path.join(OUT, f"{n}.png")) for n in names]
    w, h = images[0].size
    rows = math.ceil(len(images) / columns)
    sheet = numpy.zeros((h * rows, w * columns, 4), dtype=numpy.float32)
    for index, image in enumerate(images):
        pixels = numpy.array(image.pixels[:], dtype=numpy.float32).reshape(h, w, 4)
        row, col = rows - 1 - index // columns, index % columns
        sheet[row * h:(row + 1) * h, col * w:(col + 1) * w] = pixels
    background = numpy.array([0.11, 0.1, 0.15, 1], dtype=numpy.float32)
    alpha = sheet[:, :, 3:4]
    sheet = sheet * alpha + background * (1 - alpha)
    sheet[:, :, 3] = 1
    out = bpy.data.images.new("Sheet", w * columns, h * rows, alpha=True)
    out.pixels = sheet.ravel()
    out.filepath_raw = os.path.join(OUT, "all.png")
    out.file_format = "PNG"
    out.save()


def save_blend(names):
    """Every prop side by side in one scene, to edit by hand."""
    kit.reset()
    x = 0.0
    for name in names:
        bpy.ops.import_scene.fbx(filepath=os.path.join(OUT, f"{name}.fbx"), axis_forward="-Z", axis_up="Y")
        for obj in bpy.context.selected_objects:
            obj.location.x += x
        x += 20
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "Props.blend"), compress=True)


def roblox_place(obj, position, upright=False, turn=0.0):
    """Puts a prop where a map part at Roblox `position` would be: stood
    up (MapKit.UPRIGHT: its X to up) and/or turned about up by `turn`
    degrees."""
    x, y, z = position
    obj.location = (x, -z, y)
    obj.rotation_euler = (0, math.radians(-90) if upright else 0, math.radians(turn))


def plaza(names):
    """Porcelain Plaza as the map lays it out, dressed with the props:
    art/export/props/plaza.png. Positions are BrainrotBattlefield's."""
    kit.reset()
    scene = bpy.context.scene
    builders = {prop[0]: prop for prop in PROPS}
    colors = {}

    def place(name, position, upright=False, turn=0.0):
        _, _, builder, color, _ = builders[name]
        obj = join(name, builder())
        kit.smooth(obj, 35)
        if name not in colors:
            colors[name] = kit.material(name, kit.srgb(*color), roughness=0.45)
        obj.data.materials.append(colors[name])
        roblox_place(obj, position, upright, turn)

    def block(size, position, color):
        bpy.ops.mesh.primitive_cube_add(size=1)
        obj = bpy.context.active_object
        obj.scale = (size[0], size[2], size[1])
        roblox_place(obj, position)
        obj.data.materials.append(kit.material(f"Block{color}", kit.srgb(*color), roughness=0.8))

    block((160, 4, 160), (0, -2, 0), (86, 74, 52))
    block((50, 0.2, 90), (0, 0.1, 0), (196, 200, 206))
    for x in (-26, 26):
        for z0, z1 in ((-45, -24), (-12, 12), (24, 45)):
            block((2, 14, z1 - z0), (x, 7, (z0 + z1) / 2), (70, 62, 86))
    for side in (-1, 1):
        # Each half's throne faces away from the centre line.
        place("ToiletTank", (0, 7, 2 * side), turn=0 if side < 0 else 180)
        place("TankLid", (0, 14.5, 2 * side))
        place("ToiletBowl", (0, 3, 10 * side), upright=True)
        place("ToiletSeat", (0, 6.5, 10 * side), upright=True)
        for x, z in ((-14, -30), (14, -22), (-6, -44)):
            place("CoverWall", (x, 2.5, z * -side))
        for x, z in ((12, -16), (-18, -14)):
            place("GasBarrel", (x, 2.5, z * -side), upright=True)
            place("BarrelBand", (x, 2.5, z * -side), upright=True)
    for x, z, turn in ((6, -26, 30), (-9, -20, -50), (16, 4, 80)):
        place("Bean", (x, 0.8, z), turn=turn)

    kit.render_setup(scene, (1280, 720), samples=64)
    kit.freestyle(scene, 1.4)
    scene.render.film_transparent = False
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = kit.srgb(150, 140, 175)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    kit.camera(Vector((44, 58, 32)), Vector((0, 4, 3)))
    scene.camera.data.lens = 30
    sun = kit.light("Sun", "SUN", (0, 0, 50), 3.5)
    aim(sun, Vector((-0.4, 0.6, -1)) + sun.location)
    sun.data.angle = math.radians(8)
    scene.render.filepath = os.path.join(OUT, "plaza.png")
    bpy.ops.render.render(write_still=True)


def write_luau(manifest):
    lines = [
        "-- The map props' meshes, made in Blender: GENERATED by",
        "-- art/blender/build_props.py. Edit the script and run it again; don't",
        "-- edit this file. Each mesh's size (Roblox axes, studs), the map part",
        "-- it was modelled on (it fills that part's box) and its triangle",
        "-- count; MapArt says which map parts each one dresses.",
        "export type Prop = { size: Vector3, modelledOn: string, triangles: number }",
        "",
        "local props: { [string]: Prop } = {",
    ]
    for entry in manifest:
        size = ", ".join(f"{s:.4f}".rstrip("0").rstrip(".") for s in entry["size"])
        lines.append(
            f"\t{entry['name']} = {{ size = Vector3.new({size}), modelledOn = \"{entry['modelledOn']}\", triangles = {entry['triangles']} }},"
        )
    lines += ["}", "", "return props", ""]
    with open(os.path.join(kit.ROOT, "src", "shared", "Config", "PropArt.luau"), "w") as f:
        f.write("\n".join(lines))


def main():
    manifest = [build(*prop) for prop in PROPS]
    names = [prop[0] for prop in PROPS]
    kit.write_json(os.path.join(OUT, "manifest.json"), manifest)
    contact_sheet(names)
    save_blend(names)
    write_luau(manifest)
    plaza(names)
    for entry in manifest:
        print(f"{entry['name']}: {entry['size']} {entry['triangles']} triangles")


if __name__ == "__main__":
    main()
