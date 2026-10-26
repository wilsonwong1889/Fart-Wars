# Phase 3 checklist: Progression & Economy

The masterplan's Phase 3 pages (3.1-3.5) and their delivery gates, with
where each item is checked. "Spec" means `python3 scripts/run_specs.py`
covers it against a stand-in DataStore; "Studio" means it still needs a
run with a real DataStore. Milestone 1 (saving, coins, XP, levels) and
milestone 2 (shop, loadouts, the new weapons and abilities, the menu
screens) are in.

The Studio items here are gathered into one session in
[`studio-signoff.md`](studio-signoff.md).

## 3.1 Coins and XP accounting

| Item | Status | Where |
| --- | --- | --- |
| Elimination +10 / 20 XP, assist +5 / 10, chain bonus +5, 5-kill streak +50 / 100, 5 and 10 minutes +25 / 50 and +75 / 100 | done | Economy; values in `ProgressionConfig` |
| Prevent double-awarding | done | Economy (same death twice, replayed grant ID, alpha once, participation once) |
| Prevent idle farming | done | Economy (home screen and AFK time earn nothing) |
| Server-side transactions with unique event IDs | done | Economy (ledger IDs carry the event ID) |
| Coins spendable, XP not | done | separate fields; the shop (milestone 2) spends coins only |
| Source breakdowns | done | `Economy.coins.<reason>` and `Economy.xp.<reason>` in `/fw stats` |
| Transaction limits and audit logs | done | Economy (refused over 2,000 a grant, negatives, fractions); the profile's 20-entry ledger |
| Coins per 10-minute session, unspent balances | done | `samples.coinsPer10Minutes`, `samples.unspentCoins` in the stats JSON |
| Unlock time | done | `firsts.levelUp`, `firsts.coins`, `Economy.reachedLevel.<n>` |

## 3.2 Levels 1-50 and unlock pacing

| Item | Status | Where |
| --- | --- | --- |
| Levels 1-50 on a configurable curve | done | Economy; `ProgressionConfig.xpToNext` |
| Unlock beats at 1, 5, 10, 15, 20, 25, 30, 40, 50 | done | Economy (ability at 10, cosmetic at 20, cap at 50); Structure (each shop weapon and Q ability unlocks at its level) |
| First progression in the first few minutes | done | five eliminations and the streak reach level 2 (Economy) |
| Lifetime XP, repeatable level-50 rewards | done | Economy |
| Migration-friendly fields for prestige later | done | versioned saves, `migrate` (Data) |
| XP gained, progress to next level, unlock preview, next goal | done | Economy (the client panel, reward lines, banner) |
| Rewards never lost on a mid-animation disconnect | done | Data (reward just before leaving), Economy (reward before the profile loads) |

## 3.3 Shop, equipment and abilities

| Item | Status | Where |
| --- | --- | --- |
| Weapon shop with preview, gas per hit, range, fire rate, handling, effects, price and requirements | done | Shop (the locker's cards) |
| Purchases checked on the server; ownership saved before the UI confirms | done | Shop (refusals, saved before the answer, rolled back on a failed save) |
| Playstyles, not a damage ladder | done | Arsenal (rate and range, weight, area denial) |
| Loadouts saved, validated (defaults on an invalid save), applied on a safe respawn | done | Shop, Data |
| Abilities by level with cooldown trade-offs and counterplay; no stacking | done | Arsenal (one Q ability, one cooldown, the tells, too late mid-countdown) |

## 3.4 Weapon mastery, saves and data migrations

| Item | Status | Where |
| --- | --- | --- |
| Mastery at 25 / 75 / 150 / 300, badges, never claimed twice | done | Economy |
| The data model (all fourteen fields) | done | Data; the save format in `implementation-packet.md` |
| Retries and backoff, session locking, autosave, leave and shutdown saves | done | Data |
| Versioned records, safe migrations | done | Data |
| Partial saves, failed writes, concurrent joins | done | Data |
| No client authority over currency, inventory, mastery or level | done | no remote accepts any of them; Structure (the remote list) |
| Anomalous currency gains, impossible ownership | done | Economy (gains), Data (unknown equipment reset and counted), Shop (only owned items equip) |

## 3.5 First 10 minutes, UI and QA

| Item | Status | Where |
| --- | --- | --- |
| No popups forced while shooting | done | reward lines sit bottom right; the level-up banner is short and takes no input |
| Contextual tutorials and optional reminders | done | Shop (TipsController: dash, barrels, an affordable weapon, an unequipped ability; never mid-fight; Settings → Tips) |
| First purchase rate, first ten-minute completion, inflation | done | `Shop.firstPurchases`, `session.reached10Minutes`, `samples.coinsPer10Minutes` (Shop, Economy) |
| HUD: gas, coins, XP, level, weapon, cooldown, streak, kill feed | done | Economy (coins, XP, level), Arsenal (weapon, ability cooldown) |
| Menu: Play, Weapons, Abilities, Progression, Settings | done | Shop (the locker from the home screen and the M menu) |
| Pending purchase and saving states | done | Shop ("Buying...", buttons wait), Economy ("Loading progress...", "Progress isn't saving this session") |
| Interrupted purchases | done | Shop (failed save rolled back; leaving mid-purchase saves both together) |
| Repeated reward triggers, max level, invalid equipped item, DataStore outages | done | Economy, Data |

## Still to check in Studio

- With **Enable Studio Access to API Services** on: play, earn coins
  (`/fw coins 50`), stop, play again: the coins are back. `/fw profile`
  says "saving".
- Without API access: the HUD says progress isn't saving, the output warns
  once, nothing errors.
- Two Studio test servers (or a live server and Studio) with the same
  account: the second waits for the first's lock, then loads.
- The progress panel, reward lines and banner at 1080p and 1366×768:
  nothing covers the gas meter, kill feed or crosshair.
- A ten-minute session: participation pays at 5 and 10 minutes; the
  first level-up arrives within the first few minutes of real play.
- After a session, `/fw stats` JSON: `Economy.*` sources look sensible,
  `Data.saveFailures` is 0.
- The locker at 1366×768: four weapon cards fit, text doesn't overflow;
  buying shows "Buying..." then the answer; EQUIP mid-fight says it waits
  for the respawn, and the HUD's weapon line agrees.
- Each weapon in a 2-player session: the Spritzer's spray stops at 60
  studs, the Thunderclapper's walk feels heavier, stink bombs arc where
  you'd expect (aim higher to throw farther) and the cloud is readable.
- Q: Recovery Burst's puff and Gas Pulse's ring are visible to the other
  side; the HUD counts the cooldown down.
- Sounds: the new `AudioConfig` slots (spritzer, thunderclapper, lobber,
  splat, vent, pulse, purchase, coins, levelUp) are empty until uploaded.
