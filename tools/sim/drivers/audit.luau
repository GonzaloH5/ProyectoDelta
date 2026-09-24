-- Regla de oro del vestido (MapDresser.audit) en todos los niveles, y piezas por modelo del mapa.
local ServerScriptService = game:GetService("ServerScriptService")
Roblox.sim.seedSalt = ARGS.seed or 0
local MapBuilder = require(ServerScriptService.Glider.DevTools.MapBuilder:Clone())
MapBuilder.build()
local MapDresser = require(ServerScriptService.Glider.DevTools.MapDresser:Clone())
local map = workspace.Map
local total, bad = 0, 0
local index = 1
while map:FindFirstChild(string.format("Level%02d", index)) do
	local level = map[string.format("Level%02d", index)]
	local worst, violations, detail = MapDresser.audit(level)
	total += 1
	if violations > 0 then
		bad += 1
	end
	print(string.format("%s %-9s peor invasión %.1f · %d rayos fuera de límite · %s", level.Name, tostring(level:GetAttribute("Biome")), worst, violations, detail))
	index += 1
end
print(string.format("Regla de oro: %d de %d niveles con invasiones por encima del límite", bad, total))
