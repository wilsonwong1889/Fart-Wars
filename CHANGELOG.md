# Changelog

## 0.9.0: the map's walls and floors, made in Blender

- Walls, trims and floors made in Blender (`art/blender/build_props.py`)
  as modules: panelled wall sections in two heights (dividers and spawn
  rooms; the 24-stud boundary) with pilasters and bands, a rounded neon
  trim, Porcelain Plaza's square tiles, the side lanes' flagstones, the
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
