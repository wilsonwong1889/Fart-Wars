# Economy pacing

How fast players earn coins and XP, level up and can buy each gun, from
the numbers in the configs. These are the beta's tuning targets and the model
that checks them.

## Running the model

```
python3 scripts/analyze_economy.py                          # the working tree
python3 scripts/analyze_economy.py --ref main               # the configs at a git ref (before/after)
python3 scripts/analyze_economy.py --squad --live-ops       # with the squad bonus, Bean Rain and the season track
```

Plain Python 3, nothing to install. It parses `ProgressionConfig`,
`RewardsConfig`, `WeaponConfig`, `GameConfig`, `FeatureFlags`,
`EventConfig` and `SeasonConfig` (it doesn't copy their values), so after
changing a number you just run it again. It prints income, the time to each
level milestone, when each gun is unlocked, affordable and bought, and a
PASS/MISS line for each target.

**The model** uses expected values, with no luck involved. Each player plays one session
a day on a full 10v10 server in 5-minute rounds (11.4 an hour), claims
the daily reward at the start of it and spins every free spin straight
away. They buy each gun the moment it's both unlocked and affordable, cheapest first.
Combat pays per round. Participation, ten-minute gifts, the daily track,
weapon mastery (on the newest gun bought) and the level-50 rewards pay as
configured. The squad bonus, Bean Rain and the season track are left out unless asked
for (events and seasons are off as shipped).

**The profiles** are assumptions, not config, and live at the top of the script:

| Profile | A round | Chain kills / 5-kill streaks a round | Play a day |
| --- | --- | --- | --- |
| casual | 1 elimination, 1 assist | 0 / 0 | 45 min |
| average | 3 eliminations, 2 assists | 0.3 / 0.1 | 60 min |
| strong | 6 eliminations, 3 assists | 1 / 0.4 | 90 min |
| grinder | the strong player | 1 / 0.4 | 180 min |

Replace them with real numbers once the beta has them: kills per minute
(`Elimination.elimination` over uptime), `samples.coinsPer10Minutes` (the
model's "day 1, all: coins / 10 min") and `Economy.reachedLevel.<n>`.

## Targets

1. An average player buys the first gun (Spritzer) in their first session (45 minutes).
2. An average player can have all three guns within about a week at an hour a day.
3. Level 50 is a long-term goal. An average player reaches it on day 21 or later, and nobody
   reaches it in the first week, not even the grinder at 3 hours a day.
4. Players don't earn a lot with nothing to buy for hours. Average, strong and grinder players
   never spend more than an hour of play holding the coins for the next gun
   while they wait for its level.

Target 4 is judged on the average and stronger players only, and the
casual player's figure is shown as a note. About 85% of a casual player's coins come
from time (spins, daily rewards, participation), while nearly all of their
XP comes from combat, so with any prices an average player can reach in a
week, a casual player gets the coins before the level. The fix would be XP
from timed rewards (for example spin weights moving from coins to the
150 XP prize), which is a bigger change than this pass.

## Results

Income after this pass. No reward changed, so it's nearly the same as before; only mastery
lands at slightly different times:

| | casual | average | strong | grinder |
| --- | --- | --- | --- | --- |
| combat coins / XP per 10 min | 29 / 57 | 89 / 171 | 190 / 362 | 190 / 362 |
| combat coins / XP per hour | 171 / 343 | 531 / 1,029 | 1,143 / 2,171 | 1,143 / 2,171 |
| all sources, day 1: coins / XP per 10 min | 213 / 115 | 285 / 223 | 349 / 396 | 289 / 379 |
| all sources, week 1: coins / XP per hour | 1,438 / 676 | 1,784 / 1,323 | 2,216 / 2,368 | 1,679 / 2,270 |
| week 1 coins from spins / daily / combat | 52 / 24 / 12% | 45 / 15 / 30% | 24 / 8 / 52% | 16 / 5 / 68% |

A free spin is worth 125.5 coins and 22.5 XP on average, and six an hour is the
largest single coin source for anyone who isn't a strong player.

Pacing for the average player (play time, day at an hour a day), before and after:

| | before | after |
| --- | --- | --- |
| XP from level 1 to 50 | 115,240 | 61,640 |
| Gun prices | 400 / 1,200 / 2,500 | 400 / 3,000 / 7,000 |
| Level 5 / 10 / 15 | 0:28 d1 / 2:16 d3 / 5:44 d6 | 0:12 d1 / 0:44 d1 / 1:29 d2 |
| Level 25 / 30 | 18 h d19 / 27 h d28 | 5:10 d6 / 8:51 d9 |
| Level 50 | 87 h, day 88 | 47 h, day 47 |
| First purchase (Spritzer) | 0:28 d1 | 0:12 d1 |
| Thunderclapper bought | 5:44 d6 (had the coins at 1:00) | 2:00 d3 (level 15 at 1:29) |
| Stink Lobber bought | 18 h d19 (had the coins at 2:20) | 6:00 d6 (level 25 at 5:10) |
| Longest time holding a gun's coins while waiting for its level | 15.8 h | 2 min |
| Coins left after the last gun | 29,653 | 100 |

The other profiles, after:

| | casual | strong | grinder |
| --- | --- | --- | --- |
| Spritzer | 0:30 d1 (before: 0:55 d2) | 0:09 d1 | 0:09 d1 |
| Thunderclapper | 2:59 d4 (before: 11 h d16) | 1:35 d2 | 1:44 d1 |
| Stink Lobber | 10 h d14 (before: 36 h d48) | 4:47 d4 | 6:00 d3 |
| Level 50 | day 123 (before: 229) | day 18 (before: 33) | day 10 (before: 17) |
| Longest coins-but-no-level wait | 2.6 h (before: 32.6 h) | none (before: 8.2 h) | none (before: 8.2 h) |

Before, everything passed except two targets. **All three guns in a week**
missed because level 25 took an average player 18 hours (day 19). **Nothing
to buy for hours** missed by a lot: an average player earns about
1,800 coins an hour, mostly from spins and daily rewards, so they had the Thunderclapper's
coins after an hour and the Stink Lobber's after 2:20, then waited 5 and
18 hours for the levels, with 30,000 coins and nothing to buy at the end.
After the change, all targets pass.

Sensitivity: an average player with 2 eliminations and 1.5 assists a round
instead of 3 and 2 gets all three guns on day 8 and never waits more than 0.7 h. With 4
eliminations, they get them on day 6.

## What changed and why

- **XP curve** (`ProgressionConfig.xpToNext`): `100 + 40·(level−1)^1.25`
  became `100 + 0.25·(level−1)^2.5` (still rounded to tens). The first levels cost 100 XP
  each, then the cost rises ever faster: 730 at level 24 (was 2,110) and 4,090
  at 49 (was 5,150, close to the 5,000 per repeat reward after 50). Every
  level is cheaper than before, and most of the saving is in the middle,
  where the guns are. Level 10 (Recovery Burst) now lands in the first
  session, level 25 in the first week, and level 50 still takes the average
  player almost seven weeks and the grinder ten days. Level 2 still takes 100 XP. The 200 XP
  from five eliminations and the streak now reach level 3.
- **Thunderclapper 1,200 → 3,000 and Stink Lobber 2,500 → 7,000**
  (`WeaponConfig` prices). With the levels in reach, the old prices were a
  fraction of what timed rewards pay, so the guns cost nothing. The new prices make an
  average player's coins arrive with the levels (or a little after, so
  there's always something to save for). A strong player saves a while
  for a gun they've already unlocked. Prices can change without taking
  anything away: ownership never depends on price.
- **Unchanged**: every reward (eliminations, participation, daily track,
  spins and gifts) is kept so the first sessions still feel generous. The Spritzer stays at
  400, inside the early-unlock experiment's limit
  (`ExperimentConfig.EARLY_UNLOCK_MAX_PRICE`), and stays the 12-minute
  first purchase.

## Known gaps (after the beta)

- **No coin sink after the last gun.** Once a player owns all three guns, nothing in the beta
  costs coins, and an average player banks about 2,000 a day.
  `samples.unspentCoins` will climb. A coin sink (coin-priced cosmetics,
  for example) is a new system, so it's on the [roadmap](roadmap.md).
- The coin packs in `MonetizationConfig` (500 / 1,200 / 3,000) matched the
  old gun prices. Look at them before selling them.
- Profiles saved before this change keep their level and XP toward the next,
  and level faster from now on (levels aren't recomputed from `LifetimeXP`).
  One holding more XP than its level now needs takes the levels that XP
  pays for, with their unlocks, when it next loads (`EconomyService`).
