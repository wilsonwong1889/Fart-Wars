# Phase 4 checklist: Rewards, retention and monetization

The masterplan's Phase 4 pages (4.1-4.5) and their delivery gates, with
where each item is checked. "Spec" means `python3 scripts/run_specs.py`
covers it with stand-ins (DataStore, MarketplaceService, friendships);
"Studio" means it still needs a run in Studio or a live server.

## 4.1 Daily returns and timed rewards

| Item | Status | Where |
| --- | --- | --- |
| Seven-day track: coins, a cosmetic, occasional free spins | done | Rewards; `RewardsConfig.daily` |
| Claim availability and the reset time shown | done | Rewards (the daily screen's CLAIM and countdown, auto-open on the home screen) |
| A missed day isn't punished | done | Rewards (three days away: still the next day of the track) |
| A gift every ten minutes of active play, not AFK | done | Rewards (home screen time earns nothing) |
| Capped frequency, claim state saved | done | Rewards (6 a day, 10 banked; `GiftDay`, `GiftsToday`, `LastDailyDay` saved) |
| Spin odds and rewards disclosed; no paid random rewards | done | Rewards (every chance on the spin screen; spins are free only) |
| Daily claim rate, ten-minute completion, D1/D7, abuse patterns | done | `Rewards.dailyClaims`, `Rewards.gifts`, `session.reached10Minutes`, `retention.D1` / `D7`, `Economy.anomalies` |
| Studio: claim, wait for a gift in real play, rejoin the next UTC day | Studio | |

## 4.2 Starter pack and optional purchases

| Item | Status | Where |
| --- | --- | --- |
| Starter Pack: a tracer, a Fart Dash trail, an emote, a modest coin bonus | done | Store; `MonetizationConfig.passes` |
| Contents shown in full; no false scarcity or fake discounts | done | Store (the Store tab lists everything; prices come from Roblox) |
| Weapons stay free to earn | done | nothing for sale is a weapon or a stat; Structure |
| Server receipt processing, idempotent grants | done | Store (once per receipt, saved first, repeats granted without paying) |
| Cancelled, delayed and duplicate receipts | done | Store (absent player, unsaved profile, failed save: "not yet" and Roblox retries) |
| Products for consumables, passes for permanent items | done | coin packs are products; the Starter Pack is a pass |
| Free-to-paid outcome differences | Phase 5 | payer vs free metrics arrive with the live metrics |
| Studio: create the pass and products, set their IDs in `MonetizationConfig`, buy each in Studio's test purchase | Studio | |

## 4.3 Friends, referrals and social play

| Item | Status | Where |
| --- | --- | --- |
| Verified newcomer milestone, mutual small rewards | done | Social (a newcomer's first ten active minutes with a friend: both paid once) |
| No self-referrals or alternate-account farming | done | Social (once per newcomer, ever; the welcomer must have played before; a daily cap; no invite rewards at all) |
| Teammate assists and group moments | done | assists (Phase 2), the squad bonus for friends on one team |
| Party matchmaking | later | [`roadmap.md`](roadmap.md); friends already weigh into team choice without stacking |
| Shareable moments | done | chain explosions, inflation, the alpha call (Phases 2-3) |
| Track friend co-play and later retention | done | `social.sessionsWithFriend`, `.friendCoplaySeconds`, `.leftWithFriend` / `.leftSolo` |
| Studio: two friends' accounts on one team for ten minutes | Studio | |

## 4.4 Prestige, seasons and battle pass roadmap

| Item | Status | Where |
| --- | --- | --- |
| The prestige proposal documented, balance approval required | done | [`roadmap.md`](roadmap.md) |
| What persists, and the reset confirmation | done | [`roadmap.md`](roadmap.md) |
| No battle pass in the beta; seasonal challenges through normal play | done | [`roadmap.md`](roadmap.md) |
| Events after the beta | done | [`roadmap.md`](roadmap.md) |

## 4.5 Retention experimentation and guardrails

| Item | Status | Where |
| --- | --- | --- |
| Feature-flagged reward timing, early unlock costs, tutorial prompts | done | Social (`ExperimentConfig`: `giftMinutes`, `earlyUnlock`, `tips`, each reaching the game) |
| Compare cohorts with event telemetry | done | Social (`exp.<key>.<variant>.*`: sessions, new and returning, next day, D1, D7, ten minutes, active minutes) |
| Reward timers, ownership, costs and odds explained | done | daily countdown, gift timer, OWNED labels, prices, the spin's chances |
| No exploitative pressure or notification spam | done | the daily screen opens once a session; no timers that expire rewards |
| Daily reset boundaries, time zones | done | Rewards (UTC days, the countdown to 00:00 UTC) |
| AFK timer abuse | done | Rewards (gifts only while ACTIVE; AFK moves you to spectating) |
| Receipt repeats and refunds | done | Store |
| Prestige migration | later | prestige isn't built (4.4) |
| Paid systems only after receipt and save reliability are shown | Studio | the Store spec covers it with stand-ins; a real purchase test comes first |
