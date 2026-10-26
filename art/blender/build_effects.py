"""Renders the particle textures for Fart Wars' effects in Blender.

    python art/blender/build_effects.py
    blender --background --python art/blender/build_effects.py

Writes art/export/effects/<name>.png (256x256, white on transparent: the
game tints them per weapon and team through ParticleEmitter.Color):
    puff      a cartoon gas puff, outlined (muzzle puffs, Fart Dash)
    cloud     a soft, lumpy cloud (explosions, stink clouds)
    spark     a four-point star (hits, sparks, the Thunderclapper's flash)
    ring      a shockwave ring (explosions, Gas Pulse)
    droplet   a spray droplet (the Spritzer's mist)
and all.png, the five side by side.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import numpy  # noqa: E402

import kit  # noqa: E402

OUT = os.path.join(kit.EXPORT, "effects")
SIZE = 256


def soft_material(name, edge=1.5):
    """White emission that fades to transparent at the silhouette."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = (1, 1, 1, 1)
    transparent = nodes.new("ShaderNodeBsdfTransparent")
    weight = nodes.new("ShaderNodeLayerWeight")
    weight.inputs["Blend"].default_value = 0.5
    power = nodes.new("ShaderNodeMath")
    power.operation = "POWER"
    power.inputs[1].default_value = edge
    mix = nodes.new("ShaderNodeMixShader")
    links = mat.node_tree.links
    links.new(weight.outputs["Facing"], power.inputs[0])
    links.new(power.outputs["Value"], mix.inputs["Fac"])
    links.new(emit.outputs["Emission"], mix.inputs[1])
    links.new(transparent.outputs["BSDF"], mix.inputs[2])
    links.new(mix.outputs["Shader"], out.inputs["Surface"])
    return mat


def toon_material(name):
    """White, lit, for the outlined cartoon puff."""
    return kit.material(name, (1, 1, 1, 1), roughness=0.9)


