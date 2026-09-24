-- Tabla compacta: los tres pilotos (novato, tranquilo, completo) en cada nivel, con margen fino.
-- Argumentos: from, to, span, wingTop, seed.
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
Roblox.sim.seedSalt = ARGS.seed or 0

local MapBuilder = require(ServerScriptService.Glider.DevTools.MapBuilder:Clone())
MapBuilder.build({ dress = ARGS.dress ~= false })
local FlightTester = require(ServerScriptService.Glider.DevTools.FlightTester:Clone())
local map = workspace.Map
print(string.format("%-8s %-22s %-22s %-22s %-22s", "nivel", "título", "novato", "tranquilo", "completo"))
local index = ARGS.from or 1
while map:FindFirstChild(string.format("Level%02d", index)) and index <= (ARGS.to or math.huge) do
	local cells = {}
	for _, pilot in { FlightTester.NOVICE, FlightTester.CALM, FlightTester.FULL } do
		local _, info = FlightTester.run(index, nil, pilot)
		local margin = if info.minMargin == math.huge then ">32" else tostring(info.minMargin)
		table.insert(cells, string.format("%-22s", if info.ok then "ok  m " .. margin else "CHOCA"))
	end
	print(string.format("Level%02d  %-22s %s", index, map[string.format("Level%02d", index)]:GetAttribute("Title"), table.concat(cells, " ")))
	index += 1
end
