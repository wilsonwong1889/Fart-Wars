-- The practice yard (FeatureFlags.PRACTICE): the warm-up a player's first
-- PLAY goes to before choosing a team, and anyone can replay from the home
-- screen or Settings. PracticeService runs it on the server,
-- PracticeController shows it, ServerStorage.Maps.PracticeYard builds it.
-- The steps' words are here too, so the rules and what the screen says
-- about them stay together. Times are in seconds, distances in studs.
local PracticeConfig = {
	-- Where the yards go: one for each player in one, on a grid well clear
	-- of the battlefield (480 x 480 round the origin) and of each other,
	-- further apart than any weapon reaches (the Thunderclapper's 420).
	ORIGIN = Vector3.new(1200, 0, 0),
	SPACING = 600,
	COLUMNS = 5,

	-- The welcome before the first step, the cheer when a step is done, and
	-- the send-off after the last one.
	INTRO_SECONDS = 3,
	CHEER_SECONDS = 1.2,
	DONE_SECONDS = 3.5,
	-- A step's hint shows once it has taken this long.
	HINT_SECONDS = 12,
	-- However it's going, the yard ends (as finished) after this long.
	MAX_SECONDS = 150,
	-- How long the client waits for its yard to open before going on to
	-- the team screen without it.
	OPEN_TIMEOUT_SECONDS = 5,
	-- Back on the START pad this long after the avatar dies (nothing in the
	-- yard hurts it and the walls are higher than a jump, so it shouldn't).
	RESPAWN_SECONDS = 1,

	-- The dummies: a belly that grows from MIN_SIZE to MAX_SIZE across as
	-- its gas goes from 0 to 100, in a player's stage colours. At 100 it
	-- pops, and the blast gasses the dummies near it the way a player's
	-- explosion would (GameConfig.EXPLOSION). Back, empty, after
	-- RESPAWN_SECONDS.
	DUMMY = table.freeze({ MIN_SIZE = 3.6, MAX_SIZE = 6.4, RESPAWN_SECONDS = 2.5 }),
	-- The barrel: the battlefield's health and fuse (GameConfig.BARREL), but
	-- its blast fills every dummy it reaches, so the chain always goes off.
	-- Back, full, after RESPAWN_SECONDS.
	BARREL = table.freeze({ GAS = 100, RESPAWN_SECONDS = 6 }),
	-- Each blast in a chain goes off this long after the one that set it off.
	CHAIN_STAGGER_SECONDS = 0.15,
	-- A dummy is named in the shooter's hit markers (CombatEvents) by a
	-- number below any bot's, so nothing mistakes it for one.
	DUMMY_ID_BASE = -1000000,

	-- SKIP's key (the button needs a free mouse: Alt).
	SKIP_KEY = Enum.KeyCode.Return,
	SKIP_KEY_NAME = "ENTER",

	INTRO = table.freeze({
		title = "WELCOME TO THE PRACTICE YARD! 🧻",
		text = "30 seconds to get stinky, then you pick a team!",
	}),
	-- The steps, in order: `goal` is how many it takes (pops, dashes,
	-- barrels); `progress` (if any) counts them on the screen.
	STEPS = table.freeze({
		table.freeze({
			id = "shoot",
			goal = 3,
			title = "GAS THE DUMMIES! 🎯",
			text = "LEFT CLICK to pump them full of gas till they POP",
			progress = "%d / %d POPPED",
			hint = "Put the crosshair on a dummy and hold LEFT CLICK",
			cheer = "SHEEESH! 🔥",
		}),
		table.freeze({
			id = "dash",
			goal = 1,
			title = "FART DASH! 💨",
			text = "Hit SHIFT to zoom down the lane",
			hint = "Walk with WASD and tap SHIFT: you dash the way you're going",
			cheer = "ZOOOOOOM! 💨",
		}),
		table.freeze({
			id = "barrel",
			goal = 1,
			title = "BLOW UP THE BARREL! 🛢️",
			text = "Shoot the gas barrel and watch the CHAIN REACTION",
			hint = "It's at the end of the lane: two hits and it goes KABOOM",
			cheer = "KABOOOOOM! 💥",
		}),
	}),
	DONE = table.freeze({
		title = "YOU'RE READY TO RIP! 🔥",
		text = "Now pick a team and go stink up the battlefield!",
	}),
}

-- The step with `id` and where it comes in the order.
function PracticeConfig.step(id: string?): (any, number?)
	for index, step in PracticeConfig.STEPS do
		if step.id == id then
			return step, index
		end
	end
	return nil, nil
end

return table.freeze(PracticeConfig)
