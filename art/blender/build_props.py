"""Builds the map's props, walls and floors in Blender and exports them for
Roblox.

    python art/blender/build_props.py            (everything)
    python art/blender/build_props.py renders    (just the map renders)
    blender --background --python art/blender/build_props.py [-- renders]

Each prop is modelled at the exact size of the map part it dresses (the
part stays as the collision and line-of-sight box; the mesh is drawn over
it), so cover and sightlines don't change. Walls, trims and floors are
modules the game repeats along their parts. Every mesh has UVs in studs,
for Roblox's material textures. Writes art/export/props/:
    <Prop>.fbx    one mesh, named after the prop, for Studio's 3D importer
    <Prop>.png    a preview render
    Props.blend   every prop in one Blender scene, to edit by hand
    all.png       the previews together
    plaza.png, map.png, spawn.png
                  the map as the game builds it, dressed (from layout.txt,
                  which scripts/map_layout.py writes from the map's code)
and src/shared/Config/PropArt.luau (each mesh's size, to check imports).

Cylinders run along Blender X (Roblox X, the axis of a Roblox cylinder
part); blocks are sized x (width), y (depth, Roblox -Z), z (height, Roblox
+Y). The front of an asymmetric prop faces Blender +Y (Roblox -Z).
"""

import json
import math
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402  (before bmesh: the bpy module provides it)
import bmesh  # noqa: E402
import numpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

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


# Walls and floors: modules that MapDressing repeats along a part (PROPS'
# `tile`), each sized so its neighbours meet it cleanly. Built with
# chamfers rather than round bevels: there are hundreds of them in a map.


def chamfered(name, size, center=(0, 0, 0), bevel=0.12):
    return rounded_box(name, size, center, bevel=bevel, segments=1)


def extrude(name, profile, x0, x1):
    """A solid made by sweeping a closed (y, z) outline along X from x0 to
    x1: one shape, so nothing inside it can show through or flicker."""
    bm = bmesh.new()
    a = [bm.verts.new((x0, y, z)) for y, z in profile]
    b = [bm.verts.new((x1, y, z)) for y, z in profile]
    n = len(profile)
    for i in range(n):
        bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    bm.faces.new(list(reversed(a)))
    bm.faces.new(b)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_object(name, bm)


def wall_tile(height, bands):
    """A wall module 8 long (X), 2 thick (Y), `height` tall: half a post at
    each end (two neighbours make a whole one; an open end of a wall shows
    a clean post) and between them a panel with a base and a cap moulding
    and raised bands. The same on both faces, so it can face either way.
    The panel stops at the posts, so no two end faces lie on each other."""
    length, depth = 8.0, 2.0
    half, post = height / 2, 0.7
    inner = length / 2 - post
    profile = [
        (-0.95, -half), (0.95, -half), (0.95, -half + 0.8), (0.75, -half + 1.0),
        (0.75, half - 0.8), (0.95, half - 0.6), (0.95, half), (-0.95, half),
        (-0.95, half - 0.6), (-0.75, half - 0.8), (-0.75, -half + 1.0), (-0.95, -half + 0.8),
    ]
    parts = [extrude("Panel", profile, -inner, inner)]
    for x in (-length / 2 + post / 2, length / 2 - post / 2):
        parts.append(chamfered("Post", (post, depth, height), (x, 0, 0), bevel=0.1))
    for z in bands:
        parts.append(chamfered("Band", (2 * inner, 1.75, 0.35), (0, 0, z), bevel=0.08))
    return parts


def wall():
    # Divider: 14 tall; also the spawn rooms' walls (16, a little taller).
    return wall_tile(14, (-3.0, 2.4))


def tall_wall():
    # SideWall and EndWall: the arena's 24-tall boundary.
    return wall_tile(24, (-6.5, -0.5, 5.5))


