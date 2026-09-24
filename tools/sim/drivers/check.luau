-- Genera el mapa con MapBuilder (con vestido, salvo dress=false) y pasa la regla de dificultad del
-- FlightTester. Argumentos: from, to (niveles), dress (true/false), seed (semilla extra del vestido),
-- span / wingTop (medidas del ala: la plantilla real está en el place, no en el repo), runAll=true.
local ServerScriptService = game:GetService("ServerScriptService")

local SPAN = ARGS.span or 32 -- envergadura (MapBuilder: "envergadura 32")
local WING_TOP = ARGS.wingTop or 4 -- de la barra al punto más alto del ala

-- Plantilla AlaDelta mínima: barra "Agarre" y un ala con la envergadura en Z (la plantilla mira a +X).
local template = Instance.new("Model")
template.Name = "AlaDelta"
local bar = Instance.new("Part")
bar.Name = "Agarre"
bar.Size = Vector3.new(1, 0.5, 10)
bar.CFrame = CFrame.new(0, 400, 0)
bar.Parent = template
local wing = Instance.new("Part")
wing.Name = "Ala"
wing.Size = Vector3.new(14, 1, SPAN)
wing.CFrame = CFrame.new(0, 400 + WING_TOP - 0.5, 0)
wing.Parent = template
template.Parent = workspace

Roblox.sim.seedSalt = ARGS.seed or 0 -- otra semilla para el vestido aleatorio (en Studio sale distinto)
local t0 = realClock()
local MapBuilder = require(ServerScriptService.Glider.DevTools.MapBuilder:Clone())
local summary = MapBuilder.build({ dress = ARGS.dress ~= false })
if ARGS.summary ~= false then
	print(summary)
end
print(string.format("[sim] mapa generado en %.1f s", realClock() - t0))

local FlightTester = require(ServerScriptService.Glider.DevTools.FlightTester:Clone())
t0 = realClock()
if ARGS.runAll then
	print(FlightTester.runAll())
else
	print(FlightTester.checkRules(ARGS.from, ARGS.to))
	print(FlightTester.checkTutorial())
end
print(string.format("[sim] pruebas en %.1f s", realClock() - t0))
