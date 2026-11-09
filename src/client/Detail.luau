-- How much this PC draws. Low detail (Settings) turns shadows off here
-- (apply; Lighting changed here is local to this client). And the one rule
-- every effect follows for thinning out (reducedEffects): EffectsController's
-- puffs and clouds, WeaponFxController's particles, lights, smoke and hit
-- flash, ShotFx's bursts, rings, splats, lights and trails.
local Lighting = game:GetService("Lighting")

local Settings = require(script.Parent.Settings)
local HealthController = require(script.Parent.Controllers.HealthController)

local Detail = {}

-- On Automatic graphics quality, effects stay thin for this many seconds
-- (of frames drawn) after the frame rate was last under
-- HealthController.SLOW_FPS (40): long enough that thinning them out and
-- the frames coming back don't take turns.
Detail.SLOW_SECONDS = 20

local originalShadows: boolean? = nil

function Detail.apply()
	if originalShadows == nil then
		originalShadows = Lighting.GlobalShadows
	end
	Lighting.GlobalShadows = if Settings.lowDetail then false else originalShadows :: boolean
end

-- Whether effects thin out: with Reduced effects or Low detail on in
-- Settings; at a Roblox graphics quality of 3 or lower; and on Automatic
-- (most players' setting, which says nothing about the quality it picks),
-- while this PC is struggling: a frame rate under 40 in the last 20
-- seconds. Clouds that gas you are gameplay, and every shot's bolt says
-- where it went, so those always show (their modules say so).
function Detail.reducedEffects(): boolean
	if Settings.reducedEffects or Settings.lowDetail then
		return true
	end
	local level = HealthController.quality()
	if level and level > 0 then
		return level <= 3
	end
	local since = HealthController.sinceSlow()
	return since ~= nil and since < Detail.SLOW_SECONDS
end

return Detail
