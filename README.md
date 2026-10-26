# Fart-Wars

**Fart Wars** is a Roblox team game: the **Skibidi Stinkers** (toxic green)
against the **Sigma Sharters** (bright yellow) on the Brainrot Battlefield.

This repository holds **Phase 1** (the foundation) and **Phase 2** (combat
and chaos) of the six-phase masterplan. Two or more players join a running
server, press PLAY, land on balanced teams, and blast each other with the
Gas Blaster on a symmetrical three-lane map until someone inflates and
explodes. Five-minute rounds end in a win or draw, a 15-second intermission
follows, and the next round starts with no server restart. Continuous play
(no rounds) is one setting away. Coins, levels, the shop and the rest
arrive in later phases.

## Getting started

1. Install [Rojo](https://rojo.space) 7 and its Studio plugin.
2. Create a place named **Fart Wars - Development** and keep the experience
   **private** while testing. Turn on Team Create if you're collaborating.
3. In **Game Settings → Places**, set **Max Players** to **20**. A script
   can't set this; the server warns in the output if it's anything else.
4. Run `rojo serve` in this folder and connect from the Studio plugin.
5. Press **Play** to try it alone, or **Test → Clients and Servers** with two
   or more players for a real round. With one player you stay in WAITING;
   a second player on the other team starts the round.

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
| Gas | replaces health. Stages at 25 / 50 / 75%; at 100% a one-second countdown, then the explosion. Five seconds without taking gas, it drains 5% a second |
| Eliminations | the last enemy to add gas scores; others from the last 10 seconds assist. Five in a row without dying: the whole server hears "BRO IS THE ALPHA FART!" |
| Explosions | an exploding player blasts 40% gas onto the killer's enemies within 14 studs (not through walls), credited to the killer; chains stop after 4 steps |
| Barrels | 12 gas barrels in the middle. Two shots light the fuse; 0.6 s later they blast 40% gas onto the last shooter's enemies within 16 studs, set off nearby barrels, and come back 20 s later |
| Spawning | the team's pad farthest from enemies; 3 seconds of protection, ended by firing; respawn 3 seconds after a death |
| Match mode | `FeatureFlags.MATCH_MODE`: `"Rounds"` (default) or `"Continuous"` (join straight onto a team, no timer, scores run on) |

**Controls (PC):** WASD move, mouse aim, left click fire, Shift Fart Dash,
Space jump, V first/third person, M menu, Tab (hold) scoreboard. Q, R and F
are kept free for later mechanics. The first PLAY of a session shows a
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
| `ReplicatedStorage.Shared.Config` | `src/shared/Config` | `GameConfig`, `FeatureFlags`, `TeamConfig`, `MapConfig`, `WeaponConfig`, `UIConfig` |
| `ReplicatedStorage.Shared.Interfaces` | `src/shared/Interfaces` | `MapBase`, `GameModeBase`: the contracts maps and modes keep |
| `ReplicatedStorage.Shared` | `src/shared` | `TeamBalance` (the team rules), `RoundClock`, `States`, `Signal` |
| `ReplicatedStorage.Remotes` | `default.project.json` | `RequestPlay`, `RequestTeam`, `RequestSpectate`, `RoundSnapshot`, `RoundUpdate`, `TeamUpdate`, `UIMessage`, `FireWeapon`, `FartDash`, `CombatEvent` |
| `ServerScriptService.Server` | `src/server` | `Bootstrap.server.luau`, `Telemetry`, `TestControls`, `Messages`, `RateLimit` |
| `ServerScriptService.Server.Services` | `src/server/Services` | the services below |
| `ServerScriptService.Server.Modes` | `src/server/Modes` | `TeamElimination`, the Phase 1 mode |
| `ServerStorage.Maps` | `src/maps` | `BrainrotBattlefield`, built from code |
| `StarterPlayerScripts.Client` | `src/client` | `ClientBootstrap`, `ClientState`, `UI` and the controllers |

The screens (`HomeScreen`, `HUD`, `ResultsScreen`, `Scoreboard`, plus
`GameMenu` and `ComingSoon`) are built in code by the client controllers
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
| `Telemetry` | structured `[FW]` logs, counters, errors per service, rejected requests by remote and reason, abnormal request rates, time to first shot / hit / elimination |
| Client controllers | `InputController`, `CameraController`, `CombatController`, `HUDController`, `HomeController`: render, capture input, switch camera, fire and dash; they never decide teams, hits or results |

`Bootstrap.server.luau` loads them in dependency order. No module requires
one that depends on it (the specs fail on a require cycle).

### Remotes

Clients only state intent: PLAY (with an optional team), a team choice or
switch, spectate, which way they're aiming, a dash. The server re-checks
state, capacity, eligibility, fire interval, payload types and a per-player
cooldown, casts every shot itself, and never accepts a hit, score, timer or
team count from a client. `RoundSnapshot` answers with the current round;
`RoundUpdate`, `TeamUpdate`, `UIMessage` and `CombatEvent` go from the
server to clients. Exact payloads are in
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
/fw weapon gasblaster    equip a weapon by id
/fw barrels              every gas barrel back, full
/fw stats                shots, hits, eliminations a minute, barrel and chain kills,
                         spawn deaths, dashes, gas recovered, rejected requests, errors
```

Or the server command bar in Studio:

```lua
local T = require(game.ServerScriptService.Server.TestControls)
T.score("Stinkers", 3); T.endPhase(5); T.reloadMap(); T.idle(game.Players.Player1, 44)
T.spawn(p); T.team(p, "sharters"); T.resetGas(p); T.gas(p, 95); T.weapon(p, "GasBlaster"); T.barrels(); T.stats()
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
| `Continuous` | continuous play behind its flag |
| `Rounds` | the state machine, scoring, draws, frozen scores, late ticks, test controls, the remotes |
| `Lifecycle` | join, PLAY, spawn, rapid PLAY, team choice, spectate, death and respawn, switching, leave, reconnect, churn |
| `ClientShell` | the home screen, PLAY, HUD, crosshair, left click, V/M/Tab/Shift, results, the AFK warning, against the real server |
| `Map` | the MapBase contract, symmetry, lanes, spawn sightlines, barrel placement, reloading |
| `TeamBalance`, `Modes`, `Structure` | the team rules, game modes and the clock, the project's shape and config |

The stand-ins have almost no physics and no rendering, so Studio stays the
final word: [`docs/phase-1-checklist.md`](docs/phase-1-checklist.md) and
[`docs/phase-2-checklist.md`](docs/phase-2-checklist.md) list what still
needs a multi-client Studio test.

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
- **Shift is Fart Dash**, open to everyone until Phase 3 adds unlocks.
  There's no sprint.
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
  puffs). There's no separate settings screen yet.

