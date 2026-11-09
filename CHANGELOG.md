# Changelog

## Unreleased: smoother play

- Your aim stays where you put it. A shot's camera kick now settles back;
  before, every kick stayed, so a held Spritzer or a run of shots climbed
  off target (one Thunderclapper shot left the view about 11° higher), and
  more at high frame rates.
- Shots you see fire count. A late or lost packet's shots may arrive
  bunched up (a quarter of a second of slack, up from 0.05), so the shot
  after a network hiccup isn't thrown away; over time nobody fires faster
  than the gun.
- Tap firing works: a click up to 0.2 s before the gun is ready fires as
  soon as it is. Held, automatic fire keeps its rate (the Spritzer fired
  8.6 a second at 60 fps, not 10).
- After you're gassed out, the screen counts down to your next life
  ("BACK IN 3, 2, 1"), and the crosshair, hotbar and gas bar step aside
  until then. A trigger held through it no longer fires the moment you're
  back (which ended your spawn protection).
- Every life starts facing the way out: the spawn pads face the spawn
  room's nearer back door, not its solid front wall.
- The results are for reading: from the buzzer to the next round nobody
  fights and no gas lands, not even from a bomb or barrel that goes off
  after the buzzer. Players could gas each other under the results card
  (and be paid for it), and a countdown could carry into the next round.
- Bots fill in for the people playing, not everyone in the server:
  someone on the loading screen, in the lobby, in the practice yard or
  away no longer takes a bot from the people in a match (four in the
  server with one playing meant no bots at all). A newcomer takes a bot's
  place when they press PLAY.
- Bots' shots set off barrels like anyone's, with the blast and any chain
  credited to the bot (Barrel Buster too).
- The scoreboard keeps a bot listed while it waits to respawn, as it does
  a player, and keeps up while you hold Tab.
- The AFK warning shows over every menu and the results, so it's seen
  before anyone is moved to spectators.
- Alt-Tab no longer leaves the mouse unlocked in a match.
- Choose a Team explains locked teams only when one is locked.
- Long sessions stay smooth: old bodies are cleared on the server and on
  every client (each respawn stayed in memory, gun and all), a body's gas
  warning stops pulsing with it, and the server keeps a minute of shot
  history, not all of it.

## 0.14.0: a practice yard, bots with every gun, launch pads, daily challenges and round awards

- New players warm up first: a new profile's first PLAY goes to the
  practice yard, a yard of your own, for about half a minute. Gas the
  dummies till they pop, Fart Dash down a lane, then blow up a barrel and
  watch it set off the dummies round it, and then pick a team. SKIP (or
  Enter) leaves any time, and the PRACTICE tile on the home screen and
  Settings replay it. Nothing in the yard pays or counts toward anything,
  and the compass stays off there.
- Bots fight with the whole arsenal. Each life picks a Gas Blaster,
  Spritzer, Thunderclapper or Stink Lobber (teammates mix it up) and plays
  it at its range: Spritzer bots rush in, Thunderclapper bots hang back on
  the long lines, Stink Lobber bots lob over cover. They Fart Dash in and
  out, vent with Recovery Burst and use Gas Pulse up close, on the same
  cooldowns as players. The gun in a bot's hands, its shots and its sound
  are the gun it really fires.
- Bots never lock a team. Alone with bots, pick either side: you take a
  bot's place and a bot crosses over to keep the teams level, even on a
  team of ten bots. The team cards say how many on each side are bots, and
  the lock and SWITCH TEAM count only real players, so the teams stay fair
  between people. Two players in a quiet server are now split, one on each
  side with bots, instead of being put together against the bots.
- Launch pads: four giant whoopee cushions on each half throw you along a
  fixed arc, up the side lanes or into Porcelain Plaza, with a fart, a puff
  and a green cloud. The run from the spawn to the plaza drops from about
  16 seconds to about 11.5. A launch keeps your spawn protection, like Fart
  Dash, and the cheat checks allow for the flight. Bots use them too. The
  sound is Fart Dash's, pitched down, until a whoopee cushion sound is
  picked.
- A compass along the top shows the directions, the lanes and the plaza.
  Teammates too far away to pick out get a marker, and one fighting or
  about to blow up off the screen gets an arrow at its edge. Z (or the
  middle mouse button) pings the spot under your crosshair for your team
  only, one every 1.2 seconds at most.
- Your hits show the gas they put in where they land ("+20%", bigger and
  gold for a headshot); only you see them. A chain reaction you set off
  counts up above the crosshair ("CHAIN x2!", "CHAIN x3!") with a sting and
  a small camera kick, and players near someone else's chain see a smaller
  line saying whose it is. Every player, bot and barrel the chain sets off
  adds one. Reduce motion and Reduced effects tone them down.
- Award cards at the end of each round: Top Fragger (most eliminations),
  Chain Master (the biggest chain reaction), Barrel Buster (most barrels
  set off) and Team Player (most assists), with the winner's headshot,
  name, number and a line to match. Bots can win them, with a robot for a
  face. Nobody wins one with 0, and someone who left before the end can't
  win.
- Daily challenges: three a day on the DAILY screen (play or win rounds,
  play for 15 minutes, Fart Dash, blow up barrels, start a barrel chain
  reaction), different for each player and new at 00:00 UTC. Each pays 40
  coins and 75 XP the moment it's done, with nothing to claim, so a reward
  never runs out unclaimed at midnight. Progress carries over between
  servers that day, and one player alone with bots can do them all;
  nothing a bot does counts. Why the XP: in the economy model a casual
  player's longest wait holding a gun's coins but not its level drops from
  2.6 hours to 10 minutes, and an average player reaches level 50 on day
  40 (was 47). `docs/economy.md` has the numbers.
- The home screen's TOP button is a weekly leaderboard: this week's top 10
  for eliminations and for round wins, with avatars, your own rank
  underneath and a countdown to the reset every Monday 00:00 UTC. Only
  players count, never bots or eliminations of or by bots. The M menu's
  LEADERBOARD opens it too. If the boards can't be reached, it says it's
  taking a nap and the game carries on.
