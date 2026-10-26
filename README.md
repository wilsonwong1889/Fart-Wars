# Fart-Wars

**Fart Wars** is a Roblox team game: the **Skibidi Stinkers** (toxic green)
against the **Sigma Sharters** (bright yellow) on the Brainrot Battlefield.

This repository holds **Phase 1**: the foundation and the first playable
internal prototype. Two or more players join a running server, press PLAY,
land on balanced teams, move around a symmetrical three-lane map, play a
five-minute round, see a win or draw, wait out a 15-second intermission and
go straight into the next round, with no server restart. Combat, gas
damage, coins, the jackpot, the shop and MVP arrive in later phases; until
then, test-only controls supply the eliminations that decide a round.

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

**Controls (PC):** WASD move, Shift sprint, Space jump, V first/third
person, M menu, Tab (hold) scoreboard. Q, R and F are kept free for later
mechanics. The first PLAY of a session shows a small controls card; there's
no tutorial.

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
| `ReplicatedStorage.Shared.Config` | `src/shared/Config` | `GameConfig`, `TeamConfig`, `MapConfig`, `UIConfig` |
| `ReplicatedStorage.Shared.Interfaces` | `src/shared/Interfaces` | `MapBase`, `GameModeBase`: the contracts maps and modes keep |
| `ReplicatedStorage.Shared` | `src/shared` | `TeamBalance` (the team rules), `RoundClock`, `States`, `Signal` |
| `ReplicatedStorage.Remotes` | `default.project.json` | `RequestPlay`, `RequestTeam`, `RequestSpectate`, `RoundSnapshot`, `RoundUpdate`, `TeamUpdate`, `UIMessage` |
| `ServerScriptService.Server` | `src/server` | `Bootstrap.server.luau`, `TestControls`, `Messages`, `RateLimit` |
| `ServerScriptService.Server.Services` | `src/server/Services` | the six services below |
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
| Client controllers | `InputController`, `CameraController`, `HUDController`, `HomeController`: render, capture input, switch camera; they never decide teams or results |

`Bootstrap.server.luau` loads them in dependency order. No module requires
one that depends on it (the specs fail on a require cycle).

### Remotes

Clients only state intent: PLAY (with an optional team), a team choice or
switch, spectate. The server re-checks state, capacity, eligibility and a
per-player cooldown, and never accepts a score, timer or team count from a
client. `RoundSnapshot` answers with the current round; `RoundUpdate`,
`TeamUpdate` and `UIMessage` go from the server to clients.

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
- **Barrels** are decoration only for now.
- `Zones` marks the lanes and spawn areas, `CameraPoints` holds the home
  screen's fixed views, and `Bounds` is the playable box.

To replace it with a map built in Studio, put a Model named
`BrainrotBattlefield` in `ServerStorage.Maps` (and remove the module) with
`Spawns/Stinkers`, `Spawns/Sharters`, `CameraPoints` and `Bounds` as
described in `src/shared/Interfaces/MapBase.luau`. MapService sets the
SpawnLocations up for their teams and refuses a map that breaks the
contract. A new map is a `MapConfig` entry plus its template.

## Test-only controls

Phase 1 has no combat, so these exercise the round system. They run on the
server only. In Studio anyone can use them; in a live server, only the user
IDs in `GameConfig.TEST_CONTROLS.USER_IDS` (empty by default). **Set
`GameConfig.TEST_CONTROLS.ENABLED` to `false` before any public release.**

Chat (`/fw` or `!fw`):

```
/fw score stinkers 3     three eliminations for a team (stinkers/green, sharters/yellow)
/fw end 5                end the current round or intermission in 5 seconds
/fw reloadmap            rebuild the map; active players respawn on it
/fw idle 44              count yourself as idle for 44 seconds (to see the AFK warning)
```

Or the server command bar in Studio:

```lua
local T = require(game.ServerScriptService.Server.TestControls)
T.score("Stinkers", 3); T.endPhase(5); T.reloadMap(); T.idle(game.Players.Player1, 44)
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
| `Rounds` | the state machine, scoring, draws, frozen scores, late ticks, test controls, the remotes |
| `Lifecycle` | join, PLAY, spawn, rapid PLAY, team choice, spectate, death and respawn, switching, leave, reconnect |
| `ClientShell` | the home screen, PLAY, HUD, V/M/Tab/Shift, results, the AFK warning, against the real server |
| `Map` | the MapBase contract, symmetry, lanes, spawn sightlines, reloading |
| `TeamBalance`, `Modes`, `Structure` | the team rules, game modes and the clock, the project's shape and config |

The stand-ins have almost no physics and no rendering, so Studio stays the
final word: the checklist in [`docs/phase-1-checklist.md`](docs/phase-1-checklist.md)
lists what still needs a multi-client Studio test.

For type checking against the Roblox API, use
[luau-lsp](https://github.com/JohnnyMorganz/luau-lsp):

```
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --platform roblox --sourcemap sourcemap.json \
  --definitions @roblox=globalTypes.d.luau src
```

## Phase 1 decisions

Where the plan left room, Phase 1 does this:

- **A round needs an opponent.** Besides the 2-player minimum, each team
  needs at least one active player, so a 2v0 left behind by leavers waits
  instead of starting a round with no enemy. Nobody is moved: anyone on the
  bigger team can switch (M → SWITCH TEAM), and new joiners fill the empty
  team.
- **Switching only evens teams.** A voluntary switch is allowed when it
  narrows the gap (3v1 → 2v2), never when it only flips it (2v1 → 1v2).
- **Activity is movement the server sees.** An avatar has to travel 6
  studs across the ground; jumping or turning on the spot, held keys and
  remote pings don't count. Server systems can call
  `AFKService.markActive` (Phase 2 weapons should).
- **Every round starts from the spawns.** All active players respawn at
  their team's spawn when a round starts. A death respawns after 3 seconds
  at the team's spawn farthest from enemies.
- **Spectators watch from fixed views**, never from another player's eyes,
  so nothing tactical leaks to someone about to press PLAY.
- **The map is code.** That keeps it reviewable in Git; a Studio model with
  the same name replaces it.

## Handoff to Phase 2: Combat & Chaos

Phase 2 adds the Gas Blaster, gas, inflation, respawns, spawn protection,
Fart Dash and combat feedback. The places it plugs into:

- `MatchScoreService.recordElimination({ team, source = "elimination", killer, victim })`;
  `TeamElimination` already validates killer and victim teams.
- `MapService` SpawnLocations have `Duration = 0`; spawn protection goes
  there or in `PlayerLifecycleService`'s spawn.
- `AFKService.markActive(player)` for shots and abilities.
- `GameModeBase.new` for new modes; `MapConfig` plus `ServerStorage.Maps`
  for new maps. `RoundService` needs no change for either.
- `PlayerLifecycleService` tracks `activeSecondsThisRound`, and
  `RoundService.lastParticipation()` keeps it per round for the 60-second
  completion rewards.

Later phases (not Phase 1): progression, weapons, abilities and saving;
rewards, jackpot, challenges and cosmetics; full-server testing, anti-cheat
and the public beta. See [`CHANGELOG.md`](CHANGELOG.md) for what changed.
