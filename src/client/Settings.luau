-- The player's choices from the Settings screen. The controllers read them;
-- only the Settings screen changes them (SettingsController.choose), and
-- SettingsController keeps the ones the player picks in their profile, so
-- they're back next visit. The defaults here are SettingsConfig's.
return {
	-- Fewer puffs and clouds (stink clouds that gas you always show).
	reducedEffects = false,
	-- The game's sound effects, and their volume (0 to 1, on top of
	-- Roblox's own volume).
	sound = true,
	volume = 1,
	-- Low detail: no shadows and fewer effects, for slower PCs.
	lowDetail = false,
	-- Accessibility (Phase 6): less motion and flashing (still spectator
	-- shots, no pulsing outlines, softer bursts); the HUD's size; team
	-- symbols (▲ ●) next to names and over teammates, so teams don't rely
	-- on colour alone.
	reduceMotion = false,
	hudScale = 1,
	teamSymbols = true,
	-- Contextual tips (the "tips" experiment can start them off).
	tips = true,
	-- In third person, keep the mouse locked to the crosshair (on), or free
	-- like a cursor (off). First person always locks it; the unlock key and
	-- open screens free it either way (MouseLock).
	lockMouse = true,
	-- The camera's field of view (degrees) in both views, and how fast it
	-- turns with the mouse, times the player's own Roblox sensitivity
	-- (CameraController applies both).
	fieldOfView = 70,
	sensitivity = 1,
	-- The crosshair: its size (times the usual) and colour (a name in
	-- SettingsConfig.crosshairColors).
	crosshairSize = 1,
	crosshairColor = "White",
	-- Players whose emotes are hidden (the Players screen), by user ID. Not
	-- saved: it lasts the session.
	hiddenEmotes = {} :: { [number]: boolean },
	-- The ones the player has changed themselves (this visit or, once
	-- they've loaded, an earlier one).
	chosen = {} :: { [string]: boolean },
}
