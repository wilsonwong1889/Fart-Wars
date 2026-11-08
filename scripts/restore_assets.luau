-- Puts the 50 imported meshes back in ReplicatedStorage.Assets from their
-- asset IDs (art/export/mesh-assets.json), without importing anything: for
-- a place that has lost them, or a test place built with `rojo build`. The
-- game only needs each MeshPart's name and mesh; it places them itself. Skips
-- what's already there, so it's safe to run again. Paste it into View >
-- Command Bar in Edit mode, then save the place, or it's gone when Studio
-- closes: the imports only live in the place (Rojo leaves Assets alone).
local AssetService = game:GetService("AssetService")
local Assets = game:GetService("ReplicatedStorage"):WaitForChild("Assets")

local MESHES = {
	Effects = {
		GasBolt = { GasBolt = "rbxassetid://102454840374652" },
		MuzzleBurst = { MuzzleBurst = "rbxassetid://117991367394650" },
		ShockRing = { ShockRing = "rbxassetid://132362607264995" },
		Splat = { Splat = "rbxassetid://114059584117381" },
	},
	Props = {
		BarrelBand = { BarrelBand = "rbxassetid://124872637222839" },
		Bean = { Bean = "rbxassetid://131840900490803" },
		BeanCan = { BeanCan = "rbxassetid://134617265626994" },
		BeanLabel = { BeanLabel = "rbxassetid://93542300120380" },
		CoverWall = { CoverWall = "rbxassetid://125545050336013" },
		Crate = { Crate = "rbxassetid://95282470653652" },
		GasBarrel = { GasBarrel = "rbxassetid://73289176635348" },
		PlazaTiles = { PlazaTiles = "rbxassetid://70524103129677" },
		SpawnPad = { SpawnPad = "rbxassetid://133348224280428" },
		SpawnTiles = { SpawnTiles = "rbxassetid://72887744007329" },
		TallWall = { TallWall = "rbxassetid://128624843208358" },
		TankLid = { TankLid = "rbxassetid://105367715416261" },
		ToiletBowl = { ToiletBowl = "rbxassetid://103073382223064" },
		ToiletSeat = { ToiletSeat = "rbxassetid://77131207171066" },
		ToiletTank = { ToiletTank = "rbxassetid://120751096993273" },
		Wall = { Wall = "rbxassetid://119568730668847" },
		WallTrim = { WallTrim = "rbxassetid://71290438579380" },
	},
	Weapons = {
		GasBlaster = { Body = "rbxassetid://130559825563648", Gas = "rbxassetid://82783195363777", Glass = "rbxassetid://110060861221448", Grip = "rbxassetid://111707321403601", Metal = "rbxassetid://84532257532246", Needle = "rbxassetid://93364327195114", Pump = "rbxassetid://73661047254793", Trim = "rbxassetid://81381463176399" },
		Spritzer = { Body = "rbxassetid://122764036601609", Gas = "rbxassetid://75037620270681", Glass = "rbxassetid://70944839244210", Grip = "rbxassetid://72132652994662", Metal = "rbxassetid://98425913659086", Pump = "rbxassetid://108814018203314", Trim = "rbxassetid://95880494127736" },
		StinkLobber = { Body = "rbxassetid://82593292101075", Bomb = "rbxassetid://112509835087797", Fuse = "rbxassetid://131729851436647", Gas = "rbxassetid://112722656878543", Glass = "rbxassetid://98038215821514", Grip = "rbxassetid://104712253400217", Metal = "rbxassetid://85297190764022", Trim = "rbxassetid://99907051239110" },
		Thunderclapper = { Body = "rbxassetid://80796257443918", Gas = "rbxassetid://116931887511338", Glass = "rbxassetid://103992295526507", Grip = "rbxassetid://123140960760351", Metal = "rbxassetid://88956003025350", Trim = "rbxassetid://120518496484216" },
	},
}

local made, failed = 0, 0
for folderName, models in MESHES do
	local folder = Assets:WaitForChild(folderName)
	for modelName, parts in models do
		if not folder:FindFirstChild(modelName) then
			local model = Instance.new("Model")
			model.Name = modelName
			for name, id in parts do
				local ok, part = pcall(function()
					return AssetService:CreateMeshPartAsync(Content.fromUri(id), {
						CollisionFidelity = Enum.CollisionFidelity.Box,
						RenderFidelity = Enum.RenderFidelity.Automatic,
					})
				end)
				if ok then
					part.Name = name
					part.Anchored = true
					part.Parent = model
					made += 1
				else
					failed += 1
					warn(`[restore_assets] {modelName}.{name}: {part}`)
				end
				task.wait()
			end
			if #model:GetChildren() > 0 then
				model.Parent = folder
			end
		end
	end
end
print(`[restore_assets] {made} meshes made, {failed} failed. Save the place to keep them.`)
