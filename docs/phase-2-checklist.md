# Phase 2 checklist: Combat & Chaos

The masterplan's Phase 2 gates (section 2.5) and the Studio checks still
needed. "Spec" means `python3 scripts/run_specs.py` covers it without
Studio; the harness has no physics, rendering, sound or real network, so
feel, performance and visuals need Studio.

## Automated tests

| Masterplan item | Spec |
| --- | --- |
| Hit registration | Combat (body and head hits, walls) |
| Cooldown exploits | Combat (fire interval, repeated shot numbers, dash cooldown) |
| Team immunity | Combat, Gas, Chaos (shots, gas and blasts) |
| 99-to-100 gas threshold | Gas |
| Recovery interruption | Gas |
| Simultaneous damage | Gas (two shooters, one kill, one assist) |
| Barrel-to-player-to-barrel chains | Chaos |
| Kill attribution | Gas (killer, assists, leavers), Chaos (chains, barrels, last shot) |
| No double rewards on repeated death or duplicated remote calls | Combat (shooting the body), Gas (exploding twice), Combat (duplicate shot numbers) |
| Server restart during combat | nothing persists yet (Phase 3 adds saving); a restart starts every meter at 0 |

## Playtest metrics

All in `/fw stats` (and the full JSON in the output):

| Metric | Counter |
| --- | --- |
| Kills per minute | `Elimination.elimination` over uptime |
| Average time to explosion | `firsts.timeToExplosion` (first gas to the bang) |
| Gas recovery usage | `Gas.recovered` (total % drained) |
| Dash usage | `Dash.dashes` |
| Barrel-caused deaths | `Elimination.cause.barrel` |
| Spawn deaths | `Lifecycle.spawnDeaths` (died within 5 s of spawning) |

Laughter, frustration and readability come from playtesters, not counters.

## Release gate

- [ ] 20-player load test with effects on: the server stays responsive, no
      severe memory growth or repeated errors (`/fw stats` errors stay 0).
- [ ] Players keep fighting without progression rewards. Only then start
      Phase 3.

## Still to check in Studio

- Shots, hit markers and headshots feel right; the gas meter and the
  bellies read clearly at every stage, and the critical outline pulses
  slowly (no flashing).
- The countdown is readable, and the explosion, cloud and kill feed make it
  obvious who blew up whom.
- Chains through a cluster, and barrels: lit outline, blast timing, the
  orange burst, nothing happening through walls.
- Fart Dash puffs show for other players.
- Frame rate with a full chain in a 20-player server, and at graphics
  quality 1-3 (fewer effects).
- Sounds: `AudioConfig` is empty; upload the game's sounds and fill it in.
