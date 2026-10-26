# Studio sign-off: Phases 1-6

Everything the automated specs can check is checked (`python3
scripts/run_specs.py`, 30 specs, including a 20-player, 20-minute soak).
Sections 0-6 are the core game (Phases 1-3); section 7 is Phases 4-6.
What's left needs real Roblox: physics, rendering, sound, the real network
and real DataStores. This is one session, in order, about an hour. Tick
each box; anything that doesn't match, note what you saw (a screenshot and
the Output window help).

## 0. Setup (once)

- [ ] Create the place **Fart Wars - Development** in a private experience.
      Publish it once (File → Publish to Roblox).
- [ ] Game Settings → Places: **Max Players 20**.
- [ ] Game Settings → Security: **Enable Studio Access to API Services**
      (saving needs it).
- [ ] Connect Rojo (`rojo serve` in the repository, Connect in the plugin),
      or open the `FartWars.rbxlx` build.
- [ ] Delete the default Baseplate and SpawnLocation if they're there.

## 1. Solo (Play)

- [ ] The Output shows `[Fart Wars] server ready` and no red errors.
- [ ] Chat `/fw selftest`. Expected: **0 failures**. Warnings for test
      controls and empty sound slots are normal. If the command does
      nothing, run `require(game.ServerScriptService.Server.TestControls).selftest()`
      in the server command bar instead, and note that chat commands don't
      arrive.
- [ ] Home screen over the live battlefield: title, team picker, PLAY,
      Weapons / Abilities / Progression / Settings, Rewards and
      Leaderboard (Coming Soon).
- [ ] Open each locker tab from the home screen. Nothing overlaps or runs
      off its card. Close it.
