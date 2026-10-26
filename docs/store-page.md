# Store page, thumbnails and the first funnel

The masterplan's 5.3: make the game understandable at a glance, promise
only what's in the build, and measure the path from impression to the
first shot.

## Title

**Fart Wars** (with "[PC Beta]" in the title or the first line of the
description while it's PC-only).

## Description

Lead with the loop, then say plainly what's in the beta:

> Blast rivals with gas, watch them inflate... and KABOOM! Every
> explosion blasts the enemies around them, so one good shot can set off
> a chain reaction across the battlefield.
>
> - Two teams, up to 10 v 10, on the Brainrot Battlefield
> - Five-minute rounds: most eliminations wins
> - Four weapons: Gas Blaster, Spritzer, Thunderclapper, Stink Lobber
> - Fart Dash (Shift) and Q abilities: Recovery Burst, Gas Pulse
> - Gas barrels for big chain explosions
> - Level up to 50, unlock weapons with coins you earn by playing
> - Daily rewards and free spins (odds shown in game)
>
> PC beta: mouse and keyboard only for now. Nothing you can buy makes
> your weapons stronger.

Keep it in step with each release: if a feature is turned off with a flag,
take it out of the description.

## Thumbnails

What every thumbnail shows (from the masterplan):

1. **Inflated avatars**: a Roblox avatar mid-inflation, belly huge, the gas
   meter in the red, with a rival aiming at them.
2. **A massive fart cloud**: a green explosion in the middle of a fight,
   bigger than the players.
3. **A chain reaction**: three or four explosions going off in a line
   along a lane, barrels included.
4. **Clear teams**: green Skibidi Stinkers against yellow Sigma Sharters,
   facing each other.
5. **A readable title**: "FART WARS" big enough to read at the size of a
   phone's game tile.

Rules: screenshots from the real game (staged with the test controls, not
mock-ups); nothing that isn't in the build (no maps, modes or weapons that
don't exist yet); no fake UI, fake player counts or "limited time" claims.

How to capture them: on the staging place, with two or more accounts,
`/fw gas 95` on a few players lined up near barrels, set up the camera,
then let one shot set them all off. Turn off the HUD with the Roblox
menu's screenshot mode, or crop it.

## Icon

One inflated, about-to-pop avatar face in the team green on a dark
background, with no text (the title is under the icon already).

## Creative testing

1. Upload two or three thumbnails and let Roblox rotate them (Creator Hub
   → the experience → Thumbnails; personalisation picks the best
   performer over time).
2. Change one thing at a time (a thumbnail, then the title, then the
   description's first line), each for at least a week.
3. Compare the funnel below before and after each change.

## The first funnel

| Step | Where |
| --- | --- |
| Impression → click (play button rate) | Creator Hub → Analytics → Acquisition |
| Click → join | Creator Hub (visits) |
| Join → PLAY | `funnel.new.played` over `funnel.new.joined`; Roblox's onboarding funnel step 2 |
| PLAY → first shot | `funnel.new.shot`; onboarding funnel step 3 (and `firsts.shot` for how long it takes) |
| First shot → first elimination | `funnel.new.elimination` |
| Ten minutes | `funnel.new.reached10Minutes` |
| Left before firing | `metrics.leftBeforeFirstShot.new` |

The onboarding funnel (Creator Hub → Analytics → Funnels → Onboarding)
shows these steps for new players across all servers.
