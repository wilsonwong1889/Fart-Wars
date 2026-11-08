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
`EventConfig`, `SeasonConfig` and `ChallengeConfig` (it doesn't copy their
values), so after changing a number you just run it again. It prints income, the time to each
level milestone, when each gun is unlocked, affordable and bought, and a
PASS/MISS line for each target.

**The model** uses expected values, with no luck involved. Each player plays one session
a day on a full 10v10 server in 5-minute rounds (11.4 an hour), claims
the daily reward at the start of it and spins every free spin straight
away. They buy each gun the moment it's both unlocked and affordable, cheapest first.
Combat pays per round. Participation, ten-minute gifts, the daily track,
weapon mastery (on the newest gun bought) and the level-50 rewards pay as
configured. The day's three daily challenges are done one a round over the
session's first three rounds (the slowest, "Play 3 rounds", takes three),
while `FeatureFlags.CHALLENGES` is on, as shipped. The squad bonus, Bean Rain and the season track are left out unless asked
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
casual player's figure is shown as a note. About 80% of a casual player's coins come
from time (spins, daily rewards, participation), while most of their
XP comes from combat, so with any prices an average player can reach in a
week, a casual player tends to get the coins before the level. The daily
challenges' XP (below) closes most of that gap: the casual player's longest
wait went from 2.6 hours to 10 minutes. More would need XP from other timed
rewards (for example spin weights moving from coins to the 150 XP prize).

## Daily challenges

Three a day for each player (`ChallengeConfig`, behind `FeatureFlags.CHALLENGES`, on as
shipped), new at 00:00 UTC, the same day boundary as the daily shop. Each
pays **40 coins and 75 XP** once, the moment it's done, so all three are
**120 coins and 225 XP a day**: about one free spin's coins and eleven
eliminations' XP. The reward leans on XP on purpose, since XP is what lags
for casual players (above). Progress is saved, so a challenge can be
finished over several sessions that day.

Servers are often mostly bots, and kills of or by bots pay nothing, so the
pool only has challenges one player alone with bots can do, and nothing a
bot does or suffers counts toward any of them:

| Challenge | What counts | Why bots can't feed it |
| --- | --- | --- |
| Play 3 rounds | rounds with at least a minute ACTIVE in them | a round takes its five minutes whoever is in it; AFK and the home screen don't count |
| Play for 15 minutes | minutes ACTIVE | the same clock as participation rewards |
| Win a round | a round won with at least a minute on the winning team | five minutes a round, and no switching onto the winners at the end |
| Fart Dash 30 times | dashes the server accepted | nobody else is involved |
| Blow up 3 gas barrels | barrels the player set off (a shot, or their own blast) | a bot's blast credits nobody; barrels come back only every 20 seconds |
| Start a barrel chain reaction | a barrel set off by one of the player's barrels | the same |

Each day picks three of different kinds ("Play 3 rounds" and "Play for 15
minutes" never come together), from the player's ID and the day, so they're
the same on every server all day. Left out: eliminations, assists, streaks
and gas dealt. Bots can't feed them, but they need real enemies, so a player
alone with bots couldn't finish them.

What the challenges change, from the model (without → with):

| | casual | average | strong | grinder |
| --- | --- | --- | --- | --- |
| week 1: coins / XP per hour | 1,438 / 676 → 1,579 / 976 | 1,784 / 1,323 → 1,904 / 1,548 | 2,216 / 2,368 → 2,296 / 2,518 | 1,679 / 2,270 → 1,767 / 2,345 |
| Spritzer bought | 0:30 → 0:10 (d1) | 0:12 → 0:10 (d1) | 0:09 → 0:07 (d1) | 0:09 → 0:07 (d1) |
| all three guns | 10 h d14 → 6:55 d10 | 6:00 d6 → 5:24 d6 | 4:47 d4 → 4:36 d4 | 6:00 d3 → 6:00 d2 |
| level 50 | day 123 → 85 | day 47 → 40 | day 18 → 17 | day 10 → 9 |
| longest coins-but-no-level wait | 2.6 h → 10 min | 2 min → none | 1 min, both | 1 min, both |

Every target still passes. The biggest change is for casual players, whose
225 XP a day is a third of what they earn; for the grinder it's a few per cent.

## Results

Income as shipped, daily challenges included:

| | casual | average | strong | grinder |
| --- | --- | --- | --- | --- |
| combat coins / XP per 10 min | 29 / 57 | 89 / 171 | 190 / 362 | 190 / 362 |
| combat coins / XP per hour | 171 / 343 | 531 / 1,029 | 1,143 / 2,171 | 1,143 / 2,171 |
| all sources, day 1: coins / XP per 10 min | 239 / 165 | 305 / 260 | 363 / 421 | 296 / 391 |
| all sources, week 1: coins / XP per hour | 1,579 / 976 | 1,904 / 1,548 | 2,296 / 2,518 | 1,767 / 2,345 |
| week 1 coins from spins / daily / challenges / combat | 47 / 22 / 10 / 11% | 43 / 14 / 6 / 28% | 24 / 8 / 3 / 50% | 15 / 5 / 2 / 65% |

A free spin is worth 125.5 coins and 22.5 XP on average, and six an hour is the
largest single coin source for anyone who isn't a strong player.

The XP-curve pass below came before the daily challenges, so its figures
are without them. Pacing for the average player (play time, day at an hour a day), before and after:

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
  costs coins, and an average player banks about 2,100 a day (2,000 before the daily
  challenges).
  `samples.unspentCoins` will climb. A coin sink (coin-priced cosmetics,
  for example) is a new system, so it's on the [roadmap](roadmap.md).
- The coin packs in `MonetizationConfig` (500 / 1,200 / 3,000) matched the
  old gun prices. Look at them before selling them.
- Profiles saved before this change keep their level and XP toward the next,
  and level faster from now on (levels aren't recomputed from `LifetimeXP`).
  One holding more XP than its level now needs takes the levels that XP
  pays for, with their unlocks, when it next loads (`EconomyService`).
