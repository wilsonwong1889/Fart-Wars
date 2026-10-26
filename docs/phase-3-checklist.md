# Phase 3 checklist: Progression & Economy

The masterplan's Phase 3 pages (3.1-3.5) and their delivery gates, with
where each item is checked. "Spec" means `python3 scripts/run_specs.py`
covers it against a stand-in DataStore; "Studio" means it still needs a
run with a real DataStore. Milestone 1 (saving, coins, XP, levels) is in;
milestone 2 (shop, loadouts, the new weapons and abilities, the menu
screens) is next.

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
| Unlock beats at 1, 5, 10, 15, 20, 25, 30, 40, 50 | recorded and announced; weapons and abilities usable in milestone 2 | Economy (ability at 10, cosmetic at 20, cap at 50) |
| First progression in the first few minutes | done | five eliminations and the streak reach level 2 (Economy) |
| Lifetime XP, repeatable level-50 rewards | done | Economy |
| Migration-friendly fields for prestige later | done | versioned saves, `migrate` (Data) |
| XP gained, progress to next level, unlock preview, next goal | done | Economy (the client panel, reward lines, banner) |
| Rewards never lost on a mid-animation disconnect | done | Data (reward just before leaving), Economy (reward before the profile loads) |

## 3.3 Shop, equipment and abilities (milestone 2)

- [ ] Weapon shop with preview, gas per hit, range, fire rate, handling,
      effects, price and requirements
- [ ] Purchases checked on the server and saved before the UI confirms
- [ ] Playstyles, not a damage ladder
- [ ] Loadouts saved and validated; applied on a safe respawn
- [ ] Abilities by level with cooldown trade-offs and counterplay

## 3.4 Weapon mastery, saves and data migrations

| Item | Status | Where |
| --- | --- | --- |
| Mastery at 25 / 75 / 150 / 300, badges, never claimed twice | done | Economy |
| The data model (all fourteen fields) | done | Data; the save format in `implementation-packet.md` |
| Retries and backoff, session locking, autosave, leave and shutdown saves | done | Data |
| Versioned records, safe migrations | done | Data |
| Partial saves, failed writes, concurrent joins | done | Data |
| No client authority over currency, inventory, mastery or level | done | no remote accepts any of them; Structure (the remote list) |
| Anomalous currency gains, impossible ownership | gains done (Economy); unknown equipped weapons are reset and counted (Data); shop ownership checks in milestone 2 |

## 3.5 First 10 minutes, UI and QA

| Item | Status | Where |
| --- | --- | --- |
| No popups forced while shooting | done | reward lines sit bottom right; the level-up banner is short and takes no input |
| HUD: gas, coins, XP, level, weapon, cooldown, streak, kill feed | coins, XP and level added (Economy); weapon name on the HUD in milestone 2 | |
| Menu: Play, Weapons, Abilities, Progression, Settings | milestone 2 | |
| Pending purchase and saving states | saving done ("Loading progress...", "Progress isn't saving this session"); purchases in milestone 2 | Economy |
| Interrupted purchases | milestone 2 | |
| Repeated reward triggers, max level, invalid equipped item, DataStore outages | done | Economy, Data |

## Still to check in Studio (milestone 1)

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
