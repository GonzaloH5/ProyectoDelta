-- Flight School: el recorrido Map.Tutorial, las indicaciones, las marcas fantasma y el Coach (TutorialBot), sin Studio.
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
check("un solo tramo y meta", tutorial and tutorial:FindFirstChild("Level01") and not tutorial:FindFirstChild("Level02") and tutorial:FindFirstChild("FinishIsland"))
check("despegue", tutorial and tutorial.StartIsland:FindFirstChild("LaunchPoint") ~= nil)
check("Flight School: título y frase", tutorial.Level01:GetAttribute("Title") == "Flight School" and tutorial.Level01:GetAttribute("Tagline") ~= nil)
local launch = tutorial.StartIsland.LaunchPoint.Position
local entry = tutorial.Level01.Entry.Position
check("la boca está cerca del despegue (acción enseguida)", (entry - launch).Magnitude < 220, tostring((entry - launch).Magnitude))

local TutorialBot = require(game.ServerScriptService.Glider.TutorialBot)
local cues = TutorialBot.cuesOf(tutorial.Level01)
check("indicaciones", #cues >= 6, tostring(#cues))
check("primera: DIVE con fantasmas", cues[1].hint == "DIVE!" and cues[1].ghost == true, cues[1] and cues[1].hint)
check("indicaciones cortas (≤ 14 letras)", (function()
	for _, cue in cues do
		if #cue.hint > 14 then
			return false
		end
	end
	return true
end)())
local driftCue
for _, cue in cues do
	if cue.drift then
		driftCue = cue
	end
end
check("el Coach resbala una vez (en el combo, sin fantasmas)", driftCue ~= nil and not driftCue.ghost)

-- Indicación activa y textos especiales.
check("indicación activa", TutorialBot.activeCue(cues, "Flying", 0.05) == cues[1])
check("sin indicación fuera de vuelo", TutorialBot.activeCue(cues, "Countdown", 0.05) == nil)
check("cuenta atrás: cómo moverse", TutorialBot.hintFor(nil, "Countdown"):find("A / D") ~= nil)
check("tras la meta: aterrizar", TutorialBot.hintFor(nil, "Flying", true):find("land") ~= nil)

-- Marcas fantasma: subir = los dos fuera · bajar = los dos al centro · girar a la izquierda = izquierdo fuera,
-- derecho dentro · nivelado = los dos en medio.
local inner, outer = 1.1, 4.9
local l, r = TutorialBot.ghosts(1, 0)
check("fantasmas: subir", math.abs(l + outer) < 1e-6 and math.abs(r - outer) < 1e-6, string.format("%.2f %.2f", l, r))
l, r = TutorialBot.ghosts(0, 0)
check("fantasmas: bajar", math.abs(l + inner) < 1e-6 and math.abs(r - inner) < 1e-6)
l, r = TutorialBot.ghosts(0.5, 1)
check("fantasmas: girar a la izquierda", math.abs(l + outer) < 1e-6 and math.abs(r - inner) < 1e-6, string.format("%.2f %.2f", l, r))
l, r = TutorialBot.ghosts(0.5, 0)
check("fantasmas: nivelado", math.abs(l + r) < 1e-6 and math.abs(r - (inner + 0.5 * (outer - inner))) < 1e-6)

-- Rumbo: objetivo a la izquierda → balance positivo (girar a la izquierda), a la derecha → negativo.
local forward = Vector3.new(1, 0, 0) -- mirando a +X, la izquierda es -Z
check("objetivo delante: recto", math.abs(TutorialBot.steer(Vector3.zero, forward, Vector3.new(100, 0, 0))) < 1e-6)
check("objetivo a la izquierda", TutorialBot.steer(Vector3.zero, forward, Vector3.new(100, 0, -30)) > 0)
check("objetivo a la derecha", TutorialBot.steer(Vector3.zero, forward, Vector3.new(100, 0, 30)) < 0)

-- El Coach hace SU mitad y no copia al jugador.
local neutral = TutorialBot.targetFor(0.5, 0)
local slots = { [-1] = { rig = true, position = -3, axis = 0 }, [1] = { rig = true, position = neutral, axis = 0 } }
TutorialBot.step(slots, cues[1], 0, 0.5, 0)
check("recto y nivelado: el Coach se queda en su sitio", slots[1].axis == 0)
slots[-1].position = -1
TutorialBot.step(slots, cues[1], 0, 0.5, 0)
check("no copia al jugador", slots[1].axis == 0)
TutorialBot.step(slots, cues[1], 0, 0.9, 0)
check("subir: el Coach se abre (su mitad)", slots[1].axis == 1)
TutorialBot.step(slots, cues[1], 0.5, 0.5, 0)
check("girar a la izquierda: el Coach va a la izquierda", slots[1].axis == -1)
slots[1].position = neutral
TutorialBot.step(slots, driftCue, 0, 0.5, 2)
check("resbalón: el Coach se desplaza sin que haga falta girar", slots[1].axis ~= 0)
slots[1].position = neutral
TutorialBot.step(slots, nil, 0, 0.5, 0, true)
check("tras la meta: el Coach va al centro para aterrizar", slots[1].axis == -1)

-- Piezas nuevas en el recorrido principal: muros, ventanas y bifurcación (Route + RouteB).
local map = workspace.Map
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

-- Pasada la salida, el objetivo sigue delante.
local tcourse = require(game.ServerScriptService.Glider.Checkpoints).new(tutorial)
local exit = tutorial.Level01.Exit
local ahead = tcourse:lookahead(1, exit.Position + exit.CFrame.LookVector * 200, 110)
check("objetivo delante tras la salida", ahead and (ahead - exit.Position):Dot(exit.CFrame.LookVector) > 250, tostring(ahead))

print(if failures == 0 then "tutorial OK" else string.format("tutorial: %d fallos", failures))
