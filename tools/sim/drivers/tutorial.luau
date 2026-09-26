-- Flight School: el recorrido Map.Tutorial (conectado con el principal), las indicaciones y las marcas fantasma.
-- También comprueba las piezas nuevas de MapBuilder que usa (muro, ventana, bifurcación con RouteB) y que la
-- asistencia sigue el carril más cercano (Checkpoints.lookahead).
local failures = 0
local function check(name, ok, detail)
	if not ok then
		failures += 1
		print("FALLA", name, detail or "")
	end
end

local MapBuilder = require(game.ServerScriptService.Glider.DevTools.MapBuilder:Clone())
MapBuilder.build({ dress = false })
local tutorial = workspace.Map:FindFirstChild("Tutorial")
check("existe Map.Tutorial", tutorial ~= nil)
check("un solo tramo y línea de relevo", tutorial and tutorial:FindFirstChild("Level01") and not tutorial:FindFirstChild("Level02") and tutorial:FindFirstChild("FinishIsland"))
check("despegue", tutorial and tutorial.StartIsland:FindFirstChild("LaunchPoint") ~= nil)
check("Flight School: título y frase", tutorial.Level01:GetAttribute("Title") == "Flight School" and tutorial.Level01:GetAttribute("Tagline") ~= nil)
local launch = tutorial.StartIsland.LaunchPoint.Position
local entry = tutorial.Level01.Entry.Position
check("la boca está cerca del despegue (acción enseguida)", (entry - launch).Magnitude < 220, tostring((entry - launch).Magnitude))

-- Recorrido conectado: Flight School desemboca justo en el valle de la StartIsland del recorrido principal, y la
-- línea de relevo (meta del tutorial) está en el despegue de los veteranos.
local map = workspace.Map
local exitPos = tutorial.Level01.Exit.Position
local startValley = map.StartIsland:FindFirstChild("Valley")
check("sin pared detrás de la StartIsland (ahí llega Flight School)", map.StartIsland:FindFirstChild("BackWall") == nil)
local veteranLaunch = map.StartIsland.LaunchPoint
local handoff = tutorial.FinishIsland:FindFirstChild("FinishLine")
check("línea de relevo en el despegue de los veteranos", handoff and (handoff.Position - veteranLaunch.Position).Magnitude < 1, handoff and tostring((handoff.Position - veteranLaunch.Position).Magnitude))
local toLaunch = veteranLaunch.Position - exitPos
check("la salida de Flight School da a la StartIsland (mismo rumbo, delante del despegue)", math.abs(toLaunch.Y) < 1 and math.abs(toLaunch.Z) < 1 and toLaunch.X > 0 and toLaunch.X < 400, tostring(toLaunch))
check("Flight School sin valle de meta propio", tutorial.FinishIsland:FindFirstChild("Valley") == nil and startValley ~= nil)

local FlightSchool = require(game.ServerScriptService.Glider.FlightSchool)
local cues = FlightSchool.cuesOf(tutorial.Level01)
check("indicaciones", #cues >= 5, tostring(#cues))
check("primera: DIVE con fantasmas", cues[1].hint == "DIVE!" and cues[1].ghost == true, cues[1] and cues[1].hint)
check("indicaciones cortas (≤ 14 letras)", (function()
	for _, cue in cues do
		if #cue.hint > 14 then
			return false
		end
	end
	return true
end)())
check("indicación activa", FlightSchool.activeCue(cues, "Flying", 0.05) == cues[1])
check("sin indicación fuera de vuelo", FlightSchool.activeCue(cues, "Countdown", 0.05) == nil)
check("cuenta atrás: cómo moverse", FlightSchool.hintFor(nil, "Countdown"):find("A / D") ~= nil)

-- Marcas fantasma: subir = los dos fuera · bajar = los dos al centro · girar a la izquierda = izquierdo fuera,
-- derecho dentro · nivelado = los dos en medio.
local inner, outer = 1.1, 4.9
local l, r = FlightSchool.ghosts(1, 0)
check("fantasmas: subir", math.abs(l + outer) < 1e-6 and math.abs(r - outer) < 1e-6, string.format("%.2f %.2f", l, r))
l, r = FlightSchool.ghosts(0, 0)
check("fantasmas: bajar", math.abs(l + inner) < 1e-6 and math.abs(r - inner) < 1e-6)
l, r = FlightSchool.ghosts(0.5, 1)
check("fantasmas: girar a la izquierda", math.abs(l + outer) < 1e-6 and math.abs(r - inner) < 1e-6, string.format("%.2f %.2f", l, r))
l, r = FlightSchool.ghosts(0.5, 0)
check("fantasmas: nivelado", math.abs(l + r) < 1e-6 and math.abs(r - (inner + 0.5 * (outer - inner))) < 1e-6)

-- Rumbo: objetivo a la izquierda → balance positivo (girar a la izquierda), a la derecha → negativo.
local forward = Vector3.new(1, 0, 0) -- mirando a +X, la izquierda es -Z
check("objetivo delante: recto", math.abs(FlightSchool.steer(Vector3.zero, forward, Vector3.new(100, 0, 0))) < 1e-6)
check("objetivo a la izquierda", FlightSchool.steer(Vector3.zero, forward, Vector3.new(100, 0, -30)) > 0)
check("objetivo a la derecha", FlightSchool.steer(Vector3.zero, forward, Vector3.new(100, 0, 30)) < 0)

-- Piezas nuevas en el recorrido principal: muros, ventanas y bifurcación (Route + RouteB).
local function has(level, pattern)
	for _, part in map[level].Features:GetChildren() do
		if part.Name:find(pattern) then
			return true
		end
	end
	return false
end
check("nivel 1: muros (subir obliga)", has("Level01", "^Barrier"))
check("nivel 3: ventanas", has("Level03", "^Window"))
check("nivel 5: bifurcación con dos líneas", has("Level05", "^Divider") and map.Level05:FindFirstChild("RouteB") ~= nil)
check("nivel 5: cada nivel tiene su frase", map.Level05:GetAttribute("Tagline") ~= nil)

-- La asistencia sigue el carril por el que va el ala (la línea más cercana).
local course = require(game.ServerScriptService.Glider.Checkpoints).new(map)
local routeB = map.Level05.RouteB:GetChildren()
table.sort(routeB, function(a, b)
	return a.Name < b.Name
end)
local routeA = map.Level05.Route:GetChildren()
table.sort(routeA, function(a, b)
	return a.Name < b.Name
end)
-- Un punto del carril B que no está en la Route.
local onlyB
for _, pb in routeB do
	local shared = false
	for _, pa in routeA do
		if (pa.Position - pb.Position).Magnitude < 1 then
			shared = true
		end
	end
	if not shared then
		onlyB = pb
		break
	end
end
check("RouteB tiene tramo propio", onlyB ~= nil)
if onlyB then
	local goal = course:lookahead(5, onlyB.Position, 60)
	local distanceToB = math.huge
	for _, pb in routeB do
		distanceToB = math.min(distanceToB, (pb.Position - goal).Magnitude)
	end
	check("en el carril B, la asistencia apunta por el carril B", goal ~= nil and distanceToB < 80, tostring(distanceToB))
end

print(if failures == 0 then "tutorial OK" else string.format("tutorial: %d fallos", failures))
