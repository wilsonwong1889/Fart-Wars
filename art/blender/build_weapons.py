"""Builds the four Fart Wars weapons in Blender and exports them for Roblox.

    python art/blender/build_weapons.py          (with pip's bpy)
    blender --background --python art/blender/build_weapons.py

For each weapon it writes, under art/export/weapons/:
    <Weapon>.fbx    one mesh per role (Body, Metal, Grip, Trim, Glass, Gas,
                    Bomb), for Studio's 3D importer
    <Weapon>.blend  the Blender scene, to edit by hand
    <Weapon>.png    a preview render
and under art/export/icons/<Weapon>.png the hotbar icon. It also writes
the part list the game builds from (manifest.json) and its Luau copy,
src/shared/Config/WeaponArt.luau. Edit this script, not the outputs.

The grip is at the origin; the barrel points along Blender +Y (Roblox -Z),
the top is Blender +Z (Roblox +Y). Sizes are in studs.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import numpy  # noqa: E402

import kit  # noqa: E402

OUT = os.path.join(kit.EXPORT, "weapons")
ICONS = os.path.join(kit.EXPORT, "icons")

METAL = (55, 52, 66)
GRIP = (34, 31, 40)
GLASS = (205, 240, 255)

# Each weapon: its colours, and how it's put together.
WEAPONS = [
    {
        "id": "GasBlaster",
        "body": (128, 212, 58),
        "trim": (255, 214, 60),
        "gas": (180, 255, 90),
    },
    {
        "id": "Spritzer",
        "body": (58, 186, 232),
        "trim": (240, 250, 255),
        "gas": (120, 230, 255),
    },
    {
        "id": "Thunderclapper",
        "body": (238, 136, 40),
        "trim": (255, 222, 70),
        "gas": (255, 170, 60),
    },
    {
        "id": "StinkLobber",
        "body": (118, 148, 52),
        "trim": (150, 102, 52),
        "gas": (160, 200, 60),
        "bomb": (104, 158, 48),
    },
]


def trigger(b, y):
    # The guard is a ring on its side: the stand-in model (parts) leaves it out.
    b.ring("Metal", 0.13, 0.028, (0, y, 0.06), axis="X", standin=False)
    b.box("Trim", (0.06, 0.07, 0.17), (0, y + 0.02, 0.1), bevel=0.02, rotation=(-15, 0, 0))


def gas_blaster(b):
    b.box("Grip", (0.32, 0.42, 0.85), (0, -0.04, -0.15), bevel=0.1, rotation=(-15, 0, 0))
    b.box("Body", (0.5, 1.5, 0.5), (0, 0.45, 0.45), bevel=0.13)
    b.box("Body", (0.42, 0.38, 0.42), (0, -0.4, 0.43), bevel=0.12)
    b.box("Metal", (0.18, 1.05, 0.08), (0, 0.42, 0.73), bevel=0.03)
    b.cyl("Metal", 0.13, 0.8, (0, 1.55, 0.47))
    b.ring("Trim", 0.15, 0.04, (0, 1.32, 0.47))
    b.ring("Trim", 0.15, 0.04, (0, 1.72, 0.47))
    b.cyl("Trim", 0.25, 0.22, (0, 2.03, 0.47), radius2=0.16)
    b.cyl("Glass", 0.2, 0.74, (0, 0.3, 0.97))
    b.cyl("Gas", 0.155, 0.66, (0, 0.3, 0.97), bevel=0)
    b.cyl("Metal", 0.215, 0.08, (0, -0.09, 0.97))
    b.cyl("Metal", 0.215, 0.08, (0, 0.69, 0.97))
    b.box("Metal", (0.12, 0.1, 0.2), (0, 0.04, 0.8), bevel=0.02)
    b.box("Metal", (0.12, 0.1, 0.2), (0, 0.56, 0.8), bevel=0.02)
    b.cyl("Trim", 0.1, 0.06, (0.27, -0.05, 0.47), axis="X")
    trigger(b, 0.12)
    return (0, 2.15, 0.47)


def spritzer(b):
    b.box("Grip", (0.3, 0.4, 0.8), (0, -0.04, -0.12), bevel=0.1, rotation=(-15, 0, 0))
    b.box("Body", (0.48, 1.05, 0.62), (0, 0.3, 0.45), bevel=0.17)
    b.box("Trim", (0.5, 0.1, 0.64), (0, 0.66, 0.45), bevel=0.04)
    b.ball("Glass", 0.3, (0, 0.08, 1.04))
    b.ball("Gas", 0.24, (0, 0.08, 1.04))
    b.cyl("Metal", 0.13, 0.14, (0, 0.08, 0.76), axis="Z")
    b.cyl("Metal", 0.06, 0.95, (0, 1.25, 0.5))
    b.cyl("Trim", 0.13, 0.18, (0, 1.78, 0.5), radius2=0.07)
    b.box("Body", (0.26, 0.5, 0.2), (0, 1.08, 0.24), bevel=0.07)
    b.box("Metal", (0.08, 0.3, 0.1), (0, 1.08, 0.35), bevel=0.02)
    trigger(b, 0.12)
    return (0, 1.88, 0.5)


def thunderclapper(b):
    b.box("Grip", (0.34, 0.44, 0.9), (0, -0.08, -0.15), bevel=0.1, rotation=(-12, 0, 0))
    b.box("Grip", (0.28, 0.32, 0.6), (0, 1.05, 0.02), bevel=0.09, rotation=(10, 0, 0))
    b.box("Body", (0.72, 2.0, 0.72), (0, 0.6, 0.5), bevel=0.16)
    b.box("Trim", (0.74, 1.2, 0.12), (0, 0.72, 0.56), bevel=0.04)
    b.box("Body", (0.6, 0.6, 0.6), (0, -0.62, 0.46), bevel=0.15)
    b.box("Grip", (0.62, 0.12, 0.62), (0, -0.95, 0.46), bevel=0.05)
    b.cyl("Metal", 0.24, 0.95, (0, 2.0, 0.5))
    for y in (1.72, 1.92, 2.12):
        b.ring("Metal", 0.26, 0.055, (0, y, 0.5))
    b.cyl("Trim", 0.38, 0.36, (0, 2.6, 0.5), radius2=0.26)
    for x in (-0.17, 0.17):
        b.cyl("Glass", 0.16, 1.0, (x, 0.42, 1.06))
        b.cyl("Gas", 0.12, 0.92, (x, 0.42, 1.06), bevel=0)
    for y in (0.0, 0.84):
        b.box("Metal", (0.72, 0.09, 0.4), (0, y, 1.0), bevel=0.03)
    trigger(b, 0.08)
    return (0, 2.8, 0.5)


def stink_lobber(b):
    b.box("Grip", (0.32, 0.42, 0.85), (0, -0.04, -0.15), bevel=0.1, rotation=(-15, 0, 0))
    b.box("Body", (0.55, 1.0, 0.55), (0, 0.25, 0.42), bevel=0.13)
    b.cyl("Body", 0.34, 1.3, (0, 0.95, 0.8), bevel=0.04)
    b.ring("Trim", 0.33, 0.065, (0, 1.6, 0.8))
    b.ring("Trim", 0.33, 0.05, (0, 0.33, 0.8))
    b.cyl("Metal", 0.29, 0.05, (0, 1.56, 0.8), bevel=0)
    b.ball("Bomb", 0.27, (0, 1.74, 0.8))
    b.cyl("Trim", 0.035, 0.2, (0, 1.78, 1.12), axis="Z")
    b.cyl("Glass", 0.15, 0.6, (0.36, 0.25, 0.42))
    b.cyl("Gas", 0.11, 0.52, (0.36, 0.25, 0.42), bevel=0)
    b.box("Metal", (0.08, 0.2, 0.26), (0, 0.55, 1.24), bevel=0.02)
    trigger(b, 0.1)
    return (0, 1.9, 0.8)


BUILDERS = {
    "GasBlaster": gas_blaster,
    "Spritzer": spritzer,
    "Thunderclapper": thunderclapper,
    "StinkLobber": stink_lobber,
}


def roles_for(weapon):
    roles = {
        "Body": {"color": weapon["body"], "material": "SmoothPlastic", "transparency": 0, "blender": kit.material("Body", kit.srgb(*weapon["body"]), roughness=0.35)},
        "Metal": {"color": METAL, "material": "Metal", "transparency": 0, "blender": kit.material("Metal", kit.srgb(*METAL), metallic=0.85, roughness=0.32)},
        "Grip": {"color": GRIP, "material": "SmoothPlastic", "transparency": 0, "blender": kit.material("Grip", kit.srgb(*GRIP), roughness=0.75)},
        "Trim": {"color": weapon["trim"], "material": "SmoothPlastic", "transparency": 0, "blender": kit.material("Trim", kit.srgb(*weapon["trim"]), roughness=0.3)},
        "Glass": {"color": GLASS, "material": "Glass", "transparency": 0.55, "blender": kit.material("Glass", kit.srgb(*GLASS), roughness=0.05, transmission=0.9, alpha=0.35)},
        "Gas": {"color": weapon["gas"], "material": "Neon", "transparency": 0, "blender": kit.material("Gas", kit.srgb(*weapon["gas"]), emission=0.8)},
    }
    if "bomb" in weapon:
        roles["Bomb"] = {"color": weapon["bomb"], "material": "SmoothPlastic", "transparency": 0, "blender": kit.material("Bomb", kit.srgb(*weapon["bomb"]), roughness=0.5)}
    return roles


def render(path, size, view):
    scene = bpy.context.scene
    kit.render_setup(scene, size)
    # Frame the whole weapon (Blender axes).
    from mathutils import Vector

    corners = [o.matrix_world @ Vector(c) for o in scene.objects if o.type == "MESH" for c in o.bound_box]
    lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    center = (lo + hi) / 2
    extent = hi - lo
    if view == "icon":
        # The right side, a little from above: barrel to the right.
        kit.camera(center + Vector((8, 0.6, 1.6)), center, ortho_scale=max(extent.y, extent.z) * 1.18)
    else:
        kit.camera(center + Vector((5.2, -3.4, 2.4)), center)
        scene.camera.data.lens = 50 * 3.2 / max(extent.y, 2.6)
    kit.freestyle(scene, 2.5 if view == "preview" else 4.0)
    kit.light("Key", "AREA", (3, -2, 4), 800, size=3)
    kit.light("Fill", "AREA", (-3, 1, 2), 300, size=4)
    kit.light("Rim", "AREA", (0, 4, 3), 500, size=2)
    kit.light("Front", "AREA", (6, 1, 1), 220, size=4)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    for obj in [o for o in scene.objects if o.type in ("LIGHT", "CAMERA")]:
        bpy.data.objects.remove(obj)


def build(weapon):
    kit.reset()
    roles = roles_for(weapon)
    b = kit.Builder(weapon["id"], {role: {"material": spec["blender"]} for role, spec in roles.items()})
    muzzle = BUILDERS[weapon["id"]](b)
    joined = b.join()

    meshes = {}
    for role, obj in joined.items():
        center, size = kit.bounds(obj)
        meshes[role] = {
            "center": [round(c, 4) for c in center],
            "size": [round(s, 4) for s in size],
            "triangles": kit.triangles(obj),
        }
    os.makedirs(OUT, exist_ok=True)
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    for obj in joined.values():
        obj.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(OUT, f"{weapon['id']}.fbx"),
        use_selection=True,
        object_types={"MESH"},
        axis_forward="-Z",
        axis_up="Y",
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        mesh_smooth_type="FACE",
        use_mesh_modifiers=True,
        add_leaf_bones=False,
        bake_anim=False,
    )
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, f"{weapon['id']}.blend"), compress=True)

    # Renders: outlined, like the game's chunky UI.
    render(os.path.join(OUT, f"{weapon['id']}.png"), (640, 400), "preview")
    render(os.path.join(ICONS, f"{weapon['id']}.png"), (512, 512), "icon")

    return {
        "id": weapon["id"],
        "muzzle": [round(c, 4) for c in kit.to_roblox(muzzle)],
        "roles": {role: {"color": list(spec["color"]), "material": spec["material"], "transparency": spec["transparency"]} for role, spec in roles.items()},
        "meshes": meshes,
        "pieces": b.pieces,
    }


def contact_sheet(ids):
    """All four previews in one image, two by two."""
    images = [bpy.data.images.load(os.path.join(OUT, f"{i}.png")) for i in ids]
    w, h = images[0].size
    sheet = numpy.zeros((h * 2, w * 2, 4), dtype=numpy.float32)
    for index, image in enumerate(images):
        pixels = numpy.array(image.pixels[:], dtype=numpy.float32).reshape(h, w, 4)
        row, col = 1 - index // 2, index % 2
        sheet[row * h:(row + 1) * h, col * w:(col + 1) * w] = pixels
    background = numpy.array([0.11, 0.1, 0.15, 1], dtype=numpy.float32)
    alpha = sheet[:, :, 3:4]
    sheet = sheet * alpha + background * (1 - alpha)
    sheet[:, :, 3] = 1
    out = bpy.data.images.new("Sheet", w * 2, h * 2, alpha=True)
    out.pixels = sheet.ravel()
    out.filepath_raw = os.path.join(OUT, "all.png")
    out.file_format = "PNG"
    out.save()


def lua_number(n):
    text = f"{n:.4f}".rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def write_luau(manifest):
    lines = [
        "-- The weapons' looks, made in Blender: GENERATED by",
        "-- art/blender/build_weapons.py from the models it builds. Edit the",
        "-- script and run it again; don't edit this file.",
        "--",
        "-- For each weapon: where the muzzle is (from the grip, in studs, the",
        "-- barrel along -Z), each role's colour and material, the box each",
        "-- role's mesh fills (to place the MeshParts Studio imports from",
        "-- art/export/weapons/<Weapon>.fbx), and the pieces the mesh was built",
        "-- from (blocks, cylinders and balls: the stand-in model before the",
        "-- meshes are imported, and the UI icons).",
        "export type Piece = { role: string, shape: string, size: Vector3, cframe: CFrame, corner: number?, standin: boolean? }",
        "export type Role = { color: Color3, material: Enum.Material, transparency: number }",
        "export type Mesh = { center: Vector3, size: Vector3, triangles: number }",
        "export type Art = { muzzle: Vector3, roles: { [string]: Role }, meshes: { [string]: Mesh }, pieces: { Piece } }",
        "",
        "local function v(x: number, y: number, z: number): Vector3",
        "\treturn Vector3.new(x, y, z)",
        "end",
        "",
        "local art: { [string]: Art } = {",
    ]
    for entry in manifest:
        lines.append(f"\t{entry['id']} = {{")
        m = entry["muzzle"]
        lines.append(f"\t\tmuzzle = v({', '.join(lua_number(x) for x in m)}),")
        lines.append("\t\troles = {")
        for role in sorted(entry["roles"]):
            spec = entry["roles"][role]
            r, g, b = spec["color"]
            lines.append(f"\t\t\t{role} = {{ color = Color3.fromRGB({r}, {g}, {b}), material = Enum.Material.{spec['material']}, transparency = {lua_number(spec['transparency'])} }},")
        lines.append("\t\t},")
        lines.append("\t\tmeshes = {")
        for role in sorted(entry["meshes"]):
            mesh = entry["meshes"][role]
            lines.append(f"\t\t\t{role} = {{ center = v({', '.join(lua_number(x) for x in mesh['center'])}), size = v({', '.join(lua_number(x) for x in mesh['size'])}), triangles = {mesh['triangles']} }},")
        lines.append("\t\t},")
        lines.append("\t\tpieces = {")
        for piece in entry["pieces"]:
            size = ", ".join(lua_number(x) for x in piece["size"])
            frame = ", ".join(lua_number(x) for x in piece["cframe"])
            corner = f", corner = {lua_number(piece['corner'])}" if piece.get("corner") else ""
            if piece.get("standin") is False:
                corner += ", standin = false"
            lines.append(f"\t\t\t{{ role = \"{piece['role']}\", shape = \"{piece['shape']}\", size = v({size}), cframe = CFrame.new({frame}){corner} }},")
        lines.append("\t\t},")
        lines.append("\t},")
    lines.append("}")
    lines.append("")
    lines.append("return art")
    path = os.path.join(kit.ROOT, "src", "shared", "Config", "WeaponArt.luau")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def main():
    manifest = [build(weapon) for weapon in WEAPONS]
    kit.write_json(os.path.join(OUT, "manifest.json"), manifest)
    contact_sheet([w["id"] for w in WEAPONS])
    write_luau(manifest)
    for entry in manifest:
        total = sum(m["triangles"] for m in entry["meshes"].values())
        print(f"{entry['id']}: {len(entry['pieces'])} pieces, {len(entry['meshes'])} meshes, {total} triangles")


if __name__ == "__main__":
    main()