def wall_trim():
    # SideTrim, EndTrim, SpawnFrontTrim: 8 long, 1 tall, 2.4 deep: a neon
    # rail with a rounded bead along its top, as one swept outline.
    profile = [(-1.2, -0.5), (1.2, -0.5), (1.2, -0.12), (1.08, 0.0), (0.5, 0.0)]
    for i in range(1, 12):
        t = math.pi * i / 12
        profile.append((0.5 * math.cos(t), 0.5 * math.sin(t)))
    profile += [(-0.5, 0.0), (-1.08, 0.0), (-1.2, -0.12)]
    return [extrude("Trim", profile, -4, 4)]


def drop_bottoms(obj):
    """Deletes the faces nobody sees: those facing straight down."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    down = [f for f in bm.faces if f.normal.z < -0.99]
    bmesh.ops.delete(bm, geom=down, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()


def floor_module(stones, gap):
    """A 10 x 10 floor module 0.2 thick made of `stones`: (x0, y0, x1, y1,
    height) rectangles. Each is inset by half the gap, so the gaps between
    modules match the gaps inside them."""
    parts = []
    for x0, y0, x1, y1, h in stones:
        size = (x1 - x0 - gap, y1 - y0 - gap, h)
        center = ((x0 + x1) / 2, (y0 + y1) / 2, -0.1 + h / 2)
        stone = chamfered("Stone", size, center, bevel=0.05)
        kit.apply_modifiers(stone)
        drop_bottoms(stone)
        parts.append(stone)
    # The grout bed: fills the module edge to edge, so the gaps between
    # modules come out the same as the gaps inside one.
    bed = chamfered("Bed", (10, 10, 0.06), (0, 0, -0.07), bevel=0)
    drop_bottoms(bed)
    parts.append(bed)
    return parts


def plaza_tiles():
    # LaneCenterFloor (Porcelain Plaza): square tiles, 4 x 4 to a module.
    stones = []
    for i in range(4):
        for j in range(4):
            stones.append((-5 + i * 2.5, -5 + j * 2.5, -5 + (i + 1) * 2.5, -5 + (j + 1) * 2.5, 0.2))
    return floor_module(stones, 0.14)


def flagstones():
    # LaneLeftFloor and LaneRightFloor: flagstones in running courses, a
    # few a little lower than the rest.
    rows = [
        (3.0, 2.5, 4.5),
        (2.0, 4.0, 4.0),
        (3.5, 3.0, 3.5),
        (4.0, 2.5, 3.5),
    ]
    heights = [0.2, 0.17, 0.2, 0.18, 0.2, 0.16, 0.19, 0.2, 0.17, 0.2, 0.18, 0.2]
    stones = []
    k = 0
    for r, widths in enumerate(rows):
        x = -5.0
        for w in widths:
            stones.append((x, -5 + r * 2.5, x + w, -5 + (r + 1) * 2.5, heights[k % len(heights)]))
            x += w
            k += 1
    return floor_module(stones, 0.18)


def heightfield(name, xs, ys, height, bottom, closed=True):
    """A slab whose top is `height(x, y)` on the grid `xs` x `ys`, with flat
    sides down to `bottom` (the edges of the top should be level so
    modules meet without a step) and, if `closed`, a bottom."""
    bm = bmesh.new()
    top = [[bm.verts.new((x, y, height(x, y))) for y in ys] for x in xs]
    nx, ny = len(xs), len(ys)
    for i in range(nx - 1):
        for j in range(ny - 1):
            bm.faces.new((top[i][j], top[i + 1][j], top[i + 1][j + 1], top[i][j + 1]))
    ring = [top[i][0] for i in range(nx)] + [top[nx - 1][j] for j in range(1, ny)]
    ring += [top[i][ny - 1] for i in range(nx - 2, -1, -1)] + [top[0][j] for j in range(ny - 2, 0, -1)]
    low = [bm.verts.new((v.co.x, v.co.y, bottom)) for v in ring]
    n = len(ring)
    for k in range(n):
        bm.faces.new((ring[k], low[k], low[(k + 1) % n], ring[(k + 1) % n]))
    if closed:
        bm.faces.new(list(reversed(low)))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    else:
        # An open shell: recalc can't tell inside from out, so make the
        # top face up and the sides follow it.
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        if sum(f.normal.z * f.calc_area() for f in bm.faces) < 0:
            bmesh.ops.reverse_faces(bm, faces=bm.faces)
    return mesh_object(name, bm)


def spawn_tiles():
    # SpawnFloor: 8 x 8 modules of four big panels with V grooves between
    # them, see-through in the team colour. One open surface (no bottom,
    # nothing overlapping), so it reads cleanly through itself.
    lines = [-4.0, -3.8, -0.2, 0.0, 0.2, 3.8, 4.0]

    def low(c):
        return abs(abs(c) - 4.0) < 1e-6 or abs(c) < 1e-6

    def height(x, y):
        return -0.02 if low(x) or low(y) else 0.1

    return [heightfield("Panels", lines, lines, height, -0.1, closed=False)]


def ground_tile():
    """Ground: 20 x 20 modules 4 thick, the top gently dipped. The dips
    are zero along the edges so modules meet without a step, and never
    above the top, so the mesh fills the part's box exactly."""
    size, depth, steps = 20.0, 4.0, 10
    blobs = [(-4.0, 3.0, 4.5, 0.32), (5.0, -2.0, 5.0, 0.26), (-1.0, -6.0, 3.5, 0.2), (6.0, 6.0, 3.0, 0.18)]

    def height(x, y):
        u, v = (x + size / 2) / size, (y + size / 2) / size
        window = (math.sin(math.pi * u) * math.sin(math.pi * v)) ** 2
        dip = sum(d * math.exp(-((x - bx) ** 2 + (y - by) ** 2) / (r * r)) for bx, by, r, d in blobs)
        return depth / 2 - min(dip, 0.4) * window

    grid = [-size / 2 + size * i / steps for i in range(steps + 1)]
    return [heightfield("Ground", grid, grid, height, -depth / 2)]


