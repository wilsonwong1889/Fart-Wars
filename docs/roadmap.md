# Roadmap: after the beta

The masterplan keeps these for after the PC beta (4.4, 6.1-6.5). They are
written down so the earlier proposals aren't lost. None of them is needed
to launch, and each has open questions that need a decision before it's
built.

## Prestige

**The earlier proposal:** at level 50, reset coins, XP and weapons, and
give a 10% power increase per prestige.

**The problem:** a power increase is a lasting combat advantage for
veterans in a PvP game, and it compounds. New players would meet stronger
versions of the same weapons, which the beta's fairness goals rule out.
The proposal needs an **explicit balance decision** before any power
bonus is built.

**Safer options to test first:**

1. Cosmetic-only prestige: a badge, a name colour and a prestige-only
   cosmetic per rank, with no power.
2. A capped bonus that isn't combat (for example +10% coins), up to a
   fixed number of ranks.
3. Mode-specific normalisation: bonuses only in a separate casual
   playlist, never in the main queue.

**Whichever is chosen:**

- What persists through a reset: cosmetics, lifetime XP, lifetime stats,
  badges, mastery badges, and anything bought with Robux (passes and
  their contents). What resets: level, XP toward the next level, coins
  and weapons bought with coins (the Gas Blaster stays).
- The reset is irreversible. The screen shows exactly what will be lost
  and kept, with the numbers, and needs a second confirmation.
- The save format already has room: `SaveVersion`, `LifetimeXP` and a
  migration step. A prestige count would be a new field with a default.

## Battle pass (seasons)

Not in the beta. A free track plus a premium track, per season, was
discussed for after launch.

- Every challenge can be done through normal play, with no
  mode-specific grinding that empties the main queue.
- Rewards are cosmetic or coins. No exclusive combat power, ever.
- The premium track's price and contents are shown in full before buying.
  There is no fake urgency: a season's end date is real and shown.
- It reuses `EconomyService.grant` (one grant ID per tier) and the store's
  receipt rules.

## Events

Novelty events (bean rain, toilet eruptions, themed chaos) belong to
expansion, not the beta.

- Every hazard is telegraphed (a warning, a visible build-up) before it
  can hurt anyone.
- Each event has a performance budget (parts, particles, a per-tick cost)
  tested on low-end PCs before release.
- Events never stop the core shooting loop and never punish new players
  more than veterans.
- An event runs behind a feature flag and can be turned off without an
  update.

## Other later items

- **More modes and maps**: each needs a distinct objective, not just a
  new timer. Maps are added to rotation only after spawn-fairness and
  engagement tests. The timed 5-minute TDM and continuous play already
  exist behind `FeatureFlags.MATCH_MODE`.
- **Parties**: joining with friends must keep the team-balance
  safeguards (`TeamBalance` already weighs friends without stacking
  teams).
- **Mobile**: aiming, fire buttons, movement, dash and the UI redesigned
  for touch, with new performance budgets, before it's enabled.
- **Accessibility**: motion and flash reductions, HUD scaling, sound
  controls and team cues that don't rely on colour alone.