def lit_soft_material(name, edge=0.8):
    """White and lit (so lumps show), fading to clear at the silhouette."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    diffuse = nodes.new("ShaderNodeBsdfDiffuse")
    diffuse.inputs["Color"].default_value = (1, 1, 1, 1)
    transparent = nodes.new("ShaderNodeBsdfTransparent")
    weight = nodes.new("ShaderNodeLayerWeight")
    weight.inputs["Blend"].default_value = 0.5
    power = nodes.new("ShaderNodeMath")
    power.operation = "POWER"
    power.inputs[1].default_value = edge
    mix = nodes.new("ShaderNodeMixShader")
    links = mat.node_tree.links
    links.new(weight.outputs["Facing"], power.inputs[0])
    links.new(power.outputs["Value"], mix.inputs["Fac"])
    links.new(diffuse.outputs["BSDF"], mix.inputs[1])
    links.new(transparent.outputs["BSDF"], mix.inputs[2])
    links.new(mix.outputs["Shader"], out.inputs["Surface"])
    return mat


def flat_material(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = (1, 1, 1, 1)
    mat.node_tree.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    return mat


def blobs(name, spheres, material, noise=0.0):
    """A lumpy blob from overlapping spheres (a metaball, made a mesh)."""
    meta = bpy.data.metaballs.new(name)
    meta.resolution = 0.04
    meta.render_resolution = 0.03
    obj = bpy.data.objects.new(name, meta)
    bpy.context.scene.collection.objects.link(obj)
    for x, y, z, r in spheres:
        element = meta.elements.new()
        element.co = (x, y, z)
        element.radius = r
    kit.active(obj)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.active_object
    if noise > 0:
        texture = bpy.data.textures.new(f"{name}Noise", "CLOUDS")
        texture.noise_scale = 0.35
        mod = obj.modifiers.new("Displace", "DISPLACE")
        mod.texture = texture
        mod.strength = noise
        kit.apply_modifiers(obj)
    kit.smooth(obj, 80)
    obj.data.materials.append(material)
    return obj


def star(name, points=4, outer=1.0, inner=0.28):
    verts = [(0, 0, 0)]
    for i in range(points * 2):
        angle = math.pi / 2 + i * math.pi / points
        radius = outer if i % 2 == 0 else inner
        verts.append((math.cos(angle) * radius, math.sin(angle) * radius, 0))
    faces = [(0, i, i % (points * 2) + 1) for i in range(1, points * 2 + 1)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def render(name, objects_scale, outline=False, light=False):
    scene = bpy.context.scene
    kit.render_setup(scene, (SIZE, SIZE), samples=32)
    if scene.world:
        scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.25 if light else 0.0
    if outline:
        kit.freestyle(scene, 3.0)
        scene.view_layers[0].freestyle_settings.linesets[0].linestyle.color = (0.42, 0.42, 0.46)
    kit.camera((0, 0, 10), (0, 0, 0), ortho_scale=objects_scale)
    if light:
        kit.light("Key", "AREA", (-3, 3, 6), 260, size=4)
        kit.light("Fill", "AREA", (3, -2, 5), 70, size=6)
    scene.render.filepath = os.path.join(OUT, f"{name}.png")
    bpy.ops.render.render(write_still=True)


def build(name):
    kit.reset()
    if name == "puff":
        blobs("Puff", [(0, 0, 0, 0.75), (-0.55, -0.15, 0, 0.6), (0.55, -0.2, 0, 0.6), (-0.2, 0.45, 0, 0.62), (0.32, 0.42, 0, 0.55)], toon_material("PuffMat"))
        render(name, 3.2, outline=True, light=True)
    elif name == "cloud":
        spheres = []
        for i in range(9):
            angle = i * 2 * math.pi / 9
            spheres.append((math.cos(angle) * 0.75, math.sin(angle) * 0.75, 0, 0.6 + 0.12 * (i % 3)))
        spheres.append((0, 0, 0, 1.0))
        blobs("Cloud", spheres, lit_soft_material("CloudMat", 0.7), noise=0.22)
        render(name, 4.4, light=True)
    elif name == "spark":
        obj = star("Spark")
        obj.data.materials.append(flat_material("SparkMat"))
        glow = star("Glow", outer=0.55, inner=0.45)
        glow.location.z = -0.01
        glow.data.materials.append(soft_material("GlowMat", 0.6))
        render(name, 2.3)
    elif name == "ring":
        bpy.ops.mesh.primitive_torus_add(major_radius=0.85, minor_radius=0.12, major_segments=64, minor_segments=16)
        obj = bpy.context.active_object
        kit.smooth(obj, 80)
        obj.data.materials.append(soft_material("RingMat", 0.45))
        render(name, 2.2)
    elif name == "droplet":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=0.45)
        obj = bpy.context.active_object
        for vertex in obj.data.vertices:
            # A teardrop: pull the top into a point.
            if vertex.co.y > 0:
                vertex.co.x *= 1 - vertex.co.y * 1.6
                vertex.co.y *= 1.9
        kit.smooth(obj, 80)
        obj.data.materials.append(toon_material("DropMat"))
        render(name, 2.2, outline=True, light=True)


def sheet(names):
    images = [bpy.data.images.load(os.path.join(OUT, f"{n}.png")) for n in names]
    w, h = images[0].size
    grid = numpy.zeros((h, w * len(images), 4), dtype=numpy.float32)
    for index, image in enumerate(images):
        grid[:, index * w:(index + 1) * w] = numpy.array(image.pixels[:], dtype=numpy.float32).reshape(h, w, 4)
    tint = numpy.array([0.55, 0.85, 0.3, 1], dtype=numpy.float32)
    background = numpy.array([0.11, 0.1, 0.15, 1], dtype=numpy.float32)
    alpha = grid[:, :, 3:4]
    grid = (grid * tint) * alpha + background * (1 - alpha)
    grid[:, :, 3] = 1
    out = bpy.data.images.new("Sheet", w * len(images), h, alpha=True)
    out.pixels = grid.ravel()
    out.filepath_raw = os.path.join(OUT, "all.png")
    out.file_format = "PNG"
    out.save()


def main():
    os.makedirs(OUT, exist_ok=True)
    names = ["puff", "cloud", "spark", "ring", "droplet"]
    for name in names:
        build(name)
    sheet(names)
    print("effects:", ", ".join(names))


if __name__ == "__main__":
    main()