def spawn_pad():
    # Pad1-Pad4 (SpawnLocations): 6 x 6, 1 tall: a round pad with a raised
    # ring and a dome in the middle.
    profile = [
        (-0.5, 0.0), (-0.5, 2.9), (-0.42, 3.0), (-0.1, 3.0), (0.0, 2.85),
        (0.0, 2.6), (0.35, 2.5), (0.5, 2.3), (0.35, 2.05), (0.05, 2.0),
        (0.05, 1.1), (0.3, 0.9), (0.45, 0.5), (0.5, 0.0),
    ]
    pad = lathe("Pad", profile, steps=48)
    # Stand it up: the lathe's axis is X, the pad's is up.
    pad.rotation_euler = (0, math.radians(-90), 0)
    return [pad]


# Every prop: its name, the map part it is modelled on (it fills that
# part's box, or one module of it), its builder and preview colour.
#   upright  its long axis is Blender X, standing up in the map (preview)
#   tile     the axes (Roblox x, y, z) MapDressing repeats it along
#   studs    studs per repeat of the material's texture (it divides the
#            module, so the texture runs on across modules)


def prop(name, modelled_on, builder, color, upright=False, tile="", studs=4.0):
    return {"name": name, "modelledOn": modelled_on, "builder": builder, "color": color,
            "upright": upright, "tile": tile, "studs": studs}


