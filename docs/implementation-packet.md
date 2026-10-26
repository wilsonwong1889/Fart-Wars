# Implementation packet

What the masterplan (section 1.5) asks each phase to hand over: the folder
tree, module contracts, exact remote payloads, feature flags, test cases
and known bugs. It describes the code as it is (Phases 1-3); update it
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
      WeaponConfig.luau         weapons by the masterplan's contract, with handling, price and level
      AbilityConfig.luau        abilities by the masterplan's contract (Fart Dash, the Q abilities)
      ProgressionConfig.luau    coin and XP grants, the level curve, unlocks, mastery, limits
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
    Telemetry.luau              logs, counters, rejects, flags, session metrics
    Moderation.luau             acts on flags; banned players
    TestControls.luau           test-only commands (and /fw selftest)
    Messages.luau               UIMessage sender
    RateLimit.luau              per-player request cooldowns
    Cadence.luau                interval limits that hold over time (shots, dash, Q)
  maps/BrainrotBattlefield.luau ServerStorage.Maps: the code-built map
  client/                       StarterPlayerScripts.Client
    ClientBootstrap.client.luau starts the client
    ClientState.luau            snapshot, counts, state, messages
    Settings.luau               the player's Settings choices (effects, sound, tips)
    UI.luau                     UI building helpers
    Audio.luau                  plays AudioConfig sounds
    Controllers/                Input, Camera, Combat, Effects, HUD, Progress, Locker, Tips, Home
