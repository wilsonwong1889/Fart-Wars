# Phase 6 checklist: Expansion and live operations

The masterplan's Phase 6 pages (6.1-6.5). Phase 6 is post-launch: most
of it is built behind flags that are off, so the beta's default game
doesn't change until you turn each on. "Spec" means
`python3 scripts/run_specs.py` covers it.

## 6.1 Additional modes and maps

| Item | Status | Where |
| --- | --- | --- |
| Timed TDM kept; modes with distinct objectives | done | Team Elimination, and Gas Control (hold the plaza) (GasControl) |
| Modular map components and prefabs | done | `MapKit`, used by Brainrot Battlefield (Map) |
| Map rotation only after engagement and spawn-fairness tests | done (gate) | [`maps-and-modes.md`](maps-and-modes.md); map rotation itself isn't built |
| Feature-flagged modes, a stable default queue for small servers | done | `FeatureFlags.MODE_ROTATION`, `ROTATION_MIN_PLAYERS` (GasControl) |
| Studio: a Gas Control round with 4+ players | Studio | `/fw mode gascontrol` |

## 6.2 Prestige and long-term economy

| Item | Status | Where |
| --- | --- | --- |
| The level-50 reset proposal, power bonus pending | done | cosmetic-only prestige behind `FeatureFlags.PRESTIGE`; no power bonus (Prestige) |
| Lifetime XP, prestige count, cosmetics, badges kept | done | Prestige |
| An exact reset preview and confirmation | done | the Prestige screen: exact numbers, two presses, a token (Prestige) |
| Sources and sinks, unlock pacing, veteran advantage | done | `Economy.*`, `fairness.*.<band>` (Prestige, Metrics) |
| Prices change without invalidating purchases | done | ownership is by ID ([`roadmap.md`](roadmap.md)) |

## 6.3 Seasonal pass, events and cosmetics

| Item | Status | Where |
| --- | --- | --- |
| Free seasonal track, limited-time challenges, cosmetic rewards | done | `FeatureFlags.SEASONS`, Season 1 (Season) |
| Premium track | later | needs a pricing decision ([`roadmap.md`](roadmap.md)) |
| No combat power through the pass | done | rewards are coins, cosmetics and a badge |
| Events with telegraphs and performance budgets | done | Bean Rain behind `FeatureFlags.EVENTS` (Events) |
| Events don't lock out shooting or punish new players | done | beans only help, nobody is gassed (Events) |
| Weapon skins, trails, emotes, explosion effects | done | tracers, trails, emotes, booms (Season, Store) |
| Themed banners | later | |

## 6.4 Mobile, accessibility and social

| Item | Status | Where |
| --- | --- | --- |
| Mobile only after beta | later | [`roadmap.md`](roadmap.md); a notice on touch-only devices (Release) |
| Motion and flash reductions | done | REDUCE MOTION (Access) |
| Readable HUD scaling | done | HUD SIZE, 80-125% (Access) |
| Sound controls | done | SOUND EFFECTS and VOLUME (Shop) |
| Colour-independent team cues | done | TEAM SYMBOLS ▲ ●, team names in words (Access) |
| Friend joining without stacked teams | done | friends weigh into team choice within the balance rules (TeamBalance); the cards show friends (Access) |
| Party matchmaking, community events | later | |

## 6.5 Continuous development and operations

| Item | Status | Where |
| --- | --- | --- |
| Weekly triage, balance updates, seasonal reviews, telemetry audits | done | [`operations.md`](operations.md) |
| Patch notes explaining economy and weapon changes | done | [`operations.md`](operations.md) |
| Technical debt register | done | [`operations.md`](operations.md) |
| Rollback, staging, dashboards | done | [`release.md`](release.md), [`operations.md`](operations.md), `/fw stats`, `/fw health`, `/fw perf` |
| Expansion gate; fairness and compliance before monetization releases | done | [`operations.md`](operations.md) |