PROPS = [
    prop("ToiletTank", "ThroneTank", toilet_tank, (240, 240, 235)),
    prop("TankLid", "ThroneLid", tank_lid, (150, 120, 200)),
    prop("ToiletBowl", "ThroneBowl", toilet_bowl, (240, 240, 235), upright=True),
    prop("ToiletSeat", "ThroneSeat", toilet_seat, (150, 120, 200), upright=True),
    prop("BeanCan", "BeanCan", bean_can, (196, 92, 40), upright=True),
    prop("BeanLabel", "BeanLabel", bean_label, (240, 210, 120), upright=True),
    prop("GasBarrel", "Barrel", gas_barrel, (70, 110, 60), upright=True),
    prop("BarrelBand", "Band", barrel_band, (190, 240, 60), upright=True),
    prop("Crate", "Crate", crate, (120, 90, 50)),
    prop("CoverWall", "PlazaWall", cover_wall, (70, 62, 86)),
    prop("Bean", "Bean", bean, (196, 92, 40)),
    prop("Wall", "Divider", wall, (70, 62, 86), tile="x"),
    prop("TallWall", "SideWall", tall_wall, (70, 62, 86), tile="x"),
    prop("WallTrim", "SideTrim", wall_trim, (150, 120, 200), tile="x"),
    prop("PlazaTiles", "LaneCenterFloor", plaza_tiles, (196, 200, 206), tile="xz", studs=5.0),
    prop("Flagstones", "LaneLeftFloor", flagstones, (120, 92, 60), tile="xz", studs=5.0),
    prop("SpawnTiles", "SpawnFloor", spawn_tiles, (102, 255, 51), tile="xz"),
    prop("GroundTile", "Ground", ground_tile, (86, 74, 52), tile="xz", studs=5.0),
    prop("SpawnPad", "Pad1", spawn_pad, (102, 255, 51)),
]


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def module_offsets(entry, size):
    """Where the preview repeats a module: three along a wall, two by two
    on a floor (Blender axes)."""
    tile = entry["tile"]
    if not tile:
        return [Vector((0, 0, 0))]
    xs = range(-1, 2) if "z" not in tile else range(0, 2)
    ys = range(0, 2) if "z" in tile else range(0, 1)
    # Roblox x, z = Blender x, -y; size is Roblox (x, y, z).
    return [Vector((i * size[0], -j * size[2], 0)) for i in xs for j in ys]


def render(obj, path, entry, size):
    scene = bpy.context.scene
    kit.render_setup(scene, (420, 420), samples=40)
    kit.freestyle(scene, 1.6)
    color = entry["color"]
    # Near-white porcelain would burn out under the same lights.
    scene.view_settings.exposure = -0.8 if min(color) > 200 else 0
    if entry["upright"]:
        # Stand it up the way the map does (Blender X to up), for the
        # picture only: the FBX is already written.
        obj.rotation_euler = (0, math.radians(-90), 0)
    # Modules are shown repeated, the way the map lays them.
    for offset in module_offsets(entry, size):
        if offset.length == 0:
            continue
        copy = obj.copy()
        copy.location = obj.location + offset
        bpy.context.scene.collection.objects.link(copy)
    bpy.context.view_layer.update()
    points = []
    for item in bpy.context.scene.objects:
        if item.type == "MESH":
            points += [item.matrix_world @ Vector(c) for c in item.bound_box]
    lo = Vector((min(c.x for c in points), min(c.y for c in points), min(c.z for c in points)))
    hi = Vector((max(c.x for c in points), max(c.y for c in points), max(c.z for c in points)))
    center = (lo + hi) / 2
    radius = (hi - lo).length / 2
    kit.camera(center + Vector((0.9, 1.4, 0.75)).normalized() * radius * 3.0, center)
    scene.camera.data.lens = 50
    power = radius * radius
    for name, offset, energy, area in (
        ("Key", (1.2, 1.6, 2.2), 160, 2.0),
        ("Fill", (-2.0, 0.8, 0.8), 60, 3.0),
        ("Rim", (-0.6, -2.0, 1.4), 90, 2.0),
    ):
        lamp = kit.light(name, "AREA", tuple(center + Vector(offset) * radius), energy * power, size=radius * area)
        aim(lamp, center)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def build_mesh(entry):
    """The prop as one smoothed, UV-mapped mesh object, in triangles (the
    swept wall outlines have many-sided, inward-cornered ends, and this
    way they're split here rather than however an importer guesses)."""
    obj = join(entry["name"], entry["builder"]())
    kit.uv_box(obj, entry["studs"])
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(obj.data)
    bm.free()
    kit.smooth(obj, 35)
    return obj


