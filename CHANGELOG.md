# Changelog

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
