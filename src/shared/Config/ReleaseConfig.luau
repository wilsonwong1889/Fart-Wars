-- The build: its version, and which places are staging and live
-- (docs/release.md has the process). The version is shown in Settings and
-- on the home screen, logged when a server starts, and in the stats, so a
-- report can always say which build it came from.
local ReleaseConfig = {}

-- major.minor.patch: minor for each release with new features (Phase 5 was
-- 0.5, Phase 6 0.6, the Blender weapons 0.7), patch for fixes only. Bump it
-- in the release commit.
ReleaseConfig.VERSION = "0.12.0"

-- Place IDs from the Creator Hub, 0 until the places exist. Anywhere else
-- (Studio, a copy) counts as "dev".
ReleaseConfig.STAGING_PLACE_ID = 0
ReleaseConfig.LIVE_PLACE_ID = 0

export type Channel = "live" | "staging" | "dev"

function ReleaseConfig.channel(placeId: number): Channel
	if ReleaseConfig.LIVE_PLACE_ID ~= 0 and placeId == ReleaseConfig.LIVE_PLACE_ID then
		return "live"
	elseif ReleaseConfig.STAGING_PLACE_ID ~= 0 and placeId == ReleaseConfig.STAGING_PLACE_ID then
		return "staging"
	end
	return "dev"
end

-- "0.5.0", or "0.5.0 (staging)" off the live place.
function ReleaseConfig.label(channel: string?): string
	return if channel == nil or channel == "live" then ReleaseConfig.VERSION else `{ReleaseConfig.VERSION} ({channel})`
end

return table.freeze(ReleaseConfig)