def build(entry):
    name = entry["name"]
    kit.reset()
    obj = build_mesh(entry)
    center, size = kit.bounds(obj)
    mat = kit.material(name, kit.srgb(*entry["color"]), roughness=0.45)
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
    size = [round(s, 4) for s in size]
    out = {
        "name": name,
        "modelledOn": entry["modelledOn"],
        "size": size,
        "triangles": kit.triangles(obj),
    }
    if entry["tile"]:
        out["tile"] = [size[i] if axis in entry["tile"] else 0 for i, axis in enumerate("xyz")]
    render(obj, os.path.join(OUT, f"{name}.png"), entry, size)
    return out


def contact_sheet(names, columns=5):
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
        x += 26
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "Props.blend"), compress=True)


# Roblox to Blender: (x, y, z) -> (x, -z, y).
R2B = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))

MATERIALS = {
    # Roblox material: (roughness, metallic, emission)
    "Neon": (0.4, 0.0, 1.6),
    "Metal": (0.35, 0.6, 0.0),
    "Marble": (0.25, 0.0, 0.0),
    "SmoothPlastic": (0.35, 0.0, 0.0),
}


def read_layout():
    """art/export/props/layout.txt (scripts/map_layout.py): the map as the
    game builds it, dressed. Each line: name prop shape material r g b
    transparency, a Roblox CFrame's 12 numbers and a size."""
    path = os.path.join(OUT, "layout.txt")
    items = []
    with open(path) as f:
        for line in f:
            fields = line.split()
            if len(fields) < 23:
                continue
            numbers = [float(x) for x in fields[8:]]
            items.append({
                "name": fields[0],
                "prop": fields[1],
                "shape": fields[2],
                "material": fields[3],
                "color": tuple(int(x) for x in fields[4:7]),
                "transparency": float(fields[7]),
                "cframe": numbers[0:12],
                "size": numbers[12:15],
            })
    return items


def refresh_layout():
    """Re-runs scripts/map_layout.py when luau is installed, so the renders
    follow the map's code; otherwise uses the layout.txt in the repo."""
    script = os.path.join(kit.ROOT, "scripts", "map_layout.py")
    try:
        subprocess.run(["python3", script], check=True, cwd=kit.ROOT)
    except (OSError, subprocess.CalledProcessError) as err:
        print(f"map_layout.py didn't run ({err}); using the layout.txt there is")


def place_matrix(cframe, scale):
    """A Roblox CFrame and a scale along its own axes, as a Blender object
    matrix (the meshes were exported Blender -> Roblox by R2B)."""
    x, y, z = cframe[0:3]
    r = Matrix((cframe[3:6], cframe[6:9], cframe[9:12]))
    rotation = R2B @ r @ R2B.transposed()
    matrix = rotation.to_4x4() @ Matrix.Diagonal((scale[0], scale[2], scale[1], 1))
    matrix.translation = R2B @ Vector((x, y, z))
    return matrix


def layout_scene(items, art):
    """Builds the dressed map in the current (empty) scene."""
    meshes = {}
    entries = {entry["name"]: entry for entry in PROPS}
    materials = {}

    def material_for(item):
        key = (item["material"], item["color"], round(item["transparency"], 2))
        if key not in materials:
            rough, metal, glow = MATERIALS.get(item["material"], (0.6, 0.0, 0.0))
            color = kit.srgb(*item["color"])
            materials[key] = kit.material(f"{key}", color, metallic=metal, roughness=rough, emission=glow, alpha=1 - item["transparency"])
        return materials[key]

    for item in items:
        if item["prop"] != "-":
            name = item["prop"]
            if name not in meshes:
                obj = build_mesh(entries[name])
                meshes[name] = obj.data
                bpy.data.objects.remove(obj)
            size = art[name]
            scale = [item["size"][i] / size[i] for i in range(3)]
            data = meshes[name]
        else:
            # A plain part: a unit block, cylinder (along its X) or ball.
            key = "Part" + item["shape"]
            if key not in meshes:
                if item["shape"] == "Cylinder":
                    bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=0.5, depth=1, rotation=(0, math.radians(90), 0))
                elif item["shape"] == "Ball":
                    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.5)
                else:
                    bpy.ops.mesh.primitive_cube_add(size=1)
                obj = bpy.context.active_object
                bpy.ops.object.transform_apply(rotation=True)
                meshes[key] = obj.data
                bpy.data.objects.remove(obj)
            scale = item["size"]
            data = meshes[key]
        obj = bpy.data.objects.new(item["name"], data)
        obj.matrix_world = place_matrix(item["cframe"], scale)
        # Shared mesh data, so each object carries its own material.
        if not obj.data.materials:
            obj.data.materials.append(None)
        slot = obj.material_slots[0]
        slot.link = "OBJECT"
        slot.material = material_for(item)
        bpy.context.scene.collection.objects.link(obj)


