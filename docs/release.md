# Releasing Fart Wars

The masterplan's release process (5.1, 5.4, 5.5): a beta scope that stays
put, a staging place, a version number, a checklist, a rollback plan and
a soft launch measured before it grows.

## Beta scope (frozen)

In the beta: PC only; one map (Brainrot Battlefield); two teams (Skibidi
Stinkers and Sigma Sharters), 10v10; gas combat, Fart Dash, the four
weapons and two Q abilities; progression to level 50; daily rewards,
gifts and spins; the store (Starter Pack, coin packs); essential UI.

The match mode is **5-minute rounds** with a 15-second intermission
(`FeatureFlags.MATCH_MODE = "Rounds"`, your call in Phase 1). The
masterplan's later baseline, continuous play, is the documented
alternative behind the same flag. Switching it is a release with its own
changelog entry, never a silent change to live rules.

Not blocking the launch: a battle pass, prestige, mobile, more maps,
parties and events ([`roadmap.md`](roadmap.md)). Anything new goes on
the roadmap, not into the beta.

## Places

| Place | What it's for | `ReleaseConfig` |
| --- | --- | --- |
| Staging | a private copy for testing each release on real servers | `STAGING_PLACE_ID` |
| Live | the public game | `LIVE_PLACE_ID` |

Make the staging place in the same experience (Creator Hub → your
experience → Places → Add a place), keep it private, and set both IDs in
`src/shared/Config/ReleaseConfig.luau`. Every server logs its version and
channel at start (`server ready: v0.5.0 (staging) ...`), Workspace has
`GameVersion` and `ReleaseChannel`, and the home screen and Settings
show them, so every report and screenshot says which build it came from.

## Version numbers

`ReleaseConfig.VERSION`, `major.minor.patch`. The minor number goes up for
a release with new features, and the patch number for fixes only. Bump it
in the release commit and add a `CHANGELOG.md` entry with the same number.

## Release checklist

Before publishing to staging:

1. All specs pass (`python3 scripts/run_specs.py`) and the type check is
   clean.
2. `VERSION` bumped, changelog entry written in plain words: what changed
   for players, especially economy or weapon changes and why.
3. `rojo build default.project.json -o FartWars.rbxlx`, open it, and
   publish to the **staging** place.

On staging (a private server, two or more accounts):

4. `/fw selftest`: no FAIL lines; the WARN lines are what you expect
   (store IDs, sounds).
5. `/fw health`: OK.
6. Walk through [`studio-signoff.md`](studio-signoff.md) for anything this
   release touched, and the test matrix below for its size.
7. A test purchase of each store item (Studio's test purchases, or a real
   one on staging) if the store or saving changed.

Before publishing to live:

8. `GameConfig.TEST_CONTROLS.ENABLED = false` (or the allow-list holds only
   your own accounts), and `selftest`'s Release line agrees.
9. `GameConfig.MODERATION` set as intended (kicks are off by default).
10. Every `ExperimentConfig` percent is what you mean to run.
11. Store IDs set in `MonetizationConfig`, and the store's prices,
    contents and the Starter Pack's description match the game.
12. Game Settings: devices are **Computer** only; Max Players 20;
    DataStores and API access as intended; the content maturity
    questionnaire is filled in; private-server and permission settings
    checked.
13. Publish to **live**. Note the place version number Roblox shows.

## Rollback

- **A bad build**: Creator Hub → the place → Version History → the
  previous version → Restore. Then shut down servers (Creator Hub →
  Servers → Shut down all, or "migrate to latest update") so players move
  to it. Saves stay compatible both ways within a `SaveVersion`; a build
  that raised `SaveVersion` can't be rolled back past without the older
  build refusing those profiles (it plays them on temporary profiles
  rather than overwrite them), so treat a `SaveVersion` bump as a release
  of its own.
- **A bad system**: turn it off with its flag (`FeatureFlags`,
  `ExperimentConfig`) in a patch release instead of rolling back
  everything.
- Write down what happened in the weekly issue list.

## Soft launch

1. Publish, then open the game to a small group first (friends, a
   group, or a short promotion). Leave it a few days.
2. Each day, check:
   - errors and health: `health.DEGRADED` / `FAILING`, the error counts,
     `client.errors`, `client.lowFps`, `client.highPing`
   - spawn deaths and fairness: deaths within the spawn-protection time,
     `flags.*`
   - first-minute abandonment: sessions that end before `firsts.shot`,
     `session.reached5Minutes` / `reached10Minutes` over `session.joins`
   - purchase failures: `Store.receiptDeferred`, `Store.receiptSaveFailed`,
     `Store.unknownProduct`
3. Fix blockers before more traffic. Keep the previous version ready to
   restore.

## Live metrics

| Metric | Where |
| --- | --- |
| DAU, concurrent users, D1/D7 retention, session length, revenue | the Creator Hub's analytics dashboards |
| D1/D7 by our own count, new vs returning | `retention.newPlayers`, `.nextDay`, `.D1`, `.D7`, `session.returning` |
| Average session; ten-minute engagement | `firsts.session`, `session.reached10Minutes` |
| First kill | `firsts.elimination` |
| Purchase conversion | `Store.purchases`, `Shop.firstPurchases` over `session.joins` |
| Crash and error rate | `health.*`, the errors in `/fw stats`, `client.errors` |
| Paid vs free, new vs returning | the Creator Hub's segments (by payer and new users) |

Counters are per server (`/fw stats`); the Creator Hub's numbers are for
the whole game.

## Decision gates

Grow the audience only when:

- servers stay OK (no FAILING, DEGRADED only briefly)
- combat is fair: no spawn deaths beyond the odd edge case, no unexplained
  flags, high ping doesn't decide fights
- onboarding works: most new players fire in the first minute, and a good
  share reach ten minutes

## Weekly issue list

One list, sorted by severity, reviewed every week. Each issue has:

| Field | Example |
| --- | --- |
| Issue | Players spawn into a blast near the east barrels |
| Severity | Blocker / High / Medium / Low |
| Owner | who fixes it |
| Evidence | counter, report, clip |
| Verify by | the spec, Studio step or metric that proves it fixed |
| Status | open / fixing / verify / done |

## Test matrix

| Test | How | Covers |
| --- | --- | --- |
| Solo | Studio, Play | every spec's single-player paths; [`studio-signoff.md`](studio-signoff.md) |
| Two clients | Studio, Test → 2 players | combat, gas, teams, the store, rewards, the Players screen |
| Ten players | Studio, Test → 10 players (or a staging server) | team balance, chains, the scoreboard, performance with effects |
| Twenty players, soak | a staging server with 20 accounts, 30+ minutes | the `Soak` spec's checks in real conditions: no errors, memory flat, health OK |
| Public beta | the soft launch above | the live metrics |

Each of these also covers:

| Situation | Spec | On a real server |
| --- | --- | --- |
| Join and leave churn | Lifecycle, Soak | players leaving mid-countdown, mid-purchase |
| Lag | Combat (refused shots, cadence) | Studio's network simulation (incoming replication lag) |
| DataStore failure | Data (outages, locks), Store, Release | Studio without API access: temporary profiles, health DEGRADED |
| Low-end graphics | Effects (quality 1-3 thins effects) | graphics quality 1, reduced effects on |
| Exploit attempts | Combat, Dodges, Shop, Store, Release (junk payloads) | a client sending junk through every remote |
| Simultaneous explosions | Chaos (budget, chain depth) | six barrels and three players exploding at once |
