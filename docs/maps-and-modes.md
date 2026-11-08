# Adding modes and maps

Phase 6.1: expand only after the core mode proves sticky, with modes
that have their own objective and maps that pass the same tests as
the first one.

## Modes

A mode is a module in `src/server/Modes` made with `GameModeBase.new`:

| Field | What it does |
| --- | --- |
| `id`, `displayName` | the ID in configs and the name players see (the HUD shows it in place of ROUND) |
| `objective` | `"eliminations"` or `"zone"`; something new needs its own service, as Gas Control has `ZoneService` |
| `hint` | one line saying how to win |
| `roundSeconds`, `intermissionSeconds` | the round's length and the results screen's |
| `validateScoreEvent(event, context)` | which score events count (`source`: `"elimination"`, `"zone"`, `"test"`) |
| `computeResult(scores, teamIds)` | who won (default: most points, level is a draw) |
| `onRoundStart`, `onRoundEnd` | hooks for the mode's own setup |

`RoundService` runs the clock either way. Points go through
`MatchScoreService.record(event, points)`, which only counts them while a
round is open and the mode accepts them.

Two modes so far:

- **Team Elimination** (the default): most eliminations wins.
- **Gas Control**: hold the control zone, Porcelain Plaza around the
  throne (a circle 60 studs out on the full-size map, exactly as wide as
  its floor ring). A team alone in it takes it in 6 seconds, 4 with two
  of them in it, 3 with three or more (bots count); an enemy in it
  freezes the capture, an empty zone lets it run back down. The team
  that holds it scores a point a second while it has the zone to
  itself; contested or empty nobody scores, but it stays theirs until
  the other team takes it. Eliminations don't score, they clear the
  zone. Holders earn 2 coins and 5 XP every 10 seconds of scoring, 15
  times a round at most (`GameConfig.ZONE`). The HUD's zone line says
  who holds it, who's taking it (with a bar) or the standoff; a marker
  over the plaza shows it from anywhere; the results say it was Gas
  Control. Bots head for open ground in it, never into the throne.

## Rollout

- `FeatureFlags.MODE_ROTATION` (off as shipped): each round takes the next
  mode in `GameConfig.MODE_ROTATION` that the map lists in
  `MapConfig.modes` (a zone mode only where the map has a zone) and isn't
  the one just played, but only once `ROTATION_MIN_PLAYERS` (6) players,
  not bots, are on teams. Smaller servers always get `DEFAULT_MODE`, so a
  quiet server keeps the stable queue even when bots fill it; one that
  grows past six after a run of default rounds goes straight to Gas
  Control.
- `/fw mode gascontrol` sets the next round's mode on a test server,
  whatever the rotation says.
- Turn rotation on after a staging playtest of each mode, then watch
  `firsts.session`, `session.reached10Minutes` and the results by mode
  (`round.<mode>.ended` and `round.<mode>.draws` in `/fw stats`, and a
  `Round ended` line per round).

## Maps

A map is a ModuleScript in `src/maps` (built from code with `MapKit`) or a
Model made in Studio with the same name, plus an entry in `MapConfig`.

`MapKit` has the pieces: `mirror` (every half is mirrored across z = 0),
`part`, `marker` (invisible, never in anyone's way), `pair` (a part and
its mirror, optionally in each team's colour), `cylinder`, `spawnPads`,
`gasBarrels`, `launchPad` (a launch pad and its mirror: the cushion and
the landing spot with the arc's peak, `LaunchPads`), `cameraViews` and
`controlZone`. Build one half and mirror it, and the fairness checks
follow.

The contract (`MapBase.validate`): `Spawns/<team>` with at least one
SpawnLocation each, inside `Bounds`; `CameraPoints`; every part anchored;
and, for a map that lists a zone mode, the control zone at
`MapConfig.zone`.

## Before a map joins the rotation

Each arena has to pass, like Brainrot Battlefield does (the `Map` spec):

- the contract above
- mirror symmetry: every part has its mirror image
- lanes: dividers with gaps, so no lane is a dead end
- spawn safety: no sightline from the lanes or the enemy half to a spawn
  pad, and `safeSpawn` picks away from enemies
- barrels in contested ground, never by a spawn
- launch pads (if it has any): every arc clears the walls and cover with
  room round an avatar, stays on its own half, peaks below anything you
  could stand on, and lands on open ground, never near the other team's
  spawn

Then on staging: engagement time (`firsts.shot` and `firsts.hit` per
session, compared with Brainrot Battlefield), spawn deaths (deaths in the
first seconds after a spawn) and how long rounds stay close. Only then
does it go into a map rotation, behind its own flag. Map rotation itself
isn't built yet; `MapService.load(id)` already swaps maps between rounds.
