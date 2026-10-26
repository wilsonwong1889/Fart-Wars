# Fart-Wars

**Fart Wars** is a Roblox team game: the **Skibidi Stinkers** (toxic green)
against the **Sigma Sharters** (bright yellow) on the Brainrot Battlefield.

This repository holds **Phase 1** (the foundation), **Phase 2** (combat
and chaos) and **Phase 3** (progression and economy) of the six-phase
masterplan. Two or more players join a running
server, press PLAY, land on balanced teams, and blast each other with the
Gas Blaster on a symmetrical three-lane map until someone inflates and
explodes. Five-minute rounds end in a win or draw, a 15-second intermission
follows, and the next round starts with no server restart. Continuous play
(no rounds) is one setting away. Eliminations, assists, streaks and time
played earn coins and XP toward levels 1-50, saved between sessions;
coins buy three more weapons, levels unlock two Q abilities and tracer
cosmetics, all equipped from the locker.

## Getting started

1. Install [Rojo](https://rojo.space) 7.4 or newer (older 7.x releases skip
   `.luau` files) and its Studio plugin.
2. Create a place named **Fart Wars - Development** and keep the experience
   **private** while testing. Turn on Team Create if you're collaborating.
3. In **Game Settings → Places**, set **Max Players** to **20**. A script
   can't set this; the server warns in the output if it's anything else.
4. Run `rojo serve` in this folder and connect from the Studio plugin.
5. Press **Play** to try it alone, or **Test → Clients and Servers** with two
   or more players for a real round. With one player you stay in WAITING;
   a second player on the other team starts the round.
6. To test saving in Studio, publish the place once, then turn on **Game
   Settings → Security → Enable Studio Access to API Services**. Without
   it the game still runs, on temporary profiles that never save (the HUD
   says so, and the output warns once).
7. Chat `/fw selftest`: it checks the place settings, the map, remotes,
   teams, DataStore access and chat on the real server, one line each in
   the output. Then work through
   [`docs/studio-signoff.md`](docs/studio-signoff.md), the Studio sign-off
   for Phases 1-3.

Studio publishes to the private experience as usual. Nothing in this
repository holds credentials or API keys, and nothing should.

## How it plays