- Badges: Beta Tester, with the OG Beta Boom explosion that only beta
  players get, plus First Gassing, Chain Reaction, Level 10 Tooter, Level
  25 Stink Veteran and Level 50 Alpha Farter. You earn them in the game,
  and Roblox awards them once they exist on the experience (retried until
  then). After your first round win the game asks once whether you'd like
  to favorite it, never mid-fight, and the Players screen has an INVITE
  button.
- Gas Control is ready for the big map (mode rotation is still off): the
  plaza zone is the circle on the floor around the throne. A team alone in
  it takes it in 6 seconds (4 with two players, 3 with three or more), then
  scores a point a second while it has the plaza to itself, and keeps it
  through a contest. A bar shows the capture, a 🚽 PLAZA marker shows the
  zone through walls, the results say it was Gas Control, and bots spread
  out round the throne instead of walking into it.
- Your settings are saved: everything on the Settings page comes back the
  next time you play (it used to reset every visit). New in Settings: field
  of view (60 to 110, first and third person), mouse sensitivity (0.2x to
  3x, on top of Roblox's own camera sensitivity), and the crosshair's size
  and colour.
- FEEDBACK in the M menu sends a bug report, an idea or anything else (up
  to 300 characters) to the developer, with the game version, your ping and
  frame rate, and never your name. One every two minutes, five a day.
- A server update no longer kicks you: when the servers restart, you see
  "FART WARS JUST GOT AN UPDATE!" and move to a fresh server once your
  progress is saved.
- Fart Dash no longer flags you for going through a wall when you dash
  round a corner, along a wall, off a ledge or on a laggy connection; a
  dash through a wall is still put back. The chat is Roblox's current one
  (it was the old, legacy chat), and it no longer covers the LOADOUT button
  or your weapon list: the home screen's buttons sit below it, it moves to
  the bottom right while the Loadout is open, and it steps out of the way
  (hidden until you close it) when it would cover the SHOP, LEVELS or
  SETTINGS window.
- Fixes: HUD SIZE changes now show at once (they only did on your next
  visit); at a bigger HUD size the hotbar no longer covers the gas and
  dash bars, and the home screen's tiles no longer slide under your coins
  (they shrink a little to fit if they must); the kill feed moved below the
  SPIN and DAILY buttons, which were hiding its newest lines; the Settings
  list stays where you scrolled it when you change something; and the
  Choose a Team hint isn't cut off or covered by AUTO.
- Specs: `TeamPick`, `BotArsenal`, `LaunchPads`, `Compass`, `CompassOff`,
  `GasNumbers`, `ChainCallouts`, `Awards`, `Challenges`, `Leaderboard`,
  `Badges`, `Settings`, `Feedback`, `SoftShutdown`, `DashCheck`,
  `ChatSpace`, `Practice` and `PracticeOff` are new (66 in all, with
  0.13.0's `Gift`).

## 0.13.0: a bigger battlefield, mouse aim, sound in the world, a range for every gun

- Brainrot Battlefield is three times bigger (480 × 480 studs), with room
  for 20. The low cover stays low: the plaza and alley walls (5 studs;
  the alley's was 6) and the crates (6) keep about an avatar's height
  while they spread out, so you hide right behind them, shoot past their
  ends, jump to fire over them and lob over them. A wide stack of crates
  shows as a grid of ordinary crates rather than one squashed one. The
  throne, the bean
  cans and the Gutter's toilet grew with the map and hide you whole.
- Lane gates: each lane's entrance, on both halves, has a gate up on the
  walls with the lane's name on a lit sign that reads from both ends, and
  a landmark on top (a giant bean can, a toilet roll, a gas vent puffing
  green), so you know where you are on a field this big. They're above
  everyone's heads and never stop a shot, a player or the camera.
- Imported meshes now face the right way. The guns, the map's props and the
  shot effects were each a half turn round from how they were made, which
  hid the barrels inside the guns and left pieces floating.
- A life starts level, facing the middle of the map: not looking down at the
  top of your head, and not (for the Stinkers) at your own back wall.
- In a match the mouse is locked to the crosshair in first and third
  person, and third person sits over your right shoulder. Left Alt frees
  the mouse (again to lock it); every screen with buttons frees it while
  it's open. Settings → 3rd person mouse lock off gives a free cursor in
  third person.
- Sound comes from where it happens and fades with distance: other
  players' shots (you didn't hear them before), explosions, barrels,
  stink bombs, abilities, dashes and emotes. Your own shots, hits and
  warnings sound the same wherever you look. Every sound has its own
  volume and a little pitch variety, so repeats don't sound identical.
  Your own stink bomb is no longer heard twice, and an emote no longer
  also makes the Recovery Burst's vent sound (that sound means someone
  vented).
- Hit markers pop at the crosshair: white for a body hit; bigger and gold,
  with a higher hit sound, for a headshot; bigger still, orange and with a
  ring for the hit that sets someone off; small, grey and silent when the
  hit did nothing (a teammate, spawn protection, or they're already going
  off).
  Reduce motion and Reduced effects tone it down.
- Bots fill a quiet server to four: with one player in it there are three
  bots, with two there are two, with three there's one. They keep the
  teams level, a player who joins takes a bot's place, and a bot changes
  sides when the teams get uneven. Bots are named [BOT], carry the Gas
  Blaster and play at half difficulty: they take a moment to react and
  miss more against someone on the move. Kills of and by bots score in
  Team Elimination and bots hold the zone in Gas Control, but killing one
  pays no coins or XP, so there's nothing to farm.
- Joining shows the game's own loading screen instead of Roblox's: the
  FART WARS logo over a dark purple background, a tip every few seconds,
  a yellow progress bar and what it's waiting for (the battlefield, your
  profile, the lobby). A slow server can't keep you there: each step
  gives up after 15 seconds.
