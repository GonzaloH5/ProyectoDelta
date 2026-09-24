-- Traza un vuelo del FlightTester: posición respecto al centro del corredor (lateral, alto) cada `every` s.
-- Argumentos: level, pilot (novice/calm/full), from/to (segundos a mostrar), every.
local ServerScriptService = game:GetService("ServerScriptService")
local template = Instance.new("Model")
template.Name = "AlaDelta"
local bar = Instance.new("Part")
bar.Name = "Agarre"
bar.Size = Vector3.new(1, 0.5, 10)
bar.CFrame = CFrame.new(0, 400, 0)
bar.Parent = template
local wing = Instance.new("Part")
wing.Size = Vector3.new(14, 1, 32)
wing.CFrame = CFrame.new(0, 403.5, 0)
wing.Parent = template
template.Parent = workspace
local MapBuilder = require(ServerScriptService.Glider.DevTools.MapBuilder:Clone())
MapBuilder.build({ dress = ARGS.dress ~= false })
local FlightTester = require(ServerScriptService.Glider.DevTools.FlightTester:Clone())
local Checkpoints = require(ServerScriptService.Glider.Checkpoints)
local course = Checkpoints.new(workspace.Map)
local pilots = { novice = FlightTester.NOVICE, calm = FlightTester.CALM, full = FlightTester.FULL }
local pilot = table.clone(pilots[ARGS.pilot or "novice"])
local index = ARGS.level or 1
local every = ARGS.every or 0.25
local nextT = 0
pilot.trace = function(t, pos, state, level)
	if t < (ARGS.from or 0) or t > (ARGS.to or math.huge) or t < nextT then
		return
	end
	nextT = t + every
	-- Distancia a la línea ideal (Route) y fracción recorrida.
	local goal = course:lookahead(index, pos, 0)
	local offset = if goal then pos - goal else Vector3.zero
	local forward = if goal then (course:lookahead(index, pos, 5) - goal) else Vector3.xAxis
	forward = Vector3.new(forward.X, 0, forward.Z).Unit
	local right = Vector3.new(-forward.Z, 0, forward.X)
	print(string.format("t=%5.2f s=%.0f%% lateral %6.1f alto %6.1f · yaw %6.1f roll %5.1f turn %5.1f vy %5.1f speed %4.1f", t, course:progress(index, pos) * 100, offset:Dot(right), offset.Y, math.deg(state.yaw), state.roll, state.turnRate, state.verticalSpeed, state.speed))
end
print((FlightTester.run(index, nil, pilot)))