- [ ] PLAY opens "Choose a Team" (two cards with counts; a lock on a team
      you can't join). Pick one: you spawn on its pad with the weapon in
      your hand (the barrel should point forward; tell me if it's sideways
      or backwards), the controls card shows for a few seconds, and the
      HUD shows the score boxes and timer ("WAITING FOR PLAYERS" alone),
      coins and the four buttons top right, the gas and dash bars, the
      hotbar and the level bar.
- [ ] Press 1-4 or click a hotbar slot with a second weapon owned: in the
      first 3 seconds of a spawn it swaps at once; later it says it waits
      for your respawn and the slot shows NEXT.
- [ ] V switches first and third person a few times, also while moving.
- [ ] M opens the menu with a free mouse (also in first person); Resume
      closes it. Roblox's Esc menu has no Reset Character button.
- [ ] Hold Tab: the scoreboard (not Roblox's player list).
- [ ] Shift: a Fart Dash along the ground; not again for 3 seconds.
- [ ] Stand still 45 seconds: "BRO FELL ASLEEP MID-FART!"; at 60 you're
      back on the home screen as a spectator. PLAY again works.
- [ ] `/fw coins 5000`, `/fw xp 25000`: reward lines, level-up banners,
      the panel catches up. M → Weapons: buy the Spritzer ("Buying..." then
      "Bought!"). `/fw profile` says "saving".

## 2. Two players (Test → Clients and Servers, 2 players)

- [ ] The round starts (5:00 counting down on both clients, the same time).
- [ ] Shoot each other across a lane: tracers line up with the crosshair
      in first and third person; hit markers; headshots show bigger.
- [ ] Gas: the meter and the belly grow by stage; the critical outline
      pulses slowly (no flashing); at 100 a one-second countdown, then the
      explosion, the kill feed and "EXPLODED" card.
- [ ] Nobody takes gas for 3 seconds after spawning (unless they fire).
- [ ] A teammate can't be gassed (switch one client's team with
      `/fw team` and try).
- [ ] Barrels in the middle: two shots, a red outline, the orange blast a
      moment later, back after 20 seconds. Nothing through walls.
- [ ] Fart Dash never goes through a wall (try dashing into the spawn
      room's front wall from outside).
- [ ] Weapons (`/fw weapon spritzer`, `thunderclapper`, `stinklobber`):
      the Spritzer stops at 60 studs; the Thunderclapper walks slower;
      stink bombs arc (aim higher to throw farther) and the cloud is easy
      to see and gasses whoever stands in it.
- [ ] Q (`/fw ability recoveryburst`, then `gaspulse`): the other client
      sees the vent puff and the pulse ring; the HUD counts the cooldown.
- [ ] Equip a different weapon mid-fight: "you'll have it when you
      respawn", and the HUD's weapon line says so; it swaps on respawn.
- [ ] Five eliminations in a row: "BRO IS THE ALPHA FART!" on both screens.
- [ ] Let the round end (`/fw end 5`): results, a 15-second intermission,
      the next round starts by itself.

## 3. Saving

- [ ] Stop the test, Play again: your coins, level and weapons are back.
- [ ] In the Output after stopping: no "save failed" or "temporary
      profile" warnings.
- [ ] Turn API access off, Play: the panel says "Progress isn't saving
      this session", the shop says it's closed, nothing errors. Turn it
      back on.

## 4. Six or more players (Clients and Servers, 6-8)

- [ ] Teams split evenly (3v3 at six); a seventh player joins the
      smaller team; the home-screen team choice only allows fair picks.
- [ ] A chain reaction through a cluster: several explode, credited to the
      first killer; it stops (nothing loops forever).
- [ ] Join and leave a client several times mid-round: no leftover
      avatars, the scoreboard and team counts stay right.
- [ ] `/fw stats` afterwards: rejected requests near zero, errors 0.

## 5. Screens and settings

- [ ] At 1366×768 and 1920×1080 (Studio's device emulator or a resized
      window): home screen, HUD, locker, results and scoreboard are
      readable with nothing overlapping.
- [ ] Roblox graphics quality 1: effects thin out, the game stays smooth.
      Settings → Reduced effects does the same at any quality.
- [ ] Settings → Sound effects off: silence (once sounds are uploaded).
- [ ] Settings → Tips off: no more tips.

## 6. Full server (a published private server with friends)

Studio can't run 20 real clients. When you can, get 10+ people into the
private experience for 20 minutes:

- [ ] The server stays responsive (no rubber-banding), no repeated errors
      in the Developer Console (F9 → Server).
- [ ] `/fw stats` and the JSON in the server log: kills per minute, time to
      explosion, coins per 10 minutes, purchases, spawn deaths. Note how
      fun it was: the masterplan's gate is that people keep playing.

## 7. Phases 4-6 (rewards, the store, launch tooling, expansion)

Rewards and the store:

- [ ] A new profile: the Daily Rewards screen opens by itself on the home
      screen. CLAIM pays 100 coins; the countdown runs to 00:00 UTC.
- [ ] Ten minutes of play (not AFK): a free spin arrives. SPIN shows every
      prize's chance and pays one.
- [ ] Create the Starter Pack pass and the three coin packs in the Creator
      Hub, put their IDs in `MonetizationConfig`, and buy each with
      Studio's test purchases: coins arrive once; rejoin and they're still
      there; the pack's tracer, trail and emote are in the cosmetics grid;
      E shows the emote.
- [ ] A friend's account (a real Roblox friend) on your team for ten
      minutes: both get the squad bonus line.

Launch tooling:

- [ ] `/fw health` says OK; `/fw perf` lists the costliest paths in
      milliseconds; the home screen and Settings show `v0.6.0 (dev)`.
- [ ] M → PLAYERS: the other test client is listed; BLOCK shows Roblox's
      block prompt; HIDE EMOTES hides their E emote; REPORT → a reason
      says "Reported".
- [ ] Settings → LOW DETAIL: shadows go; VOLUME steps down to 0% and back.
- [ ] Studio → File → Studio Settings → Network → Incoming Replication Lag
      0.25, two clients: shots at a strafing player miss more, nothing hits
      that the server didn't see land, nothing errors.

Expansion (each is off as shipped; turn one on in `FeatureFlags`, test,
turn it back off unless you're keeping it):

- [ ] `/fw mode gascontrol`, then end the round (`/fw end 0`): the next
      round is Gas Control. The plaza ring shows; standing in it alone
      scores a point a second and the HUD says who holds it; with an enemy
      in it, CONTESTED and no points.
- [ ] `PRESTIGE = true`, `/fw xp 120000` to reach level 50, leave the match:
      Progression → PRESTIGE 1... shows the exact numbers; the second press
      resets you to level 1 with P1 on the level bar.
- [ ] `SEASONS = true` (and a test season in `SeasonConfig` with dates
      around today): 🏆 SEASON appears top right; the screen shows the
      tier, the challenges and the time left.
- [ ] `EVENTS = true`: within a few rounds the Bean Rain banner shows, rings
      mark where beans land (never in the spawn rooms), and walking over a
      bean pays coins and readies your Fart Dash.
- [ ] Settings → REDUCE MOTION, HUD SIZE 80% and 125% (panels stay in
      their corners), TEAM SYMBOLS (▲ over teammates; off removes it).

## Before any public release

- [ ] `GameConfig.TEST_CONTROLS.ENABLED = false` (or `USER_IDS` empty;
      in live servers only listed users can use them anyway).
- [ ] Upload the game's sounds and fill in `AudioConfig`.
- [ ] Decide `GameConfig.MODERATION.KICK_AT_FLAGS` (0 = review only)
      after looking at the flags real players trigger (`flags.*` in
      `/fw stats`).