- The lobby has big buttons over the blurred battlefield: LOADOUT, SHOP
  and LEVELS down the left; DAILY, SPIN, SEASON (while one is on),
  PLAYERS, TOP and SETTINGS down the right; your coins top right (+ opens
  the coin packs), your level and XP bottom left, and PLAY in the middle
  (or press Space or F). Red badges count what's waiting: things you can
  buy on SHOP (today's cosmetics too), new abilities on LOADOUT, a daily
  reward and free spins.
- The lobby's TODAY IN THE SHOP panel leads with a card of up to three
  of today's cosmetics you don't own and the time left (click it for the
  daily shop), then the Starter Pack, your next gun, the daily reward,
  free spins and the season, as they apply, two at a time with arrows
  for more.
- The shop is one scrolling page, with a rail beside it that jumps to
  each part: FEATURED, WEAPONS, DAILY and COINS. Each gun's card shows
  its gas, range and fire rate as bars, and spending coins asks
  "Buy it?" first, with what you'll have left. DAILY sells five
  cosmetics a day for 200 to 1,800 coins each: the same in every server,
  new at midnight UTC, with a countdown. Click one to preview it on your
  own gun, bought or not; if you can't buy it yet, it says why.
- Any of today's cosmetics can be a gift: GIFT on its card lists
  everyone else in the server (friends first, and who has it already),
  and your coins buy it for them to keep. They get a banner saying who
  it's from. A gift needs both players' progress to be saving, and
  Roblox to allow both accounts to trade items bought with coins.
- LOADOUT is its own screen (from the lobby, the M menu or the shop's
  tabs): your guns with their keys, the picked one's gas, range and fire
  rate against the shop's best, Fart Dash, your pick of Q ability, and
  slots for your tracer, Fart Dash trail and boom (the blast when someone
  you eliminate goes off). Your emotes sit in a ring around E: pick the
  one E plays, and an empty spot takes you to the daily shop.
- Hold E in a match for a wheel of every emote you own; let go on one to
  play it (in the middle, nothing plays). Your equipped emote stays as it
  is, and a tap of E still plays it, as you let go.
- Every gun has its own range, and long shots do less: full gas out to a
  gun's effective range, then less, down to half at its full range, and
  nothing past it (a headshot always stays the better hit; the server
  measures the distance). Spritzer full gas to 45 studs, reach 90 (was
  180); Gas Blaster 120 and 260 (was 480); Thunderclapper 240 and 420 (was
  660); Stink Lobber thrown up to 150 (was 270). Why: on the big map every
  gun reached nearly everywhere, so the Gas Blaster did everyone's job.
  Now the Spritzer wins up close, the Gas Blaster at middle distances, the
  Thunderclapper down the long sightlines and the Stink Lobber over
  cover. The Spritzer hits harder to back that up: 9% a hit, 11% to the
  head (was 7% and 9%), so up close it now eliminates faster than the Gas
  Blaster (1.1 s against 1.2 s). The Lobber throws slower and falls faster: aim higher to throw
  farther (farthest at about 45 degrees), a steep throw clears the throne,
  and no throw bursts in the air any more (steep ones used to).
- Levels come faster in the middle, and the late guns cost more: the
  Thunderclapper is 3,000 coins (was 1,200) and the Stink Lobber 7,000
  (was 2,500). Every level costs less XP than before (61,640 to level 50,
  was 115,240), most of all where the guns unlock. Why: levels came so
  slowly that a player had a gun's coins many hours before its level (an
  hour a day, the Stink Lobber's level took until day 19) and finished
  with thousands of coins and nothing to buy. Now coins and levels arrive
  together: at an hour a day, all three guns in about a week, and level
  50 still takes weeks. If you own a gun, you keep it. Your level is kept;
  if you already hold more XP than your next level now costs, you get
  those levels when you join.
- The map's props, walls and floors, the guns and the shot effects are the
  Blender models everywhere: imported into the game
  (`art/export/mesh-assets.json` lists them), so the server dresses the
  map and no player's device has to build them.
- The free spin is a prize wheel: it winds up, spins with a tick past the
  pointer and lands on what you won, with confetti. Every slice shows its
  chance. Your coins and the "+coins" line wait until it lands, so the
  prize stays a surprise. The 1% slice is the Lucky Lime tracer; win it
  again and you get 250 coins instead, and the wheel tells you why. New
  players start with one free spin.
- Clicking on a window no longer clicks what's behind it. A click on the
  free spin's message could press PLAY under it, one beside a "Buy it?"
  card could press the shop's tabs or another item's button, and the
  home screen's buttons still worked through the shop's dimmed backdrop.
  PLAY also closes the free spin now, as it does the daily reward.
- Specs: `Audio`, `HitFeedback` and `Balance` are new (38 in all); `Map`
  checks low cover and the gates; `Soak` now plays the same game every
  run.

## 0.12.0: better guns, shots and animation, with nothing to import

- The guns and shot effects are the Blender meshes in game with nothing
  to import: the art scripts pack each mesh into `src/shared/MeshData`,
  and each client builds them (`MeshBuilder`, Roblox's EditableMesh) and
  dresses every held gun in them (`WeaponSkin`), the hotbar and locker
  too. The server keeps the stand-in (a mesh built there wouldn't reach
  players), and it shows until the meshes are built or if they can't be
  (in a published game: Experience Settings → Security → Allow Mesh /
  Image APIs, which `/fw selftest` checks). Imports still win if present.
- The Gas Blaster remodelled again: a rounder body, glowing vent gills on
  both sides, a glowing ring and a ready light at the back, bolts, and
  its pump and gauge needle as parts of their own. The Spritzer's pump
  and the Stink Lobber's bomb and fuse are parts of their own too
  (`WeaponArt` meshes now have a role and may be `moving`).
- Animation (`WeaponFx`, `WeaponFxController`): recoil on springs (back,
  up and a little to a side, swinging past rest and home), an equip that
  overshoots and twirls the light guns, an idle sway and a walking bob;
  the pumps pump on every shot, the gauge's needle drops with the
  pressure and climbs back, the Stink Lobber's bomb goes with the throw
  and grows back; the gas flashes on every shot and a hot barrel smokes.
- Shots: every gun's muzzle flashes light and throws a shock ring (a new
  Blender mesh); the bolt lights the walls it passes and leaves a trail
  of smoke (droplets for the Spritzer); where it hits, a flash of light
  and a ring with the splat; a player you hit flashes white; your own
  shots kick the camera a little with every gun. Reduced effects leave
  all of it out but the bolt.
- Specs: `WeaponArt` checks the packed meshes (sizes, facing), building
  and dressing, the moving parts, the springs, twirl, sway and bob, and
  the new effects.

## 0.11.0: the Gas Blaster remodelled, and new shooting graphics

- The Gas Blaster, the starter gun, is remodelled in Blender: a gas
  canister on top with a valve and a hose down to the barrel, a pressure
  gauge on the side, a ribbed barrel with a pump grip under it, a horn
  that glows with gas, finger ridges and a pommel on the grip, and
  building-brick studs on the receiver. New icon and previews.
- Shots, made in Blender (`art/blender/build_shots.py`): a cartoon muzzle
  burst, the gas bolt a shot streaks as, and a splat for where it hits;
  imported into `ReplicatedStorage.Assets.Effects`, with glowing parts
  standing in until then.
- `ShotFx`: each hitscan shot's bolt, a hot core in a softer glow, now
  comes from the gun's muzzle (it came from the head) and flies to where
  the shot stopped, then slides into its target; your own shots stop at
  the first wall in the way instead of drawing through it. The muzzle
  bursts, and a splat sticks to the wall or floor a shot hits (never a
  player) and fades. Sizes per weapon (`WeaponFx`): thin and quick for
  the Spritzer, fat for the Thunderclapper. Fixed pools; reduced effects
  and reduce motion keep only the bolt.
- `/fw selftest` reports the shot effects. Specs: `WeaponArt` covers the
  bolt, burst, splat, reduced effects and the imported meshes.

## 0.10.0: a building-brick look

- Brainrot Battlefield is repainted in bright toy colours (grass-green
  ground, salmon walls with grassy tops, a lavender plaza, peach and
  green side lanes, orange crates) under a brighter midday sky
  (`MapConfig`'s theme, now with `brightness`).
- Studded plastic, like building bricks: the map's plastic blocks get
  Roblox's stud surface on top (`MapKit.studded`; not the cylinders), and
  the Blender meshes have real studs one stud apart on the tops of the
  walls, the wall-top plates (which replace the neon rails on the
  boundary and spawn rooms), the cover walls and the crates.
- The ground and the side lanes are no longer dressed with meshes: as
  studded baseplates they look the part for nothing. The Flagstones and
  GroundTile meshes are gone (17 to import now). The plaza keeps its
  smooth tiles.
- `MapArt` spec checks the studs and the baseplates.

## 0.9.0: the map's walls and floors, made in Blender

- Walls, trims and floors made in Blender (`art/blender/build_props.py`)
  as modules: panelled wall sections in two heights (dividers and spawn
  rooms; the 24-stud boundary) between posts, with mouldings and bands, a
  rounded neon trim, Porcelain Plaza's square tiles, the side lanes' flagstones, the
  ground (gently dipped), see-through spawn floors and round spawn pads.
- `MapDressing` repeats a module along its part (a wall's sections run
  along it; floors in a grid), as many as fit, each stretched a little to
  come out even, so no long wall is one stretched mesh. The parts stay as
  the invisible hitboxes as before; the spawn pads still spawn.
- Every Blender mesh for the map now has UVs measured in studs, so
  Roblox's material textures land on the meshes evenly and run on across
  modules (props re-exported).
- Renders of the whole dressed map, Porcelain Plaza and a spawn room,
  made from the map as the game builds it (`scripts/map_layout.py` dumps
  the layout through the spec harness).
- Brainrot Battlefield's end walls and trims, and the spawn rooms' front
  walls, now stop against the side walls instead of overlapping them at
  the corners, where the faces flickered (with or without the art).
  Nothing moves for play: the side walls fill the corners.
- `MapArt` spec covers the modules (placement, direction, stretch, the
  spawn pads). Docs: [`art/README.md`](art/README.md), Studio sign-off
  section 9.

## 0.8.0: the map's props, made in Blender

- The map's props are modelled in Blender (`art/blender/build_props.py`):
  the throne's toilet tank (with its flush lever), lid, bowl and seat; the
  bean can (rims, ridges, a ring pull) and its label; the gas barrel
  (rolling hoops, a bung) and its glowing band; the crate (posts, rails,
  braces); the capped cover wall; and Bean Rain's bean. Each is modelled
  at the exact size of the map part it dresses and exported as FBX, with
  a Blender scene, previews and a render of Porcelain Plaza dressed.
- `MapDressing`: once a prop is imported into
  `ReplicatedStorage.Assets.Props`, every part `MapArt` names gets the
  mesh drawn over it in the part's colour and material. The part stays as
  the invisible hitbox, so collisions, shots, blasts and sightlines are
  unchanged; the mesh is never in the way. The throne's mirrored toilet
  turns round to face its bowl and the Gas Gutter's toilet turns to face
  its bowl. Until a prop is imported, its parts show as before.
- Gas barrels keep their art through the blast and the respawn (the
  hitbox stays invisible and solid, the mesh never solid). Bean Rain's
  beans use the bean mesh.
- `/fw selftest` reports the props (a sideways import is left out and
  named). Docs: [`art/README.md`](art/README.md), Studio sign-off section
  9. New spec: `MapArt`.

## 0.7.0: the weapons, made in Blender

- The four weapons are modelled in Blender (`art/blender/build_weapons.py`):
  a chunky cartoon look with bevelled bodies, glass gas tanks, barrels,
  muzzles and grips, in each weapon's colours. Exported as FBX for Studio's
  3D importer (one MeshPart per part of the gun), with Blender scenes,
  preview renders and 512px hotbar icons.
- Particle textures made in Blender (`build_effects.py`): puff, cloud,
  spark, shockwave ring and droplet.
- `WeaponModel`: the held gun is built from the Blender model's
  measurements: the imported meshes once they're in
  `ReplicatedStorage.Assets.Weapons`, or until then the same pieces as
  plain parts. A mesh imported the wrong way round falls back and
  `/fw selftest` says so.
- Animations (`WeaponFx`, `WeaponFxController`), on every client for every
  player's gun: the gun comes up when equipped, kicks back and up on each
  shot and settles (the Stink Lobber's kick is its throw), the
  Thunderclapper flashes and kicks its shooter's camera, and the gas tank
  glows. Muzzle puffs (the Spritzer's droplets), impact puffs and sparks,
  explosion smoke and shockwave rings. Reduce motion and reduced effects
  are respected, and particles are capped each frame.
- The hotbar shows each weapon's 3D model (or its icon once uploaded); the
  locker's weapon cards turn the model slowly.
- `ArtAssets` for the uploaded image IDs; `/fw selftest` reports the art.
- Docs: [`art/README.md`](art/README.md). New spec: `WeaponArt`.

## 0.6.0: Phase 6, part 4: accessibility, friends and operations

- Settings: REDUCE MOTION (still spectator shots, a steady gas outline,
  softer explosion bursts), HUD SIZE (80% to 125%; every panel scales
  around its own corner) and TEAM SYMBOLS (▲ Stinkers, ● Sharters: on the
  score boxes and team cards, in the kill feed and Players screen, and
  over teammates' heads). Settings scroll now.
- The team cards say where your friends are (`Friends_<team>`); AUTO
  prefers their team within the balance rules.
- Docs: [`docs/operations.md`](docs/operations.md) (the week, the
  telemetry audit, patch notes, balance changes, technical debt,
  rollback, the expansion gate, monetization checks) and the Phase 6
  checklist.
- New spec: `Access`.

## 0.6.0: Phase 6, part 3: seasons, Bean Rain and booms (all off)

- Seasons, behind `FeatureFlags.SEASONS`: Season 1 (2 November to 28
  December 2026), 20 free tiers of coins with a cosmetic every five
  (Spark Boom, Sludge Trail, Toxic Boom, Brainrot Gold) and the Season 1
  badge at the top. Season XP is 20% of all XP plus 500 for each of three
  weekly challenges (eliminations, assists, dashes, barrels, minutes,
  streaks, and plaza time when Gas Control rotates). The Season screen
  (🏆 SEASON top right while a season is on) shows the tier, the next
  rewards, this week's challenges and the real time left.
- Bean Rain, behind `FeatureFlags.EVENTS`: half of rounds, a 5-second
  warning banner, then 20 seconds of beans on the lanes, each shown first
  as a ring. A bean pays 3 coins (8 an event) and refills your Fart Dash.
  It never lands in a spawn room, hurts nobody and tops out at 12 parts.
- Booms: a new cosmetic slot that colours the explosions of players you
  eliminate. The cosmetics grid scrolls.
- Signals for challenges: `DashService.Dashed`, `BarrelService.Exploded`,
  `ZoneService.Held`, `EconomyService.XPGained`; `DashService.refill`.
- New specs: `Season`, `Events`.

## 0.6.0: Phase 6, part 2: prestige (off) and the long-term economy

- Prestige, cosmetic only, behind `FeatureFlags.PRESTIGE` (off): at level
  50, from the home screen, an exact preview (level, XP and coins before
  and after, the weapons that go, what stays) and two presses to confirm.
  It resets level, XP, coin-bought weapons and coins, but keeps every
  cosmetic, lifetime XP and stats, badges, mastery, abilities, passes and
  unspent store coins. Each rank gives a badge (and a cosmetic at ranks 1,
  3 and 5: Prestige Flame, Prestige Trail, Crown Toot) and a tag (P1, P2...)
  on the level bar and scoreboard. Saved before it's confirmed; a failed
  save puts everything back. No power bonus.
- `PurchasedCoins` in the profile (store coins since the last prestige);
  the `PrestigeRequest` remote.
- Veteran advantage: eliminations and deaths by level band
  (`fairness.kills.level50`, `.prestige`...).
- Docs: the roadmap's prestige and long-term economy sections.
- New spec: `Prestige`.

## 0.6.0: Phase 6, part 1: Gas Control and the map kit

- A second mode, **Gas Control**: a team alone in Porcelain Plaza scores a
  point a second; a contested plaza scores nothing; eliminations clear the
  plaza but don't score. Holders earn 2 coins and 5 XP every 10 seconds
  (15 times a round). The HUD names the mode and says who holds the
  plaza in words and colour; a floor ring shows it on the map.
- Mode rotation behind `FeatureFlags.MODE_ROTATION` (off): rounds take
  turns through `GameConfig.MODE_ROTATION` once six players are on teams;
  smaller servers stay on Team Elimination. `/fw mode <id>` picks the next
  round's mode on a test server.
- `GameModeBase` modes have an `objective` and a `hint`;
  `MatchScoreService.record(event, points)` scores any event the mode
  accepts.
- `MapKit`: the map pieces (mirroring, pads, barrels, markers, camera
  views, the control zone), now used by Brainrot Battlefield; maps that
  list a zone mode must have a control zone (`MapBase.validate`).
- The scoreboard's leftover "arrives with combat (Phase 2)" note is gone.
- Docs: [`docs/maps-and-modes.md`](docs/maps-and-modes.md).
- New spec: `GasControl`.

## 0.5.0: Phase 5, part 2: performance, networking and live metrics

- Budgets (`GameConfig.BUDGET`): at most 16 stink clouds on the server
  (a new one ends the oldest), and on each client a pool of 24 shot
  tracers and at most 120 short-lived effect parts.
- `Profiler`: every service loop's tick, shot checks and saves timed;
  remote volume counted; `/fw perf` lists the costliest paths and the
  busiest remotes. The explosion and projectile loops run through
  `Health` too.
- Hits by the shooter's ping (`Combat.hitsBy.lowPing` / `midPing` /
  `highPing`), to watch high-ping fairness.
- Settings: LOW DETAIL (no shadows, fewer effects) and VOLUME in quarter
  steps; clients also report render spikes and how long menus wait on the
  server.
- `MetricsService`: segments (new or returning, paying or free); the
  onboarding funnel (also sent to Roblox's); eliminations and deaths by
  segment (the free-to-paid check); session length buckets, minutes and
  early leavers by segment; concurrent players; coin sources and sinks
  sent to Roblox's economy events. A failing analytics call is counted
  and never breaks the game.
- Docs: [`docs/store-page.md`](docs/store-page.md) (title, description,
  thumbnails, icon, creative testing, the first funnel) and the Phase 5
  checklist.
- New specs: `Network`, `Metrics`.

## 0.5.0: Phase 5, part 1: release, health and player safety

- Version `0.5.0` (`ReleaseConfig`), and a channel from the place ID
  (live, staging or dev): on the home screen, in Settings, in Workspace
  attributes and the server's first log line.
- `Health`: the service loops run through it (an error in one tick is
  counted and reported, and the loop keeps going). Every 30 seconds it
  checks the loops, errors per minute, frame rate, memory and a DataStore
  round trip, and publishes OK, DEGRADED or FAILING (`ServerHealth`, the
  log, `/fw health`). Clients send their frame rate, ping, error count and
  graphics quality about once a minute (`ClientReport`).
- The Players screen (PLAYERS on the home screen and in the M menu):
  BLOCK (Roblox's prompt), HIDE EMOTES and REPORT with a reason
  (`ReportPlayer`). Three different players reporting someone in a server
  flags them for review; the screen points to Roblox's own Report too.
- A notice on touch screens without a keyboard: the beta is for PC.
- Docs: [`docs/release.md`](docs/release.md) (beta scope, staging and
  live places, version numbers, the release checklist, rollback, the soft
  launch, live metrics, decision gates, the weekly issue list and the test
  matrix).
- New spec: `Release`.

## Phase 4, part 3: friends, experiments and the roadmap

- `SocialService`: the squad bonus (50 coins and 50 XP for every ten
  active minutes with a Roblox friend on your team, 3 a day) and the
  newcomer welcome (a new account's first ten active minutes with a friend
  in the server pays both 200 coins, once per newcomer; the friend must
  have played before and can welcome 3 a day). No invite rewards.
  Friendships come from TeamService's lookup as players join.
- `ExperimentService` and `ExperimentConfig`: cohorts from the user ID
  (stable across servers), a share of players by percent and variants by
  weight. Three experiments, all at 0% as shipped: `giftMinutes` (8 instead
  of 10), `earlyUnlock` (early shop weapons 25% cheaper; the server's price
  is what's paid and shown) and `tips` (tips start off; Settings still
  wins). Counters by cohort: `exp.<key>.<variant>.*`.
- Retention by visit (`profile.visit`), co-play counters (`social.*`),
  new profile fields for squads and welcomes.
- Docs: [`docs/roadmap.md`](docs/roadmap.md) (prestige, battle pass,
  events, and what needs a decision) and the Phase 4 checklist.
- New spec: `Social`.

## Phase 4, part 2: the store and cosmetics

- `MonetizationService` and `MonetizationConfig`: coin packs (developer
  products) through ProcessReceipt, paid once per receipt (remembered in
  the profile), saved before Roblox is told "granted", answered "not yet"
  (coins taken back) when the player is away, the profile isn't saving or
  the save fails; passes (the Starter Pack: a tracer, a Fart Dash trail, an
  emote, 500 coins once) given once when owned, checked with Roblox. IDs
  are 0 until you set them; the store then shows items as unavailable.
- Cosmetics now come in three kinds with their own slots: tracers, Fart
  Dash trails (puff colour) and emotes (E, shown over your head; Toot is
  free for everyone). New: Starter Swirl, Lime Trail, Toot, Victory Toot.
- Locker: a Store tab (contents in full, prices from Roblox, "nothing you
  can buy makes your weapons stronger") and a cosmetics grid (equip, take
  off, or where it comes from). The + by your coins opens the store.
- `EconomyService.grantPurchase` / `revoke`; reward sessions are created
  on demand; the `Emote` remote; `/fw selftest` warns while no store IDs
  are set.
- New spec: `Store`.

## Phase 4, part 1: daily rewards, gifts and free spins

- `RewardsService` and `RewardsConfig`: a seven-day track, one claim per
  UTC day (100 to 500 coins; a free spin on days 3 and 6; the Stink
  Sparkle tracer on day 7, or coins if owned). It loops, and a missed day
  doesn't reset it. A free spin for every 10 minutes of active play (AFK
  and the home screen don't count), 6 a day, banked up to 10. The spin
  draws on the server by published weights. Every claim is recorded
  before it pays, through unique grant IDs; unsaved sessions can't claim.
- Client: the Daily Rewards screen (opens by itself on the home screen
  when a claim is waiting; ticks, today, CLAIM, the exact countdown to the
  reset), the spin screen with every chance shown, and SPIN / DAILY
  buttons top right. The home screen's Rewards opens the daily screen.
- Retention: `retention.newPlayers`, `retention.nextDay`, `retention.D1`,
  `retention.D7`, `Rewards.dailyClaims`, `Rewards.gifts`, `Rewards.spins`.
- New cosmetics Stink Sparkle and Lucky Lime; `FeatureFlags.REWARDS`;
  the `RewardsRequest` remote; `/fw daily` and `/fw spins`.
- New spec: `Rewards`.

## A new look, and a weapon in your hands

- Your equipped weapon is held in your avatar's hand: a Tool built from
  parts in the weapon's colour (it can't be hit or collided with). It
  follows your loadout.
- Hotbar: your weapons in slots 1-4 (number keys or click; the one in hand
  outlined, NEXT on one waiting for your respawn) and Q with your ability
  and its cooldown. A swap is immediate off the battlefield or in the first
  seconds of a spawn (still protected); mid-fight it waits for the respawn.
  Roblox's own backpack bar is hidden.
- HUD: chunky score boxes in each team's colour either side of the timer;
  coins with + and big Shop / Abilities / Levels / Settings buttons top
  right; gas and Fart Dash bars over the hotbar; a segmented level bar
  along the bottom; the kill feed moved under the buttons.
- PLAY opens "Choose a Team": two big team cards with counts, a lock on a
  team that would make the match unfair, and AUTO.

## Readiness pass: Phases 1-3

Two independent reviews (server integrity, Roblox runtime) and a soak test
found these; each is fixed and has a spec.

- Saving: shutdown now waits for saves already under way (the last players'
  progress could be lost when a server closed); writes take turns per
  profile and take the latest data, so a retried save can't land after the
  final one and bring back spent coins or a held lock.
- Memory: departed players were kept alive by two connections (character
  spawning, chat commands); they're disconnected on leave. The harness now
  frees disconnected handlers like Roblox, so `Soak` can check it.
- Nobody dodges an explosion: a team switch, a new round, Reset or any
  other death mid-countdown (or while gassed) still credits the attacker.
  Reset Character is off on the client.
- Credit: no kill for an attacker whose gas drained away or was over 10 s
  ago; no mastery for gas nobody fired; someone who switched teams can't
  gas or assist against their new teammates.
- Rates: shots, dash and Q use `Cadence` (no sustained rate above the
  interval; honest jitter passes). Refused-request tracking is bounded, so
  a flood can't slow the server. Infinite dash directions are refused.
- Fart Dash through a wall is put back and flagged.
- Hats and hair no longer take shots (or hide the head from a headshot).
- The map stays streamed in for spectators even if streaming is on.
- `/fw` is registered as a TextChatService command (legacy `Chatted`
  still works); `/fw coins` and `/fw xp` take any amount.
- Locker text no longer spills at 1366×768.
- Gaps from the plans: the return rate, first purchase rate and
  ten-minute completion are measured; moderation hooks (`Moderation`,
  `Telemetry.flag`); Settings gains sound effects and tips; contextual
  tips (`TipsController`).
- `/fw selftest` checks the real server (settings, map, remotes, teams,
  DataStores, chat); `docs/studio-signoff.md` is the one-session Studio
  sign-off.
- New specs: `Soak` (20 players, 20 minutes, everything on), `Dodges`;
  regressions in `Data`, `Combat`, `Arsenal`, `Economy`, `Shop`, `Rounds`.
  Any background error now fails a spec.

## Phase 3, milestone 2: the shop, loadouts, weapons and abilities

- Three new weapons, each a different way to play: the **Spritzer**
  (level 5, 400 coins: rapid 7% hits, 60-stud range), the
  **Thunderclapper** (level 15, 1,200: 40% hits, 55% to the head, one a
  second, a slower walk) and the **Stink Lobber** (level 25, 2,500: a
  server-flown lob, a 15% splash and a 4-second cloud that gasses enemies
  inside it). `WeaponConfig` gains handling (walking speed), price, level
  and the lob fields; `ProjectileService` flies the bombs and ticks the
  clouds.
- Q abilities by level (`AbilityService`): **Recovery Burst** (level 10:
  vent 35% gas, 20 s) and **Gas Pulse** (level 30: a 0.4 s wind-up, then
  15% to enemies within 12 studs, 25 s). One equipped, one cooldown, a
  visible tell for each; a death resets the cooldown.
- `ShopService` (`ShopRequest`): purchases checked on the server (for
  sale, not owned, level, coins), coins and weapon saved together before
  the answer, rolled back with a refund if the save fails; one request at
  a time; temporary profiles can't buy. Equipping through
  `LoadoutService`: owned items only, mid-fight changes wait for the next
  respawn, tracers switch at once. `EconomyService.spend` / `refund`.
- The locker (`LockerController`): Weapons (stats, preview colour,
  mastery, BUY / EQUIP / what's missing), Abilities, Progression (the
  unlock track, stats, badges, tracers) and Settings (reduced effects,
  controls), from the home screen and the M menu, with pending and answer
  states. Rewards and Leaderboard stay Coming Soon.
- HUD: the weapon in hand (and "new loadout on respawn"), the Q ability
  and its cooldown. Effects: the lob arc, splash and cloud, the vent puff,
  the pulse ring; tracers in the shooter's cosmetic colour.
- Remotes `UseAbility`, `ShopRequest`, `ProfileUpdate`. Test commands
  `/fw weapon` (now gives the weapon for real) and `/fw ability`.
- New specs: `Arsenal`, `Shop`.

## Phase 3, milestone 1: saving, coins, XP and levels

- `DataService`: player profiles in a DataStore, with every field the
  masterplan lists. Session locks (another server's is waited on for 15 s,
  then taken; a crashed server's is taken at once; a server that loses its
  lock stops saving), retries with backoff, versioned migrations that
  repair partial or damaged saves, autosave every minute, saves on leaving
  and on shutdown. When a profile can't load, a temporary one that never
  saves.
- `EconomyService` and `ProgressionConfig`: coins and XP for eliminations,
  assists, chain and barrel kills, the 5-kill streak and 5 / 10 minutes of
  active play; each grant once, by a unique ID, within per-grant limits,
  logged in the profile's ledger and counted by source. Levels 1-50 with
  their unlocks, the level-50 reward and badge, a repeat reward every
  5,000 XP after it, lifetime XP. Weapon mastery at 25 / 75 / 150 / 300
  eliminations. Lifetime eliminations, deaths, best streak and playtime.
  Anomalous coin gains are logged.
- Client: `ProgressController` shows coins, level, the XP bar and the next
  goal; reward lines; the level-up banner; whether progress is saving.
- The new `ProgressEvent` remote (server → one client). The weapon that
  fired the final shot now travels with gas and eliminations;
  `EliminationService` gains an `Alpha` signal, and `Eliminated` carries
  one record.
- Test commands `/fw coins`, `/fw xp`, `/fw profile`; `/fw stats` adds
  coins and XP granted, temporary profiles and save failures.
- New specs: `Data` and `Economy`.

## Phase 2, milestone 2: chain reactions and gas barrels

- `ExplosionService`: an exploding player blasts 40% gas onto the
  killer's enemies within 14 studs (walls and cover stop it), credited to
  the killer; chains go up to 4 steps deep; at most 6 blasts resolve per
  tick.
- `BarrelService`: 12 gas barrels (each a `GasBarrel` model). 40 health,
  so two shots; a 0.6 s fuse (a lit barrel gets a steady red outline); a
  16-stud, 40% blast for the last shooter's side; back after 20 s. Blasts
  set off barrels in range, so barrel-player-barrel chains happen.
- Playtest metrics: eliminations a minute, barrel and chain kills, spawn
  deaths (within 5 s of spawning), dashes and gas recovered, all in
  `/fw stats`.
- `/fw barrels` resets them all. New `Chaos` spec.

## Phase 2, milestone 1: gas and eliminations

- The Gas Blaster replaces the placeholder: 20% gas a body hit, 25% to the
  head. Shots are numbered; repeats are refused. Suspicious accuracy and
  impossible movement between shots are logged.
- `GasService`: the gas meter replaces health. Stages at 25 / 50 / 75%,
  clamped at 100, then a one-second countdown (no firing or dashing) and
  the explosion. Recovery after 5 seconds without gas, at 5% a second.
- `EliminationService`: each death credited once with an event ID; the last
  enemy to add gas is the killer, others from the last 10 seconds assist.
  Leaving or spectating mid-countdown explodes at once and still credits
  the killer.
- Streaks: five eliminations without dying calls "BRO IS THE ALPHA FART!"
  to the whole server, once; announcements are spaced 3 seconds apart.
- `AbilityConfig` (Fart Dash by the masterplan's ability contract; no
  dashing while exploding) and `AudioConfig` (empty sound slots).
- Client: gas meter, streak, headshot markers, "EXPLODED" cards, kill feed
  with assists; `EffectsController` for gas bellies, the critical outline,
  pooled explosion bursts, dash puffs and the alpha banner. Effects thin out
  at low graphics quality.
- Test command `/fw gas <n>`; `/fw resetgas` empties the meter.
- Specs: `Combat` rewritten for gas, new `Gas` and `Streak`.

## Phase 1 aligned with the masterplan

- Placeholder Starter Blaster: left click, mouse aim, server-cast hitscan,
  25 damage, enemies only, eliminations score once per life. Crosshair,
  tracers, hit markers, a damage direction marker, kill feed and
  elimination cards.
- 3 seconds of spawn protection after every spawn, ended by firing.
- Shift is Fart Dash (cooldown and travel checked on the server); sprint is
  gone.
- `FeatureFlags`: 5-minute rounds stay the default; continuous play
  (join straight onto a team, no timer) is `MATCH_MODE = "Continuous"`.
- Team ties are broken the same way every time (team behind on score, then
  team order) instead of at random.
- Barrels moved from beside the spawns to the contested middle.
- `Telemetry`: structured logs, counters, errors per service, rejected
  requests by remote and reason, abnormal request rates, time to first
  shot / hit / elimination.
- Test commands: `/fw spawn`, `/fw team`, `/fw resetgas`, `/fw weapon`,
  `/fw stats`.
- Teammates outlined in their team colour.
- `WeaponConfig` and three new remotes: `FireWeapon`, `FartDash`,
  `CombatEvent`.
- `docs/implementation-packet.md`: folder tree, module contracts, remote
  payloads, flags, tests and known limits.
- New specs: `Combat`, `Continuous`; churn in `Lifecycle`; barrel placement
  in `Map`.

## Phase 1: foundation and first playable prototype

- Rojo project with the plan's structure: shared config (`GameConfig`,
  `TeamConfig`, `MapConfig`, `UIConfig`), the `MapBase` and `GameModeBase`
  contracts, seven remotes, six server services, the client controllers.
- Teams: Skibidi Stinkers vs Sigma Sharters, up to 10 active players each.
  Joins go where they keep the teams most even; a player's choice counts
  only when it's as fair; friends break ties; voluntary switches only when
  they even the teams.
- Rounds: WAITING → ACTIVE (300 s) → RESULTS (15 s) → ACTIVE, on server
  timestamps, with snapshots to clients. Most eliminations wins; level
  scores draw. Scores freeze the moment a round ends.
- Player lifecycle: menu spectator on join, PLAY (also mid-round), spawn at
  the safest team spawn, 3-second respawn, spectate, leave, reconnect. No
  avatar outlives its slot.
- AFK: "BRO FELL ASLEEP MID-FART!" at 45 seconds idle, AFK spectator at 60,
  slot freed. Only real movement counts as activity.
- Brainrot Battlefield v0: a 160 × 160 mirrored blockout with three lanes,
  four lane connections, covered spawn rooms, giant toilets, bean cans and
  decorative barrels.
- UI shell: home screen over the live battlefield (PLAY, team choice,
  Coming Soon sections), HUD (teams, scores, timer, state), results, Tab
  scoreboard, M menu, V camera toggle, Shift sprint, a one-time controls
  card.
- Test-only controls (Studio or allow-listed users): scores, phase end, map
  reload, idle time. Turn off before public release.
- Specs for the QA matrix, rounds, lifecycle, client shell, map, team rules,
  modes and project structure, runnable without Studio.