## Handoff to Phase 3: Progression & Economy

Phase 3 adds coins and XP, levels 1-50, the shop, loadouts, weapon mastery
and saving. The places it plugs into:

- `EliminationService.Eliminated(victim, killer, assists, cause, eventId)`
  is the one event for elimination, assist, chain and streak rewards; the
  event ID makes a reward idempotent.
- `EliminationService.statsOf(player)` holds eliminations, deaths and best
  streak for the save.
- `WeaponConfig` and `AbilityConfig` follow the masterplan's contracts;
  `CombatService.setWeapon` equips, and `AbilityConfig.ownership` is where
  unlocks go.
- `PlayerLifecycleService` tracks `activeSecondsThisRound`, and
  `RoundService.lastParticipation()` keeps it per round for the 5- and
  10-minute participation rewards; AFK time never counts.
- `Telemetry` already counts eliminations a minute, time to explosion,
  recovery, dashes, barrel and spawn deaths: the playtest metrics.
- `GameModeBase.new` for new modes; `MapConfig` plus `ServerStorage.Maps`
  for new maps. `RoundService` needs no change for either.

Later phases: rewards, challenges, cosmetics and monetization (4);
full-server testing, optimization and the public beta (5); new modes and
maps, prestige and seasons (6). See [`CHANGELOG.md`](CHANGELOG.md) for what changed.