def map_render(items, art, filename, camera_from, look_at, lens, size=(1600, 900), samples=48):
    kit.reset()
    scene = bpy.context.scene
    layout_scene(items, art)
    kit.render_setup(scene, size, samples=samples)
    kit.freestyle(scene, 1.2)
    scene.render.film_transparent = False
    background = scene.world.node_tree.nodes["Background"]
    background.inputs["Color"].default_value = kit.srgb(150, 140, 175)
    background.inputs["Strength"].default_value = 0.9
    kit.camera(R2B @ Vector(camera_from), R2B @ Vector(look_at))
    scene.camera.data.lens = lens
    scene.camera.data.clip_end = 2000
    sun = kit.light("Sun", "SUN", (0, 0, 100), 3.5)
    aim(sun, Vector((-0.4, 0.6, -1)) + sun.location)
    sun.data.angle = math.radians(8)
    scene.render.filepath = os.path.join(OUT, filename)
    bpy.ops.render.render(write_still=True)


def map_renders():
    refresh_layout()
    items = read_layout()
    with open(os.path.join(OUT, "manifest.json")) as f:
        art = {entry["name"]: entry["size"] for entry in json.load(f)}
    # Roblox coordinates: the throne at the centre, the Stinkers at -Z.
    map_render(items, art, "plaza.png", (46, 30, -60), (0, 4, -6), 30)
    map_render(items, art, "map.png", (150, 150, -175), (0, 0, -8), 32)
    map_render(items, art, "spawn.png", (36, 22, -36), (0, 5, -66), 26)


def write_luau(manifest):
    lines = [
        "-- The map's Blender meshes: GENERATED by art/blender/build_props.py.",
        "-- Edit the script and run it again; don't edit this file. Each mesh's",
        "-- size (Roblox axes, studs), the map part it was modelled on (it fills",
        "-- that part's box, or one module of it), its triangle count, and for",
        "-- a module (walls, trims, floors) `tile`: its size along each axis",
        "-- MapDressing repeats it on (0: stretched to fit instead). MapArt",
        "-- says which map parts each one dresses.",
        "export type Prop = { size: Vector3, modelledOn: string, triangles: number, tile: Vector3? }",
        "",
        "local props: { [string]: Prop } = {",
    ]
    for entry in manifest:
        size = ", ".join(f"{s:.4f}".rstrip("0").rstrip(".") for s in entry["size"])
        tile = ""
        if "tile" in entry:
            tile = ", tile = Vector3.new(" + ", ".join(f"{t:.4f}".rstrip("0").rstrip(".") for t in entry["tile"]) + ")"
        lines.append(
            f"\t{entry['name']} = {{ size = Vector3.new({size}), modelledOn = \"{entry['modelledOn']}\", triangles = {entry['triangles']}{tile} }},"
        )
    lines += ["}", "", "return props", ""]
    with open(os.path.join(kit.ROOT, "src", "shared", "Config", "PropArt.luau"), "w") as f:
        f.write("\n".join(lines))


def main():
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    if only == ["renders"]:
        # Just the map renders, from the props already built.
        map_renders()
        return
    manifest = [build(entry) for entry in PROPS]
    names = [entry["name"] for entry in PROPS]
    kit.write_json(os.path.join(OUT, "manifest.json"), manifest)
    contact_sheet(names)
    save_blend(names)
    write_luau(manifest)
    map_renders()
    for entry in manifest:
        print(f"{entry['name']}: {entry['size']} {entry['triangles']} triangles")


if __name__ == "__main__":
    main()
