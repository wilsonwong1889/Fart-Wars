# Running Fart Wars week to week

The masterplan's 6.5: operate the game as a measurable product. This is
the routine, and where each part of it lives in the code.

## The week

| When | What | With |
| --- | --- | --- |
| Monday | Bug triage: sort the weekly issue list by severity, give each an owner and a way to verify the fix | [`release.md`](release.md) (issue list format) |
| Monday | Telemetry audit: are the numbers still sane? (see below) | `/fw stats`, `/fw health`, `/fw perf`, the Creator Hub |
| Midweek | Fixes and balance changes on a branch, specs green, staging playtest | `python3 scripts/run_specs.py`, the staging place |
| Thursday | Release: the checklist, a version bump, patch notes | [`release.md`](release.md) |
| Each season | Content review: the next season's dates and rewards, events, cosmetics | `SeasonConfig`, `EventConfig`, `ProgressionConfig` |

## The telemetry audit

- **Health**: no FAILING, DEGRADED only briefly; errors per minute flat;
  `client.errors` near zero; memory flat over a long server.
- **Performance**: `/fw perf`'s costliest paths in the same few
  milliseconds as last week; no remote suddenly busier.
- **Fairness**: `Combat.hitsBy.highPing` against `lowPing`;
  `fairness.kills.<band>` and `<payer|free>` against deaths (veterans and
  payers shouldn't win much more often).
- **Economy**: `Economy.coins.<reason>` (sources) against `Shop.*` and
  `Economy.spent.*` (sinks); `samples.unspentCoins` creeping up means
  prices or sinks need a look.
- **Retention**: `retention.*`, `funnel.new.*`, `metrics.sessionLength.*`,
  and experiment cohorts (`exp.*`) if one is running.
- **Moderation**: `flags.*` and `reports.*`; read the flagged players' logs
  before changing `GameConfig.MODERATION`.

## Patch notes

Players see the version on the home screen and in Settings. Each release's
notes say, in plain words:

```
Fart Wars 0.6.1

New
- ...

Changed
- The Spritzer's range is now 55 studs (was 60): it won too many fights
  at mid range. Its price is the same, and if you own it you keep it.

Fixed
- ...
```

Explain every economy or weapon change and why; never change a price or
a reward silently. Ownership never depends on price, so a price change
never takes anything away.

## Changing balance

1. Change the numbers in config (`WeaponConfig`, `ProgressionConfig`,
   `RewardsConfig`, `GameConfig`), never in services.
2. The specs check each weapon's contract and the economy's limits; run
   them all.
3. Try it on staging with two or more players.
4. For a change you're unsure of, an experiment (`ExperimentConfig`) on a
   share of players, compared by cohort, is better than a guess.

## Technical debt to keep paying down

| Area | Watch for | Where it stands |
| --- | --- | --- |
| Remote validation | each remote checks its own payload | every handler is guarded and counted (`Telemetry.guard`, `remote.in.*`); a shared validator would cut repetition |
| Save migrations | every new field needs a default | `DataService.defaults` and `migrate`; `SaveVersion` for anything harder; the Data spec checks old saves load |
| Config sprawl | numbers duplicated across configs | the configs are frozen tables; the Structure spec checks their shape |
| Test coverage | new systems without a spec | every service has a spec; the Soak spec runs them all together |
| Feature flags | flags left on half-finished, or off forever | the flags list in `FeatureFlags` with what each is for; remove a flag once its system is settled |

## Rollback and staging

- Rollback is the Creator Hub's version history (Restore), then shut down
  servers to move players; a flag or experiment turned off is often
  enough instead ([`release.md`](release.md)).
- Staging is a private place in the same experience; `ReleaseConfig`
  tells servers which one they're on, and the home screen says so.
- Dashboards: `/fw stats` prints everything as JSON (copy it into a
  spreadsheet); `/fw health` and `/fw perf` for one server now; the
  Creator Hub for the whole game.

## The expansion gate

Before building something big (a mode, a map, a season, an event):

- **Demand**: do the numbers or players ask for it? (Session length,
  return rates, requests.)
- **Cost**: can it be kept up? (Content every season, moderation, support.)
- **Core health**: is the core loop's retention stable? Don't expand on a
  leaking base.

## Before any monetization release

- Nothing sold changes combat; weapons stay earnable with coins.
- Contents, prices and odds are shown before buying; no fake discounts,
  scarcity or timers.
- Receipts are processed once and saved before they're granted (the Store
  spec); test a real purchase on staging.
- Nothing bought is ever lost (prestige keeps unspent store coins; passes
  are permanent).
- Roblox's rules for paid random items: there are none in the game; keep
  it that way unless the rules are checked first.
