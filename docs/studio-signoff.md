# Studio sign-off: Phases 1-3

Everything the automated specs can check is checked (`python3
scripts/run_specs.py`, 19 specs, including a 20-player, 20-minute soak).
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
- [ ] PLAY: you spawn on a team pad, the controls card shows for a few
      seconds, the HUD shows teams, timer ("WAITING FOR PLAYERS" alone),
      gas meter, weapon, dash line, and the progress panel (bottom right).
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

## Before any public release

- [ ] `GameConfig.TEST_CONTROLS.ENABLED = false` (or `USER_IDS` empty;
      in live servers only listed users can use them anyway).
- [ ] Upload the game's sounds and fill in `AudioConfig`.
- [ ] Decide `GameConfig.MODERATION.KICK_AT_FLAGS` (0 = review only)
      after looking at the flags real players trigger (`flags.*` in
      `/fw stats`).
