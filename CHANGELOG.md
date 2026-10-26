# Changelog

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
