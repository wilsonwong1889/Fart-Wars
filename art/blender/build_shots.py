"""Builds the shot effects' meshes in Blender and exports them for Roblox.

    python art/blender/build_shots.py
    blender --background --python art/blender/build_shots.py

Writes art/export/effects/:
    MuzzleBurst.fbx   the cartoon flash at the muzzle: a dome with spikes
                      flaring forward (the shot goes along Blender +Y,
                      Roblox -Z)
    GasBolt.fbx       the glob of gas a shot streaks as: a round nose at
                      the front (+Y) and a tail that tapers off behind
    Splat.fbx         where a shot hits: a flat, lobed splat with droplets
                      round it, facing +Y (Roblox -Z: the game turns it to
                      face out of whatever was hit)
    ShockRing.fbx     the ring of air that spreads from the muzzle and from
                      where a shot hits, facing +Y like the splat
    shots.png         the four, rendered
and src/shared/Config/ShotArt.luau (each mesh's size, to check imports)
and src/shared/MeshData/Shots.luau (the meshes packed, for the game to
build without an import).
The game paints them in the shot's colour, glowing (Neon), and stretches
them to each weapon's sizes (WeaponFx).
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402  (before bmesh: the bpy module provides it)
import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402

import build_props as props  # noqa: E402
import kit  # noqa: E402

OUT = os.path.join(kit.EXPORT, "effects")
GLOW = (180, 255, 90)


def muzzle_burst():
    """A dome with eight spikes, long and short by turns, flaring 35
    degrees forward, and one spike straight ahead."""
    parts = []
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=0.38, location=(0, 0.05, 0))
    parts.append(bpy.context.active_object)
    flare = math.radians(35)
    for i in range(8):
        angle = 2 * math.pi * i / 8
        length = 0.75 if i % 2 == 0 else 0.5
        direction = Vector((math.cos(angle) * math.cos(flare), math.sin(flare), math.sin(angle) * math.cos(flare)))
        center = direction * (0.25 + length / 2)
        bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=0.17, radius2=0, depth=length, location=center)
        spike = bpy.context.active_object
        spike.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
        parts.append(spike)
    bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=0.24, radius2=0, depth=0.9, location=(0, 0.75, 0))
    ahead = bpy.context.active_object
    ahead.rotation_euler = Vector((0, 1, 0)).to_track_quat("Z", "Y").to_euler()
    parts.append(ahead)
    return parts


def gas_bolt():
    """A teardrop along X (stood along +Y below): a tail tapering from
    nothing to the widest point, then a round nose."""
    profile = []
    tail, nose, radius = 2.4, 0.5, 0.5
    for i in range(13):
        t = i / 12
        profile.append((-1.5 + tail * t, radius * t ** 0.75))
    for i in range(1, 9):
        t = i / 8
        angle = t * math.pi / 2
        profile.append((-1.5 + tail + nose * math.sin(angle), radius * math.cos(angle)))
    profile[0] = (-1.5, 0.0)
    profile[-1] = (-1.5 + tail + nose, 0.0)
    bolt = props.lathe("Bolt", profile, steps=16)
    # The lathe's axis is X; the bolt flies along +Y.
    bolt.rotation_euler = (0, 0, math.radians(90))
    return [bolt]


def splat():
    """A lobed blob, 0.1 thick, in the XZ plane, and four droplets."""
    thickness = 0.1
    parts = []

    def disc(name, outline, center):
        bm = bmesh.new()
        cx, cz = center
        front = [bm.verts.new((cx + x, thickness / 2, cz + z)) for x, z in outline]
        back = [bm.verts.new((cx + x, -thickness / 2, cz + z)) for x, z in outline]
        n = len(outline)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((front[i], front[j], back[j], back[i]))
        bm.faces.new(front)
        bm.faces.new(list(reversed(back)))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        return props.mesh_object(name, bm)

    lobes = []
    for i in range(48):
        angle = 2 * math.pi * i / 48
        r = 1.0 + 0.24 * math.sin(5 * angle) + 0.1 * math.sin(9 * angle + 1.0)
        lobes.append((r * math.cos(angle), r * math.sin(angle)))
    parts.append(disc("Blob", lobes, (0, 0)))
    for angle, distance, radius in ((0.6, 1.55, 0.16), (2.2, 1.6, 0.12), (3.6, 1.5, 0.14), (5.1, 1.62, 0.1)):
        circle = [(radius * math.cos(2 * math.pi * k / 12), radius * math.sin(2 * math.pi * k / 12)) for k in range(12)]
        parts.append(disc("Drop", circle, (distance * math.cos(angle), distance * math.sin(angle))))
    return parts


def shock_ring():
    """A flattened ring, round +Y: thick on the inside edge, thinning
    out."""
    profile = []
    for i in range(17):
        angle = 2 * math.pi * i / 16
        # A teardrop section: round inside, drawn out to a thin edge.
        r = 0.86 + 0.1 * math.cos(angle) * (1.35 if math.cos(angle) > 0 else 1)
        profile.append((0.07 * math.sin(angle), r))
    bm = bmesh.new()
    steps = 40
    rings = []
    for k in range(steps):
        turn = 2 * math.pi * k / steps
        rings.append([bm.verts.new((r * math.cos(turn), y, r * math.sin(turn))) for y, r in profile[:-1]])
    n = len(profile) - 1
    for k in range(steps):
        a, c = rings[k], rings[(k + 1) % steps]
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], c[j], c[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return [props.mesh_object("Ring", bm)]


SHOTS = [
    ("MuzzleBurst", muzzle_burst),
    ("GasBolt", gas_bolt),
    ("Splat", splat),
    ("ShockRing", shock_ring),
]


def build(name, builder):
    kit.reset()
    obj = props.join(name, builder())
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(obj.data)
    bm.free()
    kit.smooth(obj, 35)
    kit.uv_box(obj, 1.0)
    center, size = kit.bounds(obj)
    packed = dict(kit.mesh_data(obj), size=[round(x, 4) for x in size])
    obj.data.materials.clear()
    obj.data.materials.append(kit.material(name, kit.srgb(*GLOW), emission=1.2))
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
    return {"name": name, "size": [round(s, 4) for s in size], "triangles": kit.triangles(obj), "packed": packed}


def render_all():
    """The three side by side, from the shooter's right, on dark."""
    kit.reset()
    scene = bpy.context.scene
    for index, (name, builder) in enumerate(SHOTS):
        obj = props.join(name, builder())
        kit.smooth(obj, 35)
        obj.data.materials.append(kit.material(name, kit.srgb(*GLOW), emission=1.2))
        obj.location.x = (index - 1.5) * 4.2
        # Turned to show each best: the burst flaring towards the camera,
        # the bolt flying to the right, the splat and ring facing the
        # camera.
        obj.rotation_euler = (0, 0, math.radians({"MuzzleBurst": 200, "GasBolt": -90, "Splat": 180, "ShockRing": 160}[name]))
    kit.render_setup(scene, (1500, 420), samples=32)
    kit.freestyle(scene, 2.0)
    scene.render.film_transparent = False
    background = scene.world.node_tree.nodes["Background"]
    background.inputs["Color"].default_value = kit.srgb(28, 26, 38)
    background.inputs["Strength"].default_value = 1.0
    kit.camera(Vector((0, -18.0, 3.5)), Vector((0, 0, 0)))
    scene.camera.data.lens = 40
    lamp = kit.light("Key", "AREA", (3, -5, 6), 600, size=6)
    props.aim(lamp, Vector((0, 0, 0)))
    scene.render.filepath = os.path.join(OUT, "shots.png")
    bpy.ops.render.render(write_still=True)


