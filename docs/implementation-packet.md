# Implementation packet

What the masterplan (section 1.5) asks each phase to hand over: the folder
tree, module contracts, exact remote payloads, feature flags, test cases
and known bugs. It describes the code as it is (Phases 1 and 2); update it
with the code.

## Folder tree

```
default.project.json            Rojo project (remotes are declared here)
src/
  shared/                       ReplicatedStorage.Shared
    Config/
      GameConfig.luau           rules and numbers (rounds, teams, AFK, combat, dash)
      FeatureFlags.luau         MATCH_MODE and system switches
      TeamConfig.luau           the two teams
      MapConfig.luau            maps: template, spawns, bounds, modes, theme
      WeaponConfig.luau         weapons by the masterplan's contract
      AbilityConfig.luau        abilities by the masterplan's contract (Fart Dash)
      AudioConfig.luau          sound asset IDs by name (empty = silent)
      UIConfig.luau             palette, words, key bindings, controls card
    Interfaces/
      MapBase.luau              the map contract and its validator
      GameModeBase.luau         the game-mode contract and defaults
    TeamBalance.luau            team rules (shared so the UI agrees with the server)
    RoundClock.luau             snapshot type; countdown from absolute end times
    States.luau                 player states and round phases
    Signal.luau                 in-process events
  server/                       ServerScriptService.Server
    Bootstrap.server.luau       starts everything in order
    Services/                   one module per responsibility (below)
    Modes/TeamElimination.luau  the Phase 1 mode
    Telemetry.luau              logs, counters, rejects, session metrics
    TestControls.luau           test-only commands
    Messages.luau               UIMessage sender
    RateLimit.luau              per-player request cooldowns
  maps/BrainrotBattlefield.luau ServerStorage.Maps: the code-built map
  client/                       StarterPlayerScripts.Client
    ClientBootstrap.client.luau starts the client
    ClientState.luau            snapshot, counts, state, messages
    UI.luau                     UI building helpers
    Audio.luau                  plays AudioConfig sounds
    Controllers/                Input, Camera, Combat, Effects, HUD, Home
tests/                          specs + the Roblox stand-in harness
scripts/run_specs.py            runs the specs on the Luau CLI
```

## Module contracts

Services start in this order and never require one that starts later.

