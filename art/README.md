# Fart Wars art (Blender)

The four weapons, their hotbar icons, the effect textures and the map's
props are made in Blender, from scripts in `art/blender`. The scripts are
the source: change a weapon or a prop there and run them again, and the
game's copy of the measurements (`src/shared/Config/WeaponArt.luau`,
`PropArt.luau`) is regenerated to match.

![The four weapons](export/weapons/all.png)

![Porcelain Plaza, dressed with the props](export/props/plaza.png)

| Folder | What's in it |
| --- | --- |
| `art/blender/build_weapons.py` | models the Gas Blaster, Spritzer, Thunderclapper and Stink Lobber |
| `art/blender/build_effects.py` | the particle textures: puff, cloud, spark, ring, droplet |
| `art/blender/build_props.py` | the map's props: the throne's toilet tank, lid, bowl and seat; the bean can and its label; the gas barrel and its band; the crate; the cover wall; Bean Rain's bean |
| `art/blender/kit.py` | shared helpers (axes, materials, rendering) |
| `art/export/weapons/<Weapon>.fbx` | the model for Roblox: one mesh per part of the gun (Body, Metal, Grip, Trim, Glass, Gas, and the Stink Lobber's Bomb) |
| `art/export/weapons/<Weapon>.blend` | the same model as a Blender scene, to edit by hand |
| `art/export/weapons/<Weapon>.png`, `all.png` | preview renders |
| `art/export/icons/<Weapon>.png` | hotbar icons, 512×512 |
| `art/export/effects/<name>.png` | particle textures, white (the game tints them) |
| `art/export/weapons/manifest.json` | every part's size and place, which the game reads (through `WeaponArt.luau`) |
| `art/export/props/<Prop>.fbx` | each prop for Roblox: one mesh, the exact size of the map part it dresses |
| `art/export/props/Props.blend`, `<Prop>.png`, `all.png`, `plaza.png` | every prop in one Blender scene; previews; Porcelain Plaza laid out as in the map |
| `art/export/props/manifest.json` | each prop's size and the part it was modelled on (`PropArt.luau`) |

## What the game does with it

The held gun is always built from the Blender model's measurements
(`WeaponModel`):

- **Before you import anything**, it's built from the same blocks,
  cylinders and balls the Blender model is made of, in the same colours:
  the shape is right, without the bevels and round edges.
- **Once the meshes are imported** (below), it's made of the real Blender
  meshes, each sized and placed from the model's measurements, so the
  import's scale or position doesn't matter.

The animations are done in code, so there's nothing to upload for them
(`WeaponFx`, `WeaponFxController`): the gun comes up when it's equipped,
kicks back and up on every shot and settles, the Stink Lobber's kick is
its throw, the Thunderclapper flashes, and the gas tank glows. Every
player sees everyone's. Reduce motion keeps a little recoil and none of
the rest.

The hotbar shows each weapon's 3D model until its icon is uploaded, and
the locker's weapon cards turn the model slowly.

The map's props dress the parts the map is built from (`MapDressing`,
`Config/MapArt.luau` says which prop goes on which part):

- **Before you import anything**, the map is its plain blocks and
  cylinders, as before.
- **Once a prop is imported**, every part it dresses gets the mesh drawn
  exactly over it, in the part's own colour and material. The part stays
  where it is, invisible, as the hitbox: it's still what players bump
  into, what shots hit and what stops a blast, and the mesh can't be hit,
  touched or collided with. So cover, sightlines and barrels play exactly
  the same with or without the art.
- The throne's two toilets face their own bowls, the Gas Gutter's sideways
  toilet turns to face its bowl, and a gas barrel's mesh goes and comes
  back with the barrel. Bean Rain's beans use the bean mesh.

## Import the meshes into Studio (once)

1. Open the place in Studio, with Rojo connected.
2. **Model** tab (or File) → **Import 3D**. Pick
   `art/export/weapons/GasBlaster.fbx`.
3. In the importer, keep the default orientation (forward **-Z / Front**,
   up **+Y / Top**) and leave **merge meshes off**, so each part of the gun
   stays its own MeshPart. Import.
4. A model named `GasBlaster` appears in the Workspace with MeshParts named
   Body, Metal, Grip, Trim, Glass and Gas. Drag it into
   **ReplicatedStorage → Assets → Weapons**. Keep its name.
5. Do the same for `Spritzer.fbx`, `Thunderclapper.fbx` and
   `StinkLobber.fbx`.
6. Play, and chat `/fw selftest`: **Weapon meshes: all 4 imported**. If it
   says a part is "the wrong way round", delete that weapon's model and
   import it again with the orientation above.

Rojo leaves `ReplicatedStorage.Assets` alone, so the imports stay when you
sync. Save the place in Studio to keep them. To keep them in Git too,
right-click **Weapons** → **Save to File** → `art/export/Weapons.rbxm`.

## Import the map props (once)

1. **Import 3D** each FBX in `art/export/props` (ToiletTank, TankLid,
   ToiletBowl, ToiletSeat, BeanCan, BeanLabel, GasBarrel, BarrelBand,
   Crate, CoverWall, Bean), with the same orientation as the weapons
   (forward **-Z**, up **+Y**).
2. Drag each one into **ReplicatedStorage → Assets → Props** and keep its
   name. A MeshPart on its own or the Model the importer makes around it
   are both fine.
3. Optional, for performance: select them all and set
   **CollisionFidelity** to **Box** (the meshes never collide; the parts
   under them do).
4. Play, and `/fw selftest`: **Map props: all 11 imported**. A prop that's
   "the wrong way round" is left off the map (its parts show as before);
   import it again.

Save the place to keep them; to keep them in Git too, right-click
**Props** → **Save to File** → `art/export/Props.rbxm`.

## Upload the images (once)

1. **View** → **Asset Manager** → **Bulk Import**. Pick the four PNGs in
   `art/export/icons` and the five in `art/export/effects` (not `all.png`).
2. Right-click each uploaded image → **Copy Asset ID**, and paste it into
   `src/shared/Config/ArtAssets.luau` (`icons` for the four weapons,
   `effects` for puff, cloud, spark, ring and droplet). Numbers on their
   own are fine.
3. `/fw selftest`: **Art images: all 9 uploaded**.

Until then the hotbar shows the 3D models, and the particles use Roblox's
own textures.

## Changing the art

You need Blender 4.2 or newer, or just its Python module:

```
pip install bpy==5.2.3          # Python 3.13
python art/blender/build_weapons.py
python art/blender/build_effects.py
python art/blender/build_props.py
```

or, with Blender installed:

```
blender --background --python art/blender/build_weapons.py
blender --background --python art/blender/build_effects.py
blender --background --python art/blender/build_props.py
```

Each weapon is a short function in `build_weapons.py` (`gas_blaster`,
`spritzer`, ...), made of `box`, `cyl`, `ball` and `ring` calls with
sizes in studs. The grip is at the origin; the barrel points along
Blender's +Y and the top is +Z. The colours are at the top of the file.
After a change, run the specs (`python3 scripts/run_specs.py`), check the
renders, and import the changed FBX into Studio again (replace the old
model in Assets → Weapons).

Each prop is a function in `build_props.py` (`toilet_tank`, `bean_can`,
...), modelled at the exact size of the map part named in `PROPS`, so it
isn't stretched in the game. Cylinder props (bowl, seat, can, label,
barrel, band) are turned shapes around Blender's X, the axis a Roblox
cylinder part runs along; the map stands them up. A prop whose front
matters faces Blender +Y. The spec `MapArt` checks every prop still fits
its part. To dress another part, add it to `Config/MapArt.luau`.
