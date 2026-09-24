-- Vuela el tutorial con el bot de verdad (TutorialBot.steer/step) y un jugador simulado, con las mismas
-- ecuaciones y detección de choque que FlightTester / GliderSession. El jugador solo decide SUBIR o BAJAR
-- (se abre o se cierra en su lado de la barra); el rumbo lo lleva el bot. ARGS.player = "lift" (por defecto)
-- o "idle" (no se mueve nunca: debe chocar en la loma, pero no por irse contra las paredes antes).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Glider.GliderConfig)
local GliderMath = require(ReplicatedStorage.Glider.GliderMath)
local GliderPhysics = require(ReplicatedStorage.Glider.GliderPhysics)

local template = Instance.new("Model")
template.Name = "AlaDelta"
local bar = Instance.new("Part")
bar.Name = "Agarre"
bar.Size = Vector3.new(1, 0.5, 10)
bar.Parent = template
template.Parent = workspace
local SPAN, WING_TOP = 32, 4

local MapBuilder = require(game.ServerScriptService.Glider.DevTools.MapBuilder:Clone())
MapBuilder.build({ dress = ARGS.dress ~= false })
local tutorial = workspace.Map.Tutorial
local Checkpoints = require(game.ServerScriptService.Glider.Checkpoints)
local TutorialBot = require(game.ServerScriptService.Glider.TutorialBot)
local course = Checkpoints.new(tutorial)

local params = RaycastParams.new()
params.FilterDescendantsInstances = { template }
local DT = 1 / 60
local inner, outer = Config.BarInnerOffset, Config.BarOuterOffset
local mode = ARGS.player or "lift"

local launch = tutorial.StartIsland.LaunchPoint.CFrame
local pos = launch.Position
local look = launch.LookVector
local state = GliderPhysics.newState(GliderMath.yawOf(look))
local dims = { span = SPAN, wingTop = WING_TOP }
local slots = {
	[-1] = { rig = true, position = -(inner + Config.StartOutward * (outer - inner)), axis = 0, velocity = 0 },
	[1] = { rig = true, position = inner + Config.StartOutward * (outer - inner), axis = 0, velocity = 0 },
}
local checkpoint, t, result = 0, 0, "OK"
local pending = {}
local maxAbsBalance = 0
local previous = pos

while t < 200 do
	t += DT
	local level = math.clamp(checkpoint + 1, 1, course:count())
	local forward = GliderPhysics.forwardOf(state.yaw)
	-- Jugador: solo sustentación (como el piloto del FlightTester, con 0.4 s de reacción), en su lado.
	if mode == "lift" then
		local goal = course:lookahead(level, pos, 100)
		local wantVy = 0
		if goal then
			local timeToGoal = math.max(((goal - pos) * Vector3.new(1, 0, 1)).Magnitude / Config.ForwardSpeed, 0.7)
			wantVy = math.clamp((goal.Y - pos.Y) / timeToGoal, -Config.MaxFallSpeed, Config.MaxClimbSpeed)
		end
		local out = GliderPhysics.liftInputFor(GliderPhysics.liftFor(wantVy))
		table.insert(pending, { at = t + 0.4, goal = -(inner + out * (outer - inner)) })
		while #pending > 1 and pending[2].at <= t do
			table.remove(pending, 1)
		end
		local order = pending[1]
		if order.at <= t then
			local d = order.goal - slots[-1].position
			slots[-1].axis = if math.abs(d) > 0.3 then math.sign(d) else 0
		end
	end
	-- Bot.
	local progress = course:progress(level, pos)
	local balance = TutorialBot.steer(pos, forward, course:lookahead(level, pos, TutorialBot.LOOKAHEAD))
	TutorialBot.step(slots, "Flying", {}, progress, balance)
	for _, slot in slots do
		slot.velocity = GliderMath.approach(slot.velocity, slot.axis * Config.PlayerSlideSpeed, Config.PlayerSlideResponse, DT)
		slot.position = math.clamp(slot.position + slot.velocity * DT, -outer, outer)
	end
	-- Mismo cálculo que GliderSession._computeInputs / _fly.
	local a, b = slots[-1].position, slots[1].position
	local liftInput, balanceInput = GliderPhysics.inputs(a, b)
	maxAbsBalance = math.max(maxAbsBalance, math.abs(balanceInput))
	GliderPhysics.step(state, liftInput, balanceInput, DT, GliderPhysics.ceilingLimit(state, pos, dims, params), -math.huge, 0)
	local velocity = GliderPhysics.velocity(state)
	local rootCFrame = GliderPhysics.cframe(state, pos)
	-- Choque.
	if workspace:Raycast(pos, Vector3.new(0, -(Config.FeetBelowRoot + Config.GroundClearance), 0), params) then
		local exitCF = tutorial[string.format("Level%02d", level)].Exit.CFrame
		local rel = exitCF:PointToObjectSpace(pos)
		result = string.format("CHOQUE con el suelo en el tramo %d (%.0f%%) · respecto a la salida: lateral %.0f, alto %.0f, delante %.0f", level, progress * 100, rel.X, rel.Y, -rel.Z)
		break
	end
	local center = rootCFrame * CFrame.new(0, (WING_TOP - Config.FeetBelowRoot) / 2, 0)
	local hit = workspace:Blockcast(center, Vector3.new(SPAN, WING_TOP + Config.FeetBelowRoot, 2), velocity.Unit * (velocity.Magnitude * DT + Config.ObstacleProbeDistance), params)
	if hit and hit.Normal.Y >= -0.5 then
		local exitCF = tutorial[string.format("Level%02d", level)].Exit.CFrame
		local rel = exitCF:PointToObjectSpace(pos)
		result = string.format("CHOQUE en el tramo %d (%.0f%%) contra %s · respecto a la salida: lateral %.0f, alto %.0f, delante %.0f", level, progress * 100, hit.Instance:GetFullName(), rel.X, rel.Y, -rel.Z)
		break
	end
	if ARGS.trace and math.floor(t * 60) % 60 == 0 then
		local exitCF = tutorial[string.format("Level%02d", level)].Exit.CFrame
		local rel = exitCF:PointToObjectSpace(pos)
		print(string.format("t=%4.1f lateral %6.1f alto %6.1f · jugador %.2f bot %.2f · balance %.2f deseado %.2f · yaw %.1f", t, rel.X, rel.Y, a, b, balanceInput, balance, math.deg(state.yaw)))
	end
	pos += velocity * DT
	local crossed = course:crossed(previous, pos, checkpoint)
	if crossed then
		checkpoint = crossed.index
		if crossed.final then
			result = string.format("META en %.1f s", t)
			break
		end
	end
	previous = pos
end
print(string.format("jugador=%s · %s · tramos superados %d · balance máx %.2f", mode, result, checkpoint, maxAbsBalance))