| Rule | Phase 1 |
| --- | --- |
| Teams | Skibidi Stinkers vs Sigma Sharters |
| Capacity | 20 connections; at most 10 active players a team |
| Start | at least 2 active players and nobody alone without an opponent (1v1 is fine) |
| Rounds | 5 minutes, then 15 seconds of results, on a server that keeps running |
| Joining mid-round | PLAY puts you straight into the current round |
| Team choice | only when it doesn't make the teams less even |
| Friends | break a tie between equally fair teams, nothing more |
| AFK | warning at 45 seconds ("BRO FELL ASLEEP MID-FART!"), spectator at 60, slot freed |
| Camera | third person; V toggles first person |
| Home screen | the live battlefield behind the menu; you spectate until PLAY |
| Result | most validated eliminations wins; level scores are a draw |
| Combat | the Gas Blaster: 20% gas a body hit, 25% to the head, 0.3 s between shots; friendly fire off |
| Weapons | Gas Blaster (starter, all-round), Spritzer (level 5, 400 coins: 7% at 10 shots a second, 60-stud range), Thunderclapper (level 15, 1,200: 40% / 55% to the head, one a second, slower walk), Stink Lobber (level 25, 2,500: a lobbed bomb, 15% splash and a 4-second cloud that gasses enemies in it) |
| Abilities | Shift: Fart Dash (everyone). Q, one equipped: Recovery Burst (level 10: vent 35% gas, 20 s) or Gas Pulse (level 30: after a 0.4 s wind-up, 15% to enemies within 12 studs, 25 s). One cooldown whichever is equipped; a death resets it |
| Shop and loadouts | prices and levels checked on the server; a purchase is saved before it's confirmed. Weapon and ability changes made mid-fight wait for the next respawn; tracers apply at once |
| Gas | replaces health. Stages at 25 / 50 / 75%; at 100% a one-second countdown, then the explosion. Five seconds without taking gas, it drains 5% a second |
| Eliminations | the last enemy to add gas scores; others from the last 10 seconds assist. Five in a row without dying: the whole server hears "BRO IS THE ALPHA FART!" |
| Explosions | an exploding player blasts 40% gas onto the killer's enemies within 14 studs (not through walls), credited to the killer; chains stop after 4 steps |
| Barrels | 12 gas barrels in the middle. Two shots light the fuse; 0.6 s later they blast 40% gas onto the last shooter's enemies within 16 studs, set off nearby barrels, and come back 20 s later |
| Spawning | the team's pad farthest from enemies; 3 seconds of protection, ended by firing; respawn 3 seconds after a death |
| Match mode | `FeatureFlags.MATCH_MODE`: `"Rounds"` (default) or `"Continuous"` (join straight onto a team, no timer, scores run on) |
| Coins and XP | elimination 10 coins / 20 XP, assist 5 / 10, chain or barrel kill +5 coins, the 5-kill streak 50 / 100, 5 and 10 minutes of play 25 / 50 and 75 / 100 (once a session). Coins are spent in the shop; XP only levels you up |
| Levels | 1 to 50 on a rising curve (100 XP for level 2). Unlocks at 5, 10, 15, 20, 25, 30, 40 and 50; level 50 pays 1,000 coins and the Alpha Farter badge, then 250 coins every 5,000 XP |
| Mastery | 25 / 75 / 150 / 300 eliminations with a weapon: a badge and 100 / 250 / 500 / 1,000 coins each, once |
| Saving | profiles in a DataStore, locked to one server at a time, autosaved every minute and on leaving or shutdown |
| Daily rewards | a 7-day track (100 to 500 coins, a free spin on days 3 and 6, the Stink Sparkle tracer on day 7), one claim per UTC day; it loops, and a missed day doesn't reset it |
| Free spins | one for every 10 minutes of active play (6 a day, banked up to 10), plus the daily ones; every prize's chance is on the spin screen |
| Cosmetics | tracers (your shots' colour), Fart Dash trails and emotes (E, over your head); from levels, the daily track, the spin and the store. None changes combat |
| Store | the Starter Pack (a tracer, a trail, an emote, 500 coins once) and coin packs; nothing for sale changes combat. Set the IDs in `MonetizationConfig` to sell them; until then the store shows them as unavailable |

**Controls (PC):** WASD move, mouse aim, left click fire, Shift Fart Dash,
Q ability (once unlocked), 1-4 pick a weapon from the hotbar, E emote, Space jump,
V first/third person, M menu, Tab (hold) scoreboard. R and F are kept free
for later mechanics.

**On screen:** score boxes in each team's colour either side of the timer;
coins and the Shop / Abilities / Levels / Settings buttons top right; the
gas bar and the Fart Dash charge over a hotbar (your weapons in slots 1-4,
your ability on Q with its cooldown) and the level bar along the bottom.
Your weapon is in your avatar's hands. PLAY opens "Choose a Team": each
team's card shows its count and is locked when joining it would be unfair. The first PLAY of a session shows a
small controls card; there's no tutorial. Bindings live in
`UIConfig.keys`.

**Round states:** WAITING → ACTIVE (300 s) → RESULTS (15 s) → ACTIVE, or back
to WAITING when there aren't enough players. A round in progress always
finishes, even if a whole team leaves. The server owns every timestamp;
clients get a snapshot with an absolute end time and work out the countdown
from the server clock, so lag never stretches a round.

**Player states:** MENU_SPECTATOR (just joined, or chose to spectate),
ACTIVE (on a team with an avatar) and AFK_SPECTATOR (moved off their team
for being idle). Only ACTIVE players have an avatar or a team slot. The
server sets the state; clients read it from the Player's `State` attribute.

## Project structure

Rojo maps the source like this (`default.project.json`):

| In Studio | Source | What it is |
| --- | --- | --- |
| `ReplicatedStorage.Shared.Config` | `src/shared/Config` | `GameConfig`, `FeatureFlags`, `TeamConfig`, `MapConfig`, `WeaponConfig`, `AbilityConfig`, `ProgressionConfig`, `RewardsConfig`, `MonetizationConfig`, `ExperimentConfig`, `ReleaseConfig`, `AudioConfig`, `UIConfig` |
| `ReplicatedStorage.Shared.Interfaces` | `src/shared/Interfaces` | `MapBase`, `GameModeBase`: the contracts maps and modes keep |
| `ReplicatedStorage.Shared` | `src/shared` | `TeamBalance` (the team rules), `RoundClock`, `States`, `Signal` |
| `ReplicatedStorage.Remotes` | `default.project.json` | `RequestPlay`, `RequestTeam`, `RequestSpectate`, `RoundSnapshot`, `RoundUpdate`, `TeamUpdate`, `UIMessage`, `FireWeapon`, `FartDash`, `CombatEvent`, `ProgressEvent`, `UseAbility`, `ShopRequest`, `ProfileUpdate`, `RewardsRequest`, `Emote`, `ReportPlayer`, `ClientReport` |
| `ServerScriptService.Server` | `src/server` | `Bootstrap.server.luau`, `Telemetry`, `Health`, `Moderation`, `TestControls`, `Messages`, `RateLimit`, `Cadence` |
| `ServerScriptService.Server.Services` | `src/server/Services` | the services below |
| `ServerScriptService.Server.Modes` | `src/server/Modes` | `TeamElimination`, the Phase 1 mode |
| `ServerStorage.Maps` | `src/maps` | `BrainrotBattlefield`, built from code |
| `StarterPlayerScripts.Client` | `src/client` | `ClientBootstrap`, `ClientState`, `UI` and the controllers |

The screens (`HomeScreen`, `HUD`, `ResultsScreen`, `Scoreboard`,
`Progress`, `Locker`, plus `GameMenu` and `ComingSoon`) are built in code by the client controllers
rather than stored in `StarterGui`, so they live in Git like everything
else.

### Services

| Module | Owns |
| --- | --- |
| `RoundService` | the match state, server timestamps, the start threshold, the timer, results and intermission; publishes snapshots |
| `TeamService` | active team counts and Roblox `Team`s; checks every join, leave, spectate and switch against `TeamBalance`; friend preference |
| `PlayerLifecycleService` | each player's runtime state; PLAY, spawning, safe respawns, spectating, leaving; no avatar ever outlives its slot |
| `AFKService` | the 45/60-second warning and spectator move, judged on the server |
| `MapService` | loads the map template, checks it against `MapBase`, picks safe spawns; ready for map rotation |
| `MatchScoreService` | this round's scores, frozen the moment a round ends; the test-only elimination input |
| `CombatService` | the Gas Blaster: checks each shot (state, interval, shot numbers, payload), casts it on the server, sends hits to GasService; logs suspicious accuracy and movement |
| `GasService` | the gas meter: enemy-only gas, protection, recovery, the countdown and the explosion, killer and assists |
| `EliminationService` | each death credited exactly once, with an event ID; streaks and the alpha announcement |
| `ExplosionService` | blasts from explosions: gas to the owner's enemies in range and in sight, chain depth limit, a per-tick budget |
| `BarrelService` | gas barrels: health, fuse, ownership by the last shot, blasts, respawn |
| `DashService` | Fart Dash: cooldown and travel checks |
| `AbilityService` | the Q ability: checks (state, equipped, exploding, cooldown), Recovery Burst's vent, Gas Pulse's wind-up and blast |
| `ProjectileService` | stink bombs: the server-flown arc, the splash, the clouds and their ticks |
| `DataService` | player profiles: session-locked loads with retries, migrations, autosave, leave and shutdown saves, temporary profiles when DataStores are down; the only module that touches the DataStore |
| `EconomyService` | coins, XP, levels and unlocks, the cap rewards, participation, mastery and lifetime stats; every grant has a unique ID, limits and a ledger entry; spending and refunds |
| `LoadoutService` | the equipped weapon, ability and tracer: owned items only, applied on each spawn (mid-fight changes wait), the profile view for the screens |
| `ShopService` | `ShopRequest`: purchases (server prices and checks, saved before confirming, rolled back on a failed save) and equipping |
| `MonetizationService` | the store: coin-pack receipts (paid once, saved before "granted", retried when they can't be), passes (given once when owned) |
| `ExperimentService` | retention experiments: each player's cohorts (from their user ID), the values they get (gift timing, early prices, tips), telemetry by cohort; all off as shipped |
| `SocialService` | playing with friends: the squad bonus (a friend on your team), the one-time newcomer welcome, co-play counts |
| `RewardsService` | `RewardsRequest`: the daily track, ten-minute gifts (active play only, capped per day), free spins drawn by published weights; every claim recorded before it pays |
| `Telemetry` | structured `[FW]` logs, counters, errors per service, rejected requests by remote and reason, abnormal request rates, flags for review, time to first shot / hit / elimination / purchase, the return rate |
| `Moderation` | acts on flags (abnormal requests, accuracy, movement, coins, dashing through walls, reports from several players): review only by default, or a kick at `GameConfig.MODERATION.KICK_AT_FLAGS`; turns away `BANNED_USER_IDS`; `ReportPlayer` (fixed reasons, once per person, a few a session) |
| `Health` | runs the service loops (an error in a tick is counted and reported, and the loop goes on); checks loops, errors per minute, frame rate, memory and saving every 30 seconds; Workspace's `ServerHealth`; `ClientReport` (clients' frame rate, ping, errors) |
| Client controllers | `InputController`, `CameraController`, `CombatController` (crosshair, gas and dash bars), `EffectsController`, `HUDController` (score boxes and timer), `ProgressController` (level bar, rewards), `LockerController`, `HotbarController` (weapons 1-4, Q), `MenuBarController` (coins, menu buttons), `TipsController`, `PlayersController` (block, hide emotes, report), `HealthController` (the client's report), `HomeController` (home screen, Choose a Team, the version): render, capture input, switch camera, fire, dash and use abilities, ask the shop; they never decide teams, hits, results, rewards or purchases |

`Bootstrap.server.luau` loads them in dependency order. No module requires
one that depends on it (the specs fail on a require cycle).

### Remotes

Clients only state intent: PLAY (with an optional team), a team choice or
switch, spectate, which way they're aiming, a dash, Q, a purchase or an
equip. The server re-checks
state, capacity, eligibility, fire interval, payload types and a per-player
cooldown, casts every shot itself, and never accepts a hit, score, timer or
team count from a client, and there's no remote at all for coins, XP or
levels, and a purchase sends only the weapon's ID. `RoundSnapshot` and
`ShopRequest` answer requests; `RoundUpdate`, `TeamUpdate`, `UIMessage`,
`CombatEvent`, `ProgressEvent` and `ProfileUpdate` go from the server to
clients. Exact payloads are in
[`docs/implementation-packet.md`](docs/implementation-packet.md).

## Brainrot Battlefield v0

A 160 × 160 stud blockout, mirrored across the centre line so neither side
has a better layout (`src/maps/BrainrotBattlefield.luau`):

- **Three lanes** split by divider walls with two gaps each: **Bean Alley**
  (giant bean cans), **Porcelain Plaza** (a back-to-back giant toilet throne
  at the centre) and **Gas Gutter** (crates, a sideways toilet, barrel
  clusters).
- **Spawn rooms** at each end, walled at the front and sides with their
  doors at the back. Nothing in the lanes or the enemy half can see a pad
  (the Map spec checks over 13,000 sightlines).
- **Gas barrels** sit in the contested middle, never by a spawn, one
  `GasBarrel` model each in the `Barrels` folder.
- `Zones` marks the lanes and spawn areas, `CameraPoints` holds the home
  screen's fixed views, and `Bounds` is the playable box.

To replace it with a map built in Studio, put a Model named
`BrainrotBattlefield` in `ServerStorage.Maps` (and remove the module) with
`Spawns/Stinkers`, `Spawns/Sharters`, `CameraPoints` and `Bounds` as
described in `src/shared/Interfaces/MapBase.luau`. MapService sets the
SpawnLocations up for their teams and refuses a map that breaks the
contract. A new map is a `MapConfig` entry plus its template.

## Test-only controls

These exercise rounds, spawning and combat without waiting for the real
thing. They run on the server only. In Studio anyone can use them; in a live server, only the user
IDs in `GameConfig.TEST_CONTROLS.USER_IDS` (empty by default). **Set
`GameConfig.TEST_CONTROLS.ENABLED` to `false` before any public release.**

Chat (`/fw` or `!fw`):

```
/fw score stinkers 3     three eliminations for a team (stinkers/green, sharters/yellow)
/fw end 5                end the current round or intermission in 5 seconds
/fw reloadmap            rebuild the map; active players respawn on it
/fw idle 44              count yourself as idle for 44 seconds (to see the AFK warning)
/fw spawn                respawn (or PLAY from the home screen)
/fw team sharters        move to a team whatever the balance, and respawn
/fw resetgas             empty your gas meter
/fw gas 95               set your gas (100 starts your countdown)
/fw weapon spritzer      give yourself a weapon (saved for real) and hold it now
/fw ability gaspulse     unlock and equip a Q ability
/fw barrels              every gas barrel back, full
/fw coins 500            coins through the normal grant path (ledger and all)
/fw xp 1000              XP the same way (level-ups, unlocks)
/fw profile              your saved progress, and whether it's saving
/fw selftest             checks this server: settings, map, remotes, teams, DataStores, chat
/fw daily                today's daily reward claimable again
/fw spins 3              free spins
/fw stats                shots, hits, eliminations a minute, barrel and chain kills,
                         spawn deaths, dashes, gas recovered, coins and XP granted,
                         temporary profiles, save failures, rejected requests, errors
```

Or the server command bar in Studio:

```lua
local T = require(game.ServerScriptService.Server.TestControls)
T.score("Stinkers", 3); T.endPhase(5); T.reloadMap(); T.idle(game.Players.Player1, 44)
T.spawn(p); T.team(p, "sharters"); T.resetGas(p); T.gas(p, 95); T.weapon(p, "GasBlaster"); T.barrels(); T.stats()
T.coins(p, 500); T.xp(p, 1000); T.profile(p); T.ability(p, "GasPulse"); T.selftest(p)
```

## Tests

The specs in `tests/` run without Studio, on the Luau CLI, against stand-ins
for the Roblox engine (`tests/local/harness.luau`, with a virtual clock so a
five-minute round takes no real time):

```
python3 scripts/run_specs.py            # all specs
python3 scripts/run_specs.py QAMatrix   # one spec
```

They need `luau` on your PATH (`brew install luau`, or a release from
[luau-lang/luau](https://github.com/luau-lang/luau/releases)).

| Spec | Covers |
| --- | --- |
| `QAMatrix` | the plan's QA matrix, row by row, on one 20-player server |
| `Combat` | two players fight with the Gas Blaster: body and head hits, no spawn kills, the countdown and explosion, repeated deaths, friendly fire, walls, refused and duplicate shots, Fart Dash, test commands, telemetry |
| `Gas` | gas stages, clamping, recovery and its interruption, 99 to 100, simultaneous hits, assists, leaving or spectating mid-countdown, no double kills |
| `Streak` | "BRO IS THE ALPHA FART!" once at five, resets, two at once; the client's banner, inflation and effect pool |
| `Chaos` | chain reactions and their depth limit, blasts sparing the killer's team and stopped by walls, the per-tick budget, barrels (fuse, blast, credit, respawn), barrel-player-barrel chains |
| `Data` | saving against a stand-in DataStore: defaults, autosave, leave and rejoin, session locks (waiting, taking a stuck or stale one, losing one), outages, newer saves, migrations, failed writes, leaving mid-load, rejoining mid-save, shutdown, ten joins at once |
| `Economy` | every grant and its limits, no double rewards, level-ups and unlocks to 50 and past it, mastery, participation (active time only), rewards before the profile loads, anomaly logging; the client's progress panel |
| `Store` | receipts (once, saved first, repeats, unknown products, absent players, failed saves and retries, the memory limit), passes (on joining and after buying, verified, once across sessions), cosmetic slots and emotes, the Store tab and cosmetics grid |
| `Rewards` | the daily track (once a UTC day, loops, no reset for missed days, spins and the day-7 tracer), gifts (active play only, the daily cap, the bank cap), spins (one each, the odds over 20,000 draws), unsaved sessions refused; the daily and spin screens |
| `Social` | the squad bonus (friends on one team only, the daily cap), the newcomer welcome (once ever, not between new accounts, the welcomer's daily cap and reset), co-play counts; cohorts (stable, by percent and weight, off as shipped), experiment values reaching the gift timer, shop prices (paid and shown) and the tips default, telemetry by cohort |
| `Release` | the version and channel on every screen; health (every loop watched, a stopped loop FAILING and recovering, a tick's error counted and the loop going on, an error burst, saving's check, `/fw health`); client reports (averaged, junk and spam refused); player reports (reasons, not yourself, once each, the session cap, three reporters flag once); the Players screen (block, hide emotes, report and the answer) |
| `Dodges` | nobody dodges an explosion (a team switch, a new round, Reset mid-countdown or while gassed), no credit for stale or ownerless gas, mastery only for gas someone fired, turncoats can't gas or assist against their new team |
| `Arsenal` | the Spritzer's rate and range, the Thunderclapper's weight, the Stink Lobber's arc, splash, cloud and mastery; Recovery Burst and Gas Pulse with every refusal, the shared cooldown and cancelling; Q and the HUD on the client |
| `Shop` | every refusal, purchases saved before confirming, failed saves rolled back, one request at a time, leaving mid-purchase; equipping now or on respawn, handling, abilities and tracers; the locker's tabs, buttons, pending state and answers |
| `Continuous` | continuous play behind its flag |
| `Rounds` | the state machine, scoring, draws, frozen scores, late ticks, test controls, the remotes |
| `Lifecycle` | join, PLAY, spawn, rapid PLAY, team choice, spectate, death and respawn, switching, leave, reconnect, churn |
| `ClientShell` | the home screen, PLAY, HUD, crosshair, left click, V/M/Tab/Shift, results, the AFK warning, against the real server |
| `Soak` | 20 players for 20 minutes with everything on (shooting, every weapon and ability, shopping, spectating, AFK, junk payloads, leaving and rejoining): no errors anywhere, team caps, avatars only for ACTIVE players, sane gas, coins, levels and ownership, rounds turning over, every profile saved and released, and no departed player left in memory |
| `Map` | the MapBase contract, symmetry, lanes, spawn sightlines, barrel placement, reloading |
| `TeamBalance`, `Modes`, `Structure` | the team rules, game modes and the clock, the project's shape and config |

A spec fails on any error in a background thread, not just its own checks.
The stand-ins have almost no physics and no rendering, so Studio stays the
final word: [`docs/studio-signoff.md`](docs/studio-signoff.md) is the
one-session Studio sign-off for Phases 1-3, and
[`docs/phase-1-checklist.md`](docs/phase-1-checklist.md),
[`docs/phase-2-checklist.md`](docs/phase-2-checklist.md) and
[`docs/phase-3-checklist.md`](docs/phase-3-checklist.md) map each plan item
to where it's checked.

For type checking against the Roblox API, use
[luau-lsp](https://github.com/JohnnyMorganz/luau-lsp):

```
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --platform roblox --sourcemap sourcemap.json \
  --definitions @roblox=globalTypes.d.luau src
```

## Phase 1 decisions

Where the plans left room, or disagreed, Phase 1 does this:

- **5-minute rounds by default.** The masterplan made continuous play the
  baseline and the earlier Phase 1 plan made rounds it; rounds are the
  default (your call), and continuous play is `FeatureFlags.MATCH_MODE`.
- **Shift is Fart Dash**, open to everyone (it stays that way; the
  unlockable abilities are on Q). There's no sprint.
- **Ties go the same way every time**: to the team behind on score, then
  the Skibidi Stinkers.
- **A round needs an opponent.** Besides the 2-player minimum, each team
  needs at least one active player, so a 2v0 left behind by leavers waits
  instead of starting a round with no enemy. Nobody is moved: anyone on the
  bigger team can switch (M → SWITCH TEAM), and new joiners fill the empty
  team.
- **Switching only evens teams.** A voluntary switch is allowed when it
  narrows the gap (3v1 → 2v2), never when it only flips it (2v1 → 1v2).
- **Activity is movement the server sees, and shooting.** An avatar has to
  travel 6 studs across the ground, or fire, or dash; jumping or turning on
  the spot, held keys and remote pings don't count.
- **Every round starts from the spawns.** All active players respawn at
  their team's spawn when a round starts. A death respawns after 3 seconds
  at the team's spawn farthest from enemies.
- **Spectators watch from fixed views**, never from another player's eyes,
  so nothing tactical leaks to someone about to press PLAY.
- **The map is code.** That keeps it reviewable in Git; a Studio model with
  the same name replaces it.

## Phase 2 decisions

- **Inflation is a belly, not a bigger avatar.** Each client gives every
  avatar a gas belly that grows with its stage. The real body (and so the
  hitbox and camera) never changes size.
- **A one-second countdown at 100%**, in which the player can't fire or
  dash; then the explosion.
- **The last enemy to add gas is the killer**; anyone else who added gas
  in the last 10 seconds assists.
- **Leaving, spectating or going AFK mid-countdown explodes you on the
  spot**, so nobody can dodge giving the killer the point. A killer who
  leaves before the bang scores nothing.
- **Explosions hurt the killer's enemies.** A player who explodes blasts
  gas onto their own teammates nearby, credited to whoever blew them up;
  the killer's team is never touched. Explosions with nobody to credit
  (a test gas, a killer who left) blast nobody.
- **The last shot owns a barrel.** Whoever finishes it gets the credit and
  their enemies get the gas, so it's never ambiguous. Blasts set barrels
  off for the same owner.
- **Walls and cover stop blasts**, the same as they stop shots.
- **Fart Dash works while spawn-protected**: it's movement, not an attack.
- **Shots are numbered** by the client; a repeated or out-of-order number
  is refused as a duplicate packet.
- **Sounds are empty slots** (`AudioConfig`) until the game's own sounds
  are uploaded.
- **Effects thin out at Roblox graphics quality 3 or lower** (no clouds or
  puffs), or with Reduced effects on in Settings.

## Phase 3 decisions

- **Rewards are paid when they happen, on the server.** Each grant is
  written into the profile at once with a unique ID (from the
  elimination's event ID), so a repeat is refused and leaving mid-animation
  loses nothing; the client only shows it.
- **Participation is once a session**, for time actually ACTIVE (on a team
  with an avatar). The home screen, spectating and AFK time earn nothing,
  so idling pays nothing.
- **Mastery counts eliminations made with the weapon** (its shots, or a
  Stink Lobber's splash and cloud). Chain, barrel and Gas Pulse kills
  still pay, but count toward no weapon. Milestones pay themselves out;
  there's nothing to claim.
- **Playtime is active time** (`TotalPlaytime`, seconds).
- **Level unlocks:** abilities and cosmetics are granted at their level;
  weapons only go on sale, for coins.
- **Weapons are playstyles, not a ladder.** Up close the Spritzer wins,
  at range the Gas Blaster or Thunderclapper, around cover the Stink
  Lobber. Handling is walking speed (never faster than the default, so the
  movement checks stay honest).
- **One Q ability, one cooldown.** Equipping a different ability doesn't
  skip the cooldown; both have a visible tell (the vent puff, the pulse's
  wind-up ring), and Recovery Burst is too late once the countdown starts.
  Gas Pulse is an attack, so it ends spawn protection like firing does.
- **Loadouts change on a safe respawn.** A weapon or ability equipped
  mid-fight waits for the next spawn (the HUD says so); from the home
  screen, or while dead, it's in hand at once. Tracers change nothing in
  combat and switch at once.
- **A purchase is saved before it's confirmed**, coins and weapon in one
  write; if the save fails both are put back and the player is told.
  Temporary profiles can't buy (it would be lost).
- **Stink bombs and Gas Pulse set off barrels** in range, like any blast.

## Readiness decisions (before Phase 4)

- **Reset Character is off.** It let a gassed player skip their explosion;
  any death while gassed (a fall too) now goes to the recent attacker, and
  any respawn mid-countdown explodes the player first.
- **Credit has a time limit.** The killer must have added gas in the last
  10 seconds; gas that's fully drained owes nobody anything.
- **Rates hold over time.** Shots, dash and Q allow a little network slack
  for bunched packets, never a faster sustained rate.
- **Moderation is review-only by default.** Flags are logged and counted;
  kicking is a setting (`GameConfig.MODERATION`), off until the checks are
  tuned on real players.
- **Settings last a session**: reduced effects, sound effects and tips.
- **A profile that won't load is never written.** If DataStores are down
  (or it's Studio without API access, or the save comes from a newer
  version), the player gets a temporary profile, the HUD says progress
  isn't saving, and nothing overwrites the real one.
- **Another server's lock is waited on for 15 seconds**, then taken; a lock
  not refreshed for 3 minutes (a crashed server) is taken at once. A server
  that finds its lock taken stops saving that profile.

## Phase 4 decisions

- **Days are UTC days.** The daily claim, gifts, squad bonuses and
  welcomes all reset at 00:00 UTC, the same moment for everyone; the
  daily screen counts down to it exactly.
- **A missed day doesn't reset the daily track**; it waits on the next day.
- **Gifts are for active play only**, capped per day and banked up to a
  limit, so leaving the game open earns nothing.
- **Odds are on the screen.** The spin shows every prize's chance; the
  draw is on the server.
- **Nothing for sale changes combat.** The store sells coins and
  cosmetics; weapons are bought with coins earned in play, as before.
- **A purchase is saved before Roblox hears "granted"**; when it can't
  be, Roblox is told "not yet" and retries, and the coins are taken back.
- **Friend rewards need real co-play.** The squad bonus is for active
  minutes with a Roblox friend on your team; the welcome is once per new
  account, only from a friend who has played before, a few a day. There
  are no invite rewards (nothing to farm with spam or alternate accounts).
- **Experiments are off as shipped** (`ExperimentConfig`, every percent at
  0). They only move reward timing, early prices and prompts, never power,
  odds or what Robux buys, and a cohort is the same for a player in every
  server.
- **Prestige, a battle pass and events wait** for after the beta, with the
  open questions in [`docs/roadmap.md`](docs/roadmap.md); prestige's power
  bonus needs an explicit balance decision first.

## Phase 5 decisions

- **The beta's scope is frozen** in [`docs/release.md`](docs/release.md):
  PC only, one map, two teams, rounds as the default mode, everything else
  on the roadmap.
- **Every build says which it is**: `ReleaseConfig.VERSION`, and the
  channel (live, staging, dev) from the place ID, on the home screen, in
  Settings and in the server's first log line.
- **Health is watched, not acted on**: a server that's DEGRADED or FAILING
  says so (Workspace's `ServerHealth`, the log, `/fw health`) and keeps
  running; the service loops survive an error in one tick.
- **Reports from players are evidence, not verdicts**: one report does
  nothing but count; three different players in one server flag someone
  for review, the same as the other flags. Roblox's own Report (Esc menu)
  is the path to Roblox moderation, and the Players screen says so.
- **Blocking is Roblox's** (its prompt, which also mutes chat); hiding
  someone's emotes is this player's choice for this session.
- **Clients report a few numbers** (frame rate, ping, errors, graphics
  quality) about once a minute, and nothing else.

## Handoff to Phase 5: Launch and optimization

Phase 5 is the beta: the scope freeze and test matrix, performance and
networking, the store page, moderation and reliability, and the soft
launch. The places it plugs into:

- `Telemetry.snapshot()` (and `/fw stats`) for the live numbers, with
  `retention.*`, `session.*`, `Store.*`, `social.*` and `exp.*` counters.
- `FeatureFlags` and `ExperimentConfig` to switch systems and cohorts
  without code changes.
- `DataService.probe()` and `/fw selftest` for health checks;
  `GameConfig.MODERATION` for kicks and bans.
- [`docs/phase-4-checklist.md`](docs/phase-4-checklist.md) for the Studio
  runs Phase 4 still needs (receipts with real products in particular).

See [`CHANGELOG.md`](CHANGELOG.md) for what changed.
