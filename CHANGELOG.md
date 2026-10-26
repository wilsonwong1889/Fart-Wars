# Changelog

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
