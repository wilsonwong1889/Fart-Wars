# Phase 5 checklist: Launch and optimization

The masterplan's Phase 5 pages (5.1-5.5) and their delivery gates, with
where each item is checked. "Spec" means `python3 scripts/run_specs.py`
covers it; "Studio" or "live" means it needs a real server or the
Creator Hub.

## 5.1 Beta scope freeze and test matrix

| Item | Status | Where |
| --- | --- | --- |
| PC only, one map, two teams, 10v10, gas combat, progression, essential UI | done | [`release.md`](release.md) (beta scope); the touch-screen notice on the home screen |
| Timed 5-minute TDM documented as the alternative | done | rounds are the default (your call); continuous play behind `FeatureFlags.MATCH_MODE`, documented in [`release.md`](release.md) |
| Don't block on battle pass, prestige, mobile, maps, parties, events | done | [`roadmap.md`](roadmap.md) |
| Solo, 2-client, 10-player, 20-player soak, public beta | done (plan) | [`release.md`](release.md) test matrix; the Soak spec stands in for the 20-player soak |
| Churn, lag, DataStore failure, low-end graphics, exploits, simultaneous explosions | done | Lifecycle, Soak, Network, Data, Store, Release, Chaos; low detail (Shop) |
| Staging place, release checklist, version number, rollback, changelog | done | [`release.md`](release.md); `ReleaseConfig`; `CHANGELOG.md` |
| Studio: run the matrix on a staging place | Studio | |

## 5.2 Performance and networking

| Item | Status | Where |
| --- | --- | --- |
| Profile remote volume | done | `remote.in.<name>` counters; `/fw perf` (Network) |
| Profile hit validation, gas ticks, barrel chains, saves | done | `Profiler`: `Combat.fire`, `loop.Gas`, `loop.Explosions`, `loop.Projectiles`, `Data.save`, every loop (Network) |
| Physics and memory | done | memory in Health's report; physics in Studio's MicroProfiler |
| Cap concurrent effects and chain depth | done | chain depth 4 and 6 blasts a tick (Chaos); clouds, tracers, effect parts (`GameConfig.BUDGET`, Network) |
| Pool objects | done | explosion bursts (Streak), tracers (Network) |
| No unbounded per-player loops | done | per-player work is per tick; the squad check is at most 20 × 20 a second |
| Reduced particles, volume control, low-detail mode | done | Settings (Shop) |
| Frame rate, render spikes, UI latency | done | `ClientReport`: `client.fps`, `client.spikesPerReport`, `client.uiLatencyMs` (Release) |
| Camera responsiveness | Studio | the MicroProfiler with the camera moving |
| Latency and packet loss can't award false hits | done | Network (late shots, moving targets, lost, bunched and out-of-order shots; hit markers only from the server) |
| High-ping fairness | done | `Combat.shotsBy.<band>` / `hitsBy.<band>` (Network) |
| Studio: network simulation (Incoming Replication Lag) with two clients | Studio | |

## 5.3 Visual identity, store page and acquisition

| Item | Status | Where |
| --- | --- | --- |
| Thumbnail direction | done | [`store-page.md`](store-page.md) |
| No misleading promises | done | [`store-page.md`](store-page.md) rules |
| Description leads with the loop, says PC-only beta | done | [`store-page.md`](store-page.md) |
| Creative testing and the early funnel | done | [`store-page.md`](store-page.md); `funnel.*` (Metrics) |
| Capture the thumbnails and upload them | live | |

## 5.4 Moderation, safety and Roblox compliance

| Item | Status | Where |
| --- | --- | --- |
| Report path | done | the Players screen's REPORT, and Roblox's own Report (Release) |
| Safe chat defaults | done | chat is Roblox's (TextChatService and its filters); the game adds no free text |
| Controls for disruptive players | done | BLOCK, HIDE EMOTES; reports from three players flag for review; kicks and bans in `GameConfig.MODERATION` |
| No personal data in analytics and logs | done | user IDs only; segments only to Roblox's analytics |
| Platform purchase flows | done | MarketplaceService prompts and ProcessReceipt (Store) |
| Health checks, error monitoring, shutdown saves | done | `Health` (Release); `DataService.saveAll` on close (Data) |
| Permissions, private test access, store configuration, content ratings | live | [`release.md`](release.md) checklist items 8-12 |
| No misleading monetization, fake counters or urgency | done | real player counts; odds and contents shown; no timers on purchases |

## 5.5 Launch day, live ops and success criteria

| Item | Status | Where |
| --- | --- | --- |
| Soft launch to a small cohort; review errors, spawn deaths, abandonment, purchase failures | done (plan) | [`release.md`](release.md) |
| Rollback ability | done | [`release.md`](release.md) |
| DAU, concurrents, sessions, D1/D7, first kill, conversion, revenue, crashes | done | Creator Hub + `metrics.*`, `retention.*`, `firsts.*`, `health.*` (Metrics) |
| New vs returning, paid vs free | done | `metrics.*.<segment>`, `funnel.<segment>.*`, `fairness.*` (Metrics) |
| Decision gates | done | [`release.md`](release.md) |
| Weekly issue list with owner, severity, verification | done | [`release.md`](release.md) |
| Run the soft launch | live | |