tests/                          specs + the Roblox stand-in harness
scripts/run_specs.py            runs the specs on the Luau CLI
```

## Module contracts

Services start in this order and never require one that starts later.

| Module | Public API |
| --- | --- |
| `DataService` | `start()`, `get(player) -> Profile?` (`{ data, temporary, dirty, lost }`), `isLoaded(player)`, `update(player, fn(data)) -> boolean`, `save(player) -> boolean`, `saveAll()` (shutdown), `defaults()`, `migrate(old) -> Data`, `probe() -> (ok, why)` (a scratch round trip), `setStore(store)` (specs), signal `Loaded(player, profile)` |
| `MapService` | `load(mapId) -> Model` (errors on a broken map), `current()`, `spawns(teamId)`, `safeSpawn(teamId, enemyPositions)`, `cameraPoints()`, signal `Loaded(model, entry)` |
| `MatchScoreService` | `reset()`, `open(mode, context, endsAt)`, `closeAt(t)`, `freeze()`, `isOpen()`, `getScores()`, `recordElimination(event) -> boolean`, `testAddElimination(team, n)`, signal `Changed` |
| `TeamService` | `start()`, `assign(player, preferred?) -> (team?, why)`, `release(player)`, `switch(player, to) -> boolean`, `counts()`, `activeCount()`, `teamOf(player)`, `members(team)`, `friendCounts(player)`, `areFriends(a, b)`, `testSetTeam(player, team)`, signal `Changed` |
| `PlayerLifecycleService` | `start()`, `get(player) -> Runtime?`, `stateOf(player)`, `requestPlay(player, preferred?)`, `requestTeam(player, team?)`, `requestSpectate(player)`, `toSpectator(player, state)`, `respawn(player)`, `respawnAll()`, `isProtected(player)`, `endProtection(player)`, `beginRound(id)`, `accrue(seconds)`, `finishRound()`, signals `StateChanged(player, state?, previous?)`, `Spawned(player, character)`, `Died(player, character)`, `Leaving(player, character?)`, `Replacing(player, character)` |
| `AFKService` | `start()`, `check(now)`, `markActive(player)` |
| `EliminationService` | `start()`, `eliminate(victim, character, { killer?, killerTeam?, victimTeam?, assists?, cause, weapon? }) -> eventId?`, `streakOf(player)`, `bestStreakOf(player)`, `statsOf(player)`, signals `Eliminated({ event, victim, killer?, assists, cause, weapon?, counted })`, `Alpha(player, eventId)` |
| `GasService` | `start()`, `add(victim, amount, { attacker?, team?, cause, chainDepth?, weapon? }) -> boolean`, `vent(player, amount) -> number`, `gasOf(player)`, `isExploding(player)`, `explode(player)`, `stageOf(gas)`, `tick(dt)`, `reset(player)`, `testSetGas(player, value)`, signal `Exploded(victim, position, killer?, chainDepth, killerTeam?)` |
| `CombatService` | `start()`, `fire(player, direction, shotId)`, `weaponOf(player)`, `setWeapon(player, id)`, signals `PartHit(shooter, part, weapon, from)`, `Lobbed(shooter, from, direction, weapon)` |
| `ExplosionService` | `start()`, `blast({ position, radius, gas, owner?, ownerTeam, cause, depth, source?, weapon? })`, `step()`, `pending()`, `blocked(from, to)`, signal `Blasted(blast)` |
| `BarrelService` | `start()`, `shoot(shooter, part, amount) -> boolean`, `get(model)`, `all()`, `resetAll()` |
| `DashService` | `start()`, `dash(player, direction) -> boolean` |
| `AbilityService` | `start()`, `use(player) -> boolean`, `setAbility(player, id?)`, `abilityOf(player)` |
| `ProjectileService` | `start()`, `throw(player, from, direction, weapon)`, `arc(from, direction, weapon, ignore) -> (landing, flight, path)`, `step()`, `cloudCount()` |
| `EconomyService` | `start()`, `grant(player, id, reason, coins, xp) -> boolean`, `spend(player, id, reason, coins) -> boolean`, `refund(player, id, coins)`, `xpToNext(data)`, `publish(player)`, `tick(dt)`, `activeSecondsOf(player)`, `testGrant(player, coins, xp)`, signal `Changed(player)` |
| `LoadoutService` | `start()`, `resolve(data) -> (weapon, ability?, cosmetic?)`, `apply(player)`, `equip(player, kind, id?) -> (ok, "now" / "respawn" / reason)`, `view(player)`, `push(player)`, `testGive(player, kind, id)` |
| `ExperimentService` | `start()`, `assign(player)`, `variant(player, key) -> string?`, `value(player, key)`, `weaponPrice(player, price)`, `track(player, metric, n?)`, `tick(dt)`, `setConfig(config)` (tests) |
| `SocialService` | `start()`, `squadmate(player) -> Player?`, `coplayed(player)`, `tick(dt)` |
| `ShopService` | `start()`, `buy(player, weaponId) -> Result`, `request(player, action, kind, id?) -> Result` (`{ ok, reason, message, profile? }`) |
| `RoundService` | `start()`, `step(now)`, `phase()`, `snapshot()`, `getMode()`, `lastParticipation()`, `testEndPhaseIn(seconds)`, signal `PhaseChanged(phase, snapshot)` |
| `Telemetry` | `log(service, event, fields)`, `count(key, n)`, `error(service, err)`, `guard(service, fn)`, `reject(remote, player, reason)`, `isFlagged(player)`, `joined/left(player)`, `first(player, kind)`, `time(kind, seconds)`, `sample(kind, value)`, `flag(player, reason, detail?)`, `snapshot()`, signal `Flagged(player, reason, detail?)` |
| `Moderation` | `start()`, `flagsOf(player)`; config `GameConfig.MODERATION` (`KICK_AT_FLAGS`, `BANNED_USER_IDS`) |
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
| `UseAbility` | client → server | none (the equipped Q ability) |
| `Emote` | client → server | none (the equipped emote; one every 3 s) |
| `RewardsRequest` | client → server (RemoteFunction) | `action: "status" \| "claimDaily" \| "spin"`; returns `{ ok, reason, message, ... }` (status: `day`, `ready`, `spins`, `giftsLeft`, `nextGiftSeconds`, `secondsToReset`, `saving`; a claim: `day`, `coins`, `spins?`, `cosmetic?`; a spin: `prize`, `label`, `coins`, `xp`, `cosmetic?`) |
| `ShopRequest` | client → server (RemoteFunction) | `action: "buy" \| "equip" \| "profile"`, `kind: "weapon" \| "ability" \| "cosmetic" \| "all"`, `id: string?` (40 characters at most); returns `{ ok, reason, message, profile? }` |
| `RoundSnapshot` | client → server (RemoteFunction) | none; returns the snapshot below |
| `RoundUpdate` | server → all | snapshot: `{ roundId, phase, phaseStartTime, phaseEndTime?, scoresByTeam, activePlayersByTeam, result?, mode, matchMode, map, serverTime }`; `result = { winner?, draw, scores }` |
| `TeamUpdate` | server → all | `{ counts = { Stinkers, Sharters }, maxTeamSize }` |
| `UIMessage` | server → one | `{ kind, text, ... }`: `afkWarning` (+`detail`, `endsAt`), `afkClear`, `afkMoved`, `teamFull`, `team` (+`team`), `denied`, `test` |
| `ProfileUpdate` | server → one | `{ ownedWeapons, equippedWeapon, unlockedAbilities, equippedAbility?, ownedCosmetics, equippedCosmetic?, badges, mastery = { [weapon] = { eliminations, claimed } }, stats = { eliminations, deaths, bestStreak, playtime, lifetimeXP }, pending, saving }` |
| `ProgressEvent` | server → one | `{ kind = "grant", id, reason, coins, xp }`, `{ kind = "levelUp", level, unlocks = { text }, coins, repeated? }`, `{ kind = "mastery", weapon, badge, eliminations, coins }`; reasons: `elimination`, `assist`, `chainBonus`, `alpha`, `participation`, `levelCap`, `levelCapRepeat`, `mastery`, `test` |
| `CombatEvent` | server → all / one | `{ kind = "shot", shooter, from, to }` (all), `{ kind = "hit", victim, gas, headshot, blocked }` (shooter), `{ kind = "damaged", attacker, from }` (victim), `{ kind = "explosion", victim, position, killer? }` (all), `{ kind = "elimination", event, victim, killer?, team?, assists, cause }` (all), `{ kind = "dash", player, from, direction }` (all), `{ kind = "alpha", player, text }` (all), `{ kind = "barrel", position }` (all), `{ kind = "lob", shooter, from, to, path, flight }` (all), `{ kind = "cloud", position, radius, endsAt, team }` (all), `{ kind = "ability", player, ability, position }` (all); players as user IDs |

Rejection reasons: `rateLimited`, `badPayload`, `notActive`, `dead`,
`tooFast`, `duplicate`, `exploding`, `prohibited`, `cooldown`, `tooFar`,
`disabled`, `notEquipped`, `noGas`, `throughWall`. Shop answers (`reason`): `bought`,
`now`, `respawn`, `profile`, `busy`, `loading`, `notSaving`, `unknown`,
`owned`, `level`, `coins`, `saveFailed`, `notOwned`, `badPayload`,
`rateLimited`.

Player attributes the server sets: `State`, `TeamId`, `PreferredTeam`,
`Weapon`, `Coins`, `Level`, `XP` (toward the next level), `XPToNext`,
`LifetimeXP`, `DataStatus` (`loading`, `ready`, `unsaved`), `Ability`,
`AbilityReadyAt` (server time), `Tracer` (cosmetic id), `LoadoutPending`. Character attributes: `ProtectedUntil`, `Gas` (0-100),
`GasStage` (0-4), `ExplodesAt` (server time). Gas barrel attributes:
`Health`, `Ready`, `FuseAt` (server time).

## Feature flags

`src/shared/Config/FeatureFlags.luau`:

| Flag | Default | Effect |
| --- | --- | --- |
| `MATCH_MODE` | `"Rounds"` | `"Rounds"`: 5-minute rounds, 15-second results. `"Continuous"`: one endless match, joining is PLAY |
| `GAS_COMBAT` | on | the Gas Blaster, gas meter and explosions |
| `FART_DASH` | on | Shift dash, everyone's |
| `PROGRESSION` | on | coins, XP and levels; off pays nothing (stats and saving carry on), for combat-only playtests |
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
| `Data` | 3.4 DataStore retries and backoff, session locking, autosave, leave and shutdown saves, versioned migrations, partial saves, failed writes, concurrent joins; 3.5 DataStore outages, invalid equipped items |
| `Economy` | 3.1 grants with unique IDs, no double awards, limits, audit ledger, source breakdowns, idle farming, anomalous gains; 3.2 levels 1-50, unlocks, cap and repeat rewards, lifetime XP, rewards never lost; 3.4 mastery once per milestone; 3.5 repeated reward triggers, max level, HUD |
| `Soak` | 2.5 the 20-player test (errors, memory, invariants) as far as a stand-in goes; 1.3 churn with every system on |
| `Arsenal` | 3.3 playstyles (rate, range, handling, area denial), abilities with cooldown trade-offs and counterplay, one ability at a time |
| `Shop` | 3.3 server-checked purchases, ownership saved before the UI confirms, loadouts validated and applied on respawn; 3.5 interrupted purchases, pending purchase states, the menu |
| `Continuous` | 1.1 continuous core loop behind its flag |
| `Lifecycle` | 1.3 joining, spawning, churn without duplicate avatars or bad counts |
| `QAMatrix` | the Phase 1 plan's QA matrix |
| `Rounds` | rounds, scoring, draws, late ticks, the remote surface |
| `Map` | 1.2 footprint, lanes and cross-links, symmetry, spawn sightlines, barrel placement |
| `TeamBalance` | 1.3 smaller-team joins, deterministic ties, fair switches |
| `ClientShell` | 1.4 PC input, HUD, camera, menus |
| `Modes`, `Structure` | contracts, config, flags, weapon contract, no require cycles |

## Metrics

Beyond the per-service counters, `/fw stats` (and its JSON) has what the
masterplan asks to measure: `firsts.shot`, `.hit`, `.elimination`,
`.coins`, `.levelUp`, `.purchase` (seconds into a session), `session`
(length), `session.joins` and `session.returning` (the return rate, with
`samples.daysSinceLastVisit`), `session.reached5Minutes` /
`reached10Minutes` (the first-ten-minutes rate), `Shop.firstPurchases`
(the first purchase rate), `samples.coinsPer10Minutes` and
`samples.unspentCoins` (inflation), `Economy.coins.<reason>` and
`Economy.xp.<reason>` (sources), and `flags.<reason>` (moderation).

Retention and Phase 4: `retention.newPlayers`, `.nextDay`, `.D1`, `.D7`;
`Rewards.dailyClaims`, `.gifts`, `.spins`; `Store.purchases`,
`Store.bought.<product>`, `Store.passGranted.<pass>`; `social.squadBonuses`,
`.welcomes`, `.sessionsWithFriend`, `.friendCoplaySeconds`,
`.leftWithFriend` / `.leftSolo`; and per experiment cohort
`exp.<key>.<variant>.sessions`, `.newPlayers`, `.returning`,
`.returnedNextDay`, `.D1`, `.D7`, `.reached10Minutes`, `.activeMinutes`.

## Save format

One DataStore, `FartWarsProfiles`, key `player_<UserId>`. `SaveVersion` 1:

| Field | Type | Notes |
| --- | --- | --- |
| `Coins` | number | spendable |
| `XP` | number | toward the next level (at 50, toward the next repeat reward) |
| `Level` | number | 1-50 |
| `LifetimeXP` | number | every XP point ever earned |
| `TotalEliminations`, `TotalDeaths`, `BestStreak` | number | lifetime stats |
| `OwnedWeapons` | { string } | always includes `GasBlaster` |
| `EquippedWeapon` | string | an owned weapon, else the default on load |
| `UnlockedAbilities`, `OwnedCosmetics`, `Badges` | { string } | |
| `EquippedAbility`, `EquippedCosmetic` | string? | cleared on load if not owned |
| `WeaponMastery` | { [weaponId]: { Eliminations, Claimed: { milestone } } } | |
| `TotalPlaytime` | number | active seconds |
| `CapRewards` | number | repeat rewards paid past level 50 |
| `Ledger` | { { id, reason, coins, xp, at } } | the last 20 transactions |
| `Sessions`, `FirstSeen`, `LastSeen` | number | visits (os.time), for the return rate |
| `DailyTrack`, `LastDailyDay`, `DailyClaims` | number | the daily track's position (claims so far), the UTC day of the last claim |
| `Spins`, `SpinsUsed`, `GiftDay`, `GiftsToday` | number | free spins banked and used (the spin's grant ID), today's gifts |
| `EquippedTrail`, `EquippedEmote` | string? | the Fart Dash trail and emote slots (`EquippedCosmetic` is the tracer) |
| `Receipts`, `PassesGranted` | { string } | the latest 100 purchase IDs paid, the passes whose contents were given |
| `SquadDay`, `SquadToday` | number | the UTC day and count of today's squad bonuses |
| `WelcomedBy` | number | the friend (user ID) who welcomed this player; 0 if nobody yet |
| `WelcomedFriends`, `WelcomeDay`, `WelcomesToday` | { number }, number, number | newcomers this player has welcomed (the latest 50), today's welcomes |
| `Lock` | { Job, At }? | the server holding the profile; absent when free |

A new field gets a default in `DataService.defaults()`; `migrate` fills it
in for older saves. Bump `VERSION` only for a change `migrate` must handle
specially; an older server never writes a newer save.

## Rules worth knowing when changing combat or saving

- **Rates:** shots, Fart Dash and Q go through `Cadence`: a bucket that
  refills one use per interval and holds a little slack for network
  jitter. Bunched honest requests pass; over time nobody beats the
  interval. Don't go back to a per-gap check (it let a steady 15% faster
  rate through).
- **Credit:** the killer is the last enemy to add gas, if they did so in
  the last `GAS.ASSIST_WINDOW_SECONDS`; an empty meter forgets its
  attackers. Leaving, a team switch, any respawn (`Replacing`) or any
  other death mid-countdown explodes the player; a death while gassed
  (Reset is off on the client, but a fall) is credited to the recent
  attacker. Gas from someone now on the victim's team is refused.
- **Saving:** one write per profile at a time, each taking the profile as
  it is when it reaches the DataStore; nothing writes after the release;
  shutdown waits for releases and loads already under way.

## Known bugs and limits

- No lag compensation: the server casts shots against where players are
  now, so a high-ping shooter can miss a fast mover they had on target.
  Phase 5 covers network fairness.
- The spec harness casts rays against bounding boxes, so round cover is a
  little "boxier" in the specs than in Studio.
- Chat test commands are a TextChatService command (`/fw`, `!fw`) and
  `Player.Chatted` for legacy chat; if neither delivers them, use the
  command bar. `/fw selftest` says which one is in use.
- Sounds are empty `AudioConfig` slots until real assets are uploaded.
- The Stink Lobber has no arc preview: aim higher to throw farther. Worth
  adding if playtesters struggle to place bombs.
- A stink bomb's flight is worked out when it's thrown; it lands where the
  arc met something then, even if that player has since moved.
- Third-person aim follows the free mouse cursor; a shoulder camera may
  feel better and is worth trying in playtests.
- Saving is only proven against a stand-in DataStore in the specs; a real
  DataStore run (Studio with API access, then a live server) is on the
  Phase 3 checklist.
- Participation is per session: rejoining starts the 5- and 10-minute
  clock again (the time still has to be played).
- Not yet verified in Studio: everything above passes in the spec harness
  only. The checklists list the Studio runs still needed.
