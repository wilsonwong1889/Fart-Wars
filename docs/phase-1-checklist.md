# Phase 1 checklist

The Phase 1 plan's sign-off list and QA matrix, and the masterplan's Phase 1
acceptance scenarios, with where each one is checked.
"Spec" means `python3 scripts/run_specs.py` covers it without Studio;
"Studio" means it still needs a run in Studio (the spec harness has no
physics, rendering, chat service or real network).

## Sign-off

- [ ] Private Roblox experience created and source controlled. *Studio: the
      place, Max Players 20, private; this repository is the source.*
- [x] Modular services load without errors. *Spec: Structure (every module,
      no require cycles), every server spec boots through `Bootstrap`.*
- [x] Symmetrical three-lane map playable with safe team spawns. *Spec:
      Map. Studio: walk every lane and gap, check collisions and camera
      angles.*
- [x] Balanced team assignment works for 2-20 players. *Spec: TeamBalance,
      QAMatrix.*
- [x] Menu spectator → PLAY → active → spectator flow works. *Spec:
      Lifecycle, ClientShell.*
- [x] Five-minute round and 15-second intermission run repeatedly. *Spec:
      Rounds (six rounds on one server).*
- [x] Server-authoritative score stub, winner and draw results work. *Spec:
      Rounds, QAMatrix.*
- [x] Join-in-progress, AFK and camera controls work. *Spec: QAMatrix,
      ClientShell. Studio: the feel of V and the spectator views.*
- [ ] All QA matrix cases pass. *Spec rows below pass; the Studio rows need
      a multi-client session.*
- [x] Combat implementation can begin without replacing the foundation.
      *See "Handoff to Phase 2" in the README.*

## QA matrix

| Test | Expected | Spec | Studio |
| --- | --- | --- | --- |
| 2 clients join | 1v1 starts | QAMatrix | 2-player Clients and Servers |
| 6 clients join | 3v3 | QAMatrix | 6-player session |
| 20 clients join | 10v10, no extra active slots | QAMatrix | 20-player session (performance) |
| 21st connection | the server cap stops it | config only | try a 21st client against Max Players 20 |
| Mid-round join | joins the match, same timer | QAMatrix | |
| One team empties | round completes; next waits | QAMatrix, Rounds | |
| Equal score at timeout | draw, no winner | QAMatrix, Rounds | |
| AFK 45/60 seconds | warning, then spectator; slot freed | QAMatrix, ClientShell | stand still for a minute |
| Return from AFK | PLAY rechecks team, joins match | QAMatrix | |
| Switch V repeatedly | toggles without breaking controls | ClientShell | mash V while moving and in the M menu |
| Rapid PLAY requests | no duplicate avatars or slots | QAMatrix, Lifecycle | spam-click PLAY |
| Timer under lag | round stays 300 s; clients resync | QAMatrix, Rounds | Studio network simulation (incoming replication lag) |
| Map reload / test restart | spawn references resolve | QAMatrix, Map | `/fw reloadmap` mid-round |

## Masterplan Phase 1 acceptance (section 1.5)

| Scenario | Spec | Studio |
| --- | --- | --- |
| Two local test clients spawn on opposite teams; both can move, see enemies and use the starter placeholder attack | Combat, ClientShell | 2-player session: shoot each other across a lane |
| Joining and leaving repeatedly never duplicates character controllers or corrupts team counts | Lifecycle (churn), QAMatrix | join/leave a client several times |
| No enemy can spawn-kill an invulnerable player; respawn works after repeated deaths | Combat | camp a spawn exit with the blaster |
| Friendly fire off on every damage path | Combat | shoot a teammate |
| Remotes with strict payloads, rate limits and line-of-sight checks | Combat, Rounds | `/fw stats` after a session: rejects should be near zero for honest clients |
| Test commands for spawning, changing teams, resetting gas and granting weapons | Combat | `/fw spawn`, `/fw team`, `/fw resetgas`, `/fw weapon` |
| Continuous play available behind a flag | Continuous | set `MATCH_MODE = "Continuous"` and join |
| Low-end PC settings, clear team colours, common resolutions, stable camera | | graphics quality 1, 1366×768 and 1920×1080 windows |

## Still to check in Studio

- The screens at 1080p and smaller windows: nothing overlapping, the home
  screen readable over the live view.
- Chat test commands: `/fw` and `!fw` use `Player.Chatted`. If a command
  doesn't arrive under TextChatService, use the server command bar
  (README, "Test-only controls").
- Shooting feels right: the tracer lines up with the crosshair in first and
  third person, hits register on moving targets at normal ping.
- Fart Dash moves a sensible distance and never through walls, and the
  server never puts back an honest dash (`/fw stats` shows no `tooFar`).
- Teammate outlines show and enemies have none.
- The M menu frees the mouse in first person, and Tab doesn't open
  Roblox's own player list.
- Barrels, toilets and cans collide as expected; nobody gets stuck in the
  spawn doors or the back corridor.

## Open issues

- `GameConfig.TEST_CONTROLS.ENABLED` is on. Turn it off (or leave
  `USER_IDS` empty) before any public release.
- Studio-only rounds are the full five minutes; use `/fw end 5` to move
  on while testing.
- Gas, inflation, explosions, barrel interactions, the dash trail and the
  5-kill announcement are Phase 2.
- See "Known bugs and limits" in `docs/implementation-packet.md`.
