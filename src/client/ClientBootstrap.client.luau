-- Starts the client: the match state first, then input, camera and the
-- screens. Controllers render and send requests; they never decide teams
-- or results.
local Client = script.Parent
local Controllers = Client.Controllers

require(Client.ClientState).start()
require(Controllers.InputController).start()
require(Controllers.CameraController).start()
require(Controllers.CombatController).start()
require(Controllers.EffectsController).start()
require(Controllers.HUDController).start()
require(Controllers.ProgressController).start()
require(Controllers.LockerController).start()
require(Controllers.HomeController).start()
