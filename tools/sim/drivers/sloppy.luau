-- Dúo descuidado (FlightTester.SLOPPY) en modo juego: corazones, asistencia del nivel, puntos seguros y
-- reapariciones. Mide lo que perdona cada nivel: golpes (corazones perdidos), alas perdidas y tiempo.
-- Argumentos: from, to, seeds (semillas por nivel, 3 por defecto), dress.
local ServerScriptService = game:GetService("ServerScriptService")
local template = Instance.new("Model")
template.Name = "AlaDelta"
local bar = Instance.new("Part")
bar.Name = "Agarre"
bar.Size = Vector3.new(1, 0.5, 10)
bar.CFrame = CFrame.new(0, 400, 0)
bar.Parent = template
local wing = Instance.new("Part")
wing.Size = Vector3.new(14, 1, ARGS.span or 32)
wing.CFrame = CFrame.new(0, 400 + (ARGS.wingTop or 4) - 0.5, 0)
wing.Parent = template
template.Parent = workspace

local MapBuilder = require(ServerScriptService.Glider.DevTools.MapBuilder:Clone())
MapBuilder.build({ dress = ARGS.dress ~= false })
local FlightTester = require(ServerScriptService.Glider.DevTools.FlightTester:Clone())
local map = workspace.Map
local seeds = ARGS.seeds or 3

print(string.format("%-8s %-22s %8s %8s %8s %8s", "nivel", "título", "golpes", "alas", "llega", "tiempo"))
local totals = { hits = 0, losses = 0, finished = 0, runs = 0 }
local index = ARGS.from or 1
while map:FindFirstChild(string.format("Level%02d", index)) and index <= (ARGS.to or math.huge) do
	local hits, losses, finished, time = 0, 0, 0, 0
	for seed = 1, seeds do
		local pilot = table.clone(FlightTester.SLOPPY)
		pilot.seed = seed * 7919 + index
		pilot.stopOnLoss = false
		local _, info = FlightTester.run(index, nil, pilot)
		hits += info.hits
		losses += info.losses
		time += info.time
		if info.time < 150 then
			finished += 1
		end
	end
	totals.hits += hits
	totals.losses += losses
	totals.finished += finished
	totals.runs += seeds
	print(string.format("Level%02d  %-22s %8.1f %8.1f %6d/%d %7.1fs", index, map[string.format("Level%02d", index)]:GetAttribute("Title"), hits / seeds, losses / seeds, finished, seeds, time / seeds))
	index += 1
end
print(string.format("Total: %.2f golpes y %.2f alas perdidas por nivel · llegan %d de %d", totals.hits / math.max(totals.runs, 1), totals.losses / math.max(totals.runs, 1), totals.finished, totals.runs))