def write_luau(entries):
    lines = [
        "-- The shot effects' meshes, made in Blender: GENERATED by",
        "-- art/blender/build_shots.py. Edit the script and run it again; don't",
        "-- edit this file. Each mesh's size (Roblox axes, studs; the shot goes",
        "-- along -Z) and triangle count. WeaponFx says how big each weapon's",
        "-- are; WeaponFxController finds the imports in",
        "-- ReplicatedStorage.Assets.Effects.",
        "export type Shot = { size: Vector3, triangles: number }",
        "",
        "local shots: { [string]: Shot } = {",
    ]
    for entry in entries:
        size = ", ".join(f"{s:.4f}".rstrip("0").rstrip(".") for s in entry["size"])
        lines.append(f"\t{entry['name']} = {{ size = Vector3.new({size}), triangles = {entry['triangles']} }},")
    lines += ["}", "", "return shots", ""]
    with open(os.path.join(kit.ROOT, "src", "shared", "Config", "ShotArt.luau"), "w") as f:
        f.write("\n".join(lines))


def main():
    entries = [build(name, builder) for name, builder in SHOTS]
    write_luau(entries)
    kit.write_mesh_module(
        os.path.join(kit.ROOT, "src", "shared", "MeshData", "Shots.luau"),
        [
            "The shot effects' meshes, packed: GENERATED by art/blender/build_shots.py.",
            "Edit the script and run it again; don't edit this file. MeshBuilder",
            "builds them in the game, so they show without importing anything;",
            "Config/ShotArt has their sizes. The format is kit.mesh_data's.",
        ],
        {entry["name"]: entry["packed"] for entry in entries},
    )
    render_all()
    for entry in entries:
        print(f"{entry['name']}: {entry['size']} {entry['triangles']} triangles")


if __name__ == "__main__":
    main()