| Module | Public API |
| --- | --- |
| `MapService` | `load(mapId) -> Model` (errors on a broken map), `current()`, `spawns(teamId)`, `safeSpawn(teamId, enemyPositions)`, `cameraPoints()`, signal `Loaded(model, entry)` |
| `MatchScoreService` | `reset()`, `open(mode, context, endsAt)`, `closeAt(t)`, `freeze()`, `isOpen()`, `getScores()`, `recordElimination(event) -> boolean`, `testAddElimination(team, n)`, signal `Changed` |
| `TeamService` | `start()`, `assign(player, preferred?) -> (team?, why)`, `release(player)`, `switch(player, to) -> boolean`, `counts()`, `activeCount()`, `teamOf(player)`, `members(team)`, `friendCounts(player)`, `testSetTeam(player, team)`, signal `Changed` |
| `PlayerLifecycleService` | `start()`, `get(player) -> Runtime?`, `stateOf(player)`, `requestPlay(player, preferred?)`, `requestTeam(player, team?)`, `requestSpectate(player)`, `toSpectator(player, state)`, `respawn(player)`, `respawnAll()`, `isProtected(player)`, `endProtection(player)`, `beginRound(id)`, `accrue(seconds)`, `finishRound()`, signals `StateChanged(player, state?, previous?)`, `Spawned(player, character)`, `Died(player, character)` |
| `AFKService` | `start()`, `check(now)`, `markActive(player)` |
| `EliminationService` | `start()`, `eliminate(victim, character, { killer?, killerTeam?, victimTeam?, assists?, cause }) -> eventId?`, `streakOf(player)`, `bestStreakOf(player)`, `statsOf(player)`, signal `Eliminated(victim, killer?, assists, cause, eventId)` |
| `GasService` | `start()`, `add(victim, amount, { attacker?, team?, cause, chainDepth? }) -> boolean`, `gasOf(player)`, `isExploding(player)`, `explode(player)`, `stageOf(gas)`, `tick(dt)`, `reset(player)`, `testSetGas(player, value)`, signal `Exploded(victim, position, killer?, chainDepth, killerTeam?)` |
| `CombatService` | `start()`, `fire(player, direction, shotId)`, `weaponOf(player)`, `setWeapon(player, id)`, signal `PartHit(shooter, part, weapon, from)` |
| `ExplosionService` | `start()`, `blast({ position, radius, gas, owner?, ownerTeam, cause, depth, source? })`, `step()`, `pending()`, `blocked(from, to)`, signal `Blasted(blast)` |
| `BarrelService` | `start()`, `shoot(shooter, part, amount) -> boolean`, `get(model)`, `all()`, `resetAll()` |
| `DashService` | `start()`, `dash(player, direction) -> boolean` |
| `RoundService` | `start()`, `step(now)`, `phase()`, `snapshot()`, `getMode()`, `lastParticipation()`, `testEndPhaseIn(seconds)`, signal `PhaseChanged(phase, snapshot)` |
| `Telemetry` | `log(service, event, fields)`, `count(key, n)`, `error(service, err)`, `guard(service, fn)`, `reject(remote, player, reason)`, `isFlagged(player)`, `joined/left(player)`, `first(player, kind)`, `time(kind, seconds)`, `snapshot()` |
| `MapBase` | `validate(model, entry, teamIds) -> (ok, problems)`, `spawns(model, entry, teamId)`, `cameraPoints(model)`, `resolve(model, path)`, `isDefinition(value)` |
| `GameModeBase` | `new(definition) -> GameMode`, `mostPointsWins(scores, teamIds)`; a mode has `id`, `displayName`, `roundSeconds`, `intermissionSeconds`, `validateScoreEvent`, `computeResult`, `onRoundStart`, `onRoundEnd` |
| `TeamBalance` | `choose(counts, order, max, { preferred?, friends?, scores? }) -> (team?, why)`, `bestTeams`, `preferenceAllowed`, `canSwitch`, `canStart`, `spread`, `spreadAfterJoin` |

## Remotes and payloads

All in `ReplicatedStorage.Remotes`. Every client request is checked on the
server and rate-limited; a refused one is counted in Telemetry with a
reason.

| Remote | Direction | Payload |
| --- | --- | --- |
| `RequestPlay` | client → server | `preferredTeam: string?` (`"Stinkers"` / `"Sharters"`; anything else is ignored) |
| `RequestTeam` | client → server | `team: string?`: on the home screen, the choice for PLAY (nil = auto); in a match, a switch |
| `RequestSpectate` | client → server | none |
| `FireWeapon` | client → server | `direction: Vector3` (unit, from the head toward the crosshair), `shotId: number` (an integer, counting up per shot) |
| `FartDash` | client → server | `direction: Vector3` (horizontal) |
| `RoundSnapshot` | client → server (RemoteFunction) | none; returns the snapshot below |
| `RoundUpdate` | server → all | snapshot: `{ roundId, phase, phaseStartTime, phaseEndTime?, scoresByTeam, activePlayersByTeam, result?, mode, matchMode, map, serverTime }`; `result = { winner?, draw, scores }` |
| `TeamUpdate` | server → all | `{ counts = { Stinkers, Sharters }, maxTeamSize }` |
| `UIMessage` | server → one | `{ kind, text, ... }`: `afkWarning` (+`detail`, `endsAt`), `afkClear`, `afkMoved`, `teamFull`, `team` (+`team`), `denied`, `test` |
| `CombatEvent` | server → all / one | `{ kind = "shot", shooter, from, to }` (all), `{ kind = "hit", victim, gas, headshot, blocked }` (shooter), `{ kind = "damaged", attacker, from }` (victim), `{ kind = "explosion", victim, position, killer? }` (all), `{ kind = "elimination", event, victim, killer?, team?, assists, cause }` (all), `{ kind = "dash", player, from, direction }` (all), `{ kind = "alpha", player, text }` (all), `{ kind = "barrel", position }` (all); players as user IDs |

Rejection reasons: `rateLimited`, `badPayload`, `notActive`, `dead`,
`tooFast`, `duplicate`, `exploding`, `prohibited`, `cooldown`, `tooFar`,
`disabled`.

Player attributes the server sets: `State`, `TeamId`, `PreferredTeam`,
`Weapon`. Character attributes: `ProtectedUntil`, `Gas` (0-100),
`GasStage` (0-4), `ExplodesAt` (server time). Gas barrel attributes:
`Health`, `Ready`, `FuseAt` (server time).

## Feature flags

`src/shared/Config/FeatureFlags.luau`:

| Flag | Default | Effect |
| --- | --- | --- |
| `MATCH_MODE` | `"Rounds"` | `"Rounds"`: 5-minute rounds, 15-second results. `"Continuous"`: one endless match, joining is PLAY |
| `GAS_COMBAT` | on | the Gas Blaster, gas meter and explosions |
| `FART_DASH` | on | Shift dash (unlocks arrive in Phase 3) |
| `SPAWN_PROTECTION` | on | 3 seconds after each spawn, ended by firing |
| `TEAMMATE_HIGHLIGHTS` | on | teammates outlined |
| `DEBUG_LOGS` | on | `[FW]` lines in the output |

`GameConfig.TEST_CONTROLS.ENABLED` turns the test commands on or off.

## Test cases

`python3 scripts/run_specs.py` runs them all. Each spec's header lists what
it proves.

| Spec | Masterplan / Phase 1 plan items |
| --- | --- |
| `Combat` | 1.3 respawn rules, friendly fire, spawn protection; 1.4 remote validation, rate limits, line of sight, observability, test commands; 1.5 two clients fight, no spawn kills, respawn after repeated deaths; 2.1 server-validated hits, duplicate packets; 2.5 hit registration, cooldown exploits, team immunity |
| `Gas` | 2.2 stages, clamping, recovery and interruption, 99 to 100, simultaneous hits, disconnects mid-countdown; 2.3 one kill per explosion, killer and assists |
| `Streak` | 2.4 the five-kill call, once, reset on death, rate-limited; inflation visuals and the effect pool |
| `Chaos` | 2.3 chain reactions, depth limit, per-tick budget, friendly fire off, barrels (health, fuse, radius, respawn, attribution); 2.5 barrel-player-barrel chains, kill attribution |
| `Continuous` | 1.1 continuous core loop behind its flag |
| `Lifecycle` | 1.3 joining, spawning, churn without duplicate avatars or bad counts |
| `QAMatrix` | the Phase 1 plan's QA matrix |
| `Rounds` | rounds, scoring, draws, late ticks, the remote surface |
| `Map` | 1.2 footprint, lanes and cross-links, symmetry, spawn sightlines, barrel placement |
| `TeamBalance` | 1.3 smaller-team joins, deterministic ties, fair switches |
| `ClientShell` | 1.4 PC input, HUD, camera, menus |
| `Modes`, `Structure` | contracts, config, flags, weapon contract, no require cycles |

## Known bugs and limits

- No lag compensation: the server casts shots against where players are
  now, so a high-ping shooter can miss a fast mover they had on target.
  Phase 5 covers network fairness.
- The spec harness casts rays against bounding boxes, so round cover is a
  little "boxier" in the specs than in Studio.
- Chat test commands use `Player.Chatted`; if TextChatService doesn't
  deliver them, use the command bar.
- Sounds are empty `AudioConfig` slots until real assets are uploaded.
- Third-person aim follows the free mouse cursor; a shoulder camera may
  feel better and is worth trying in playtests.
- Not yet verified in Studio: everything above passes in the spec harness
  only. The checklist lists the Studio runs still needed.
