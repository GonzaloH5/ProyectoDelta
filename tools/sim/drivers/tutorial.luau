-- Tutorial: el recorrido Map.Tutorial y el bot (TutorialBot.cuesOf / step), sin Studio.
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
check("tres tramos y meta", tutorial and tutorial:FindFirstChild("Level03") and not tutorial:FindFirstChild("Level04") and tutorial:FindFirstChild("FinishIsland"))
check("despegue", tutorial and tutorial.StartIsland:FindFirstChild("LaunchPoint") ~= nil)

local TutorialBot = require(game.ServerScriptService.Glider.TutorialBot)
local cues = TutorialBot.cuesOf(tutorial.Level03)
check("indicaciones del giro", #cues == 4, tostring(#cues))
check("texto de la indicación", cues[1].hint == "Lean LEFT with the Coach to turn left!", cues[1] and cues[1].hint)
local climb = TutorialBot.cuesOf(tutorial.Level01)
check("indicaciones de la subida", #climb == 2)

-- Rumbo: objetivo a la izquierda → balance positivo (girar a la izquierda), a la derecha → negativo.
local forward = Vector3.new(1, 0, 0) -- mirando a +X, la izquierda es -Z
check("objetivo delante: recto", math.abs(TutorialBot.steer(Vector3.zero, forward, Vector3.new(100, 0, 0))) < 1e-6)
check("objetivo a la izquierda", TutorialBot.steer(Vector3.zero, forward, Vector3.new(100, 0, -30)) > 0)
check("objetivo a la derecha", TutorialBot.steer(Vector3.zero, forward, Vector3.new(100, 0, 30)) < 0)

-- Colocación: recto = espejo del jugador; girar = el bot desplaza el peso hacia ese lado.
local slots = { [-1] = { rig = true, position = -3, axis = 0 }, [1] = { rig = true, position = 3, axis = 0 } }
local hint = TutorialBot.step(slots, "Flying", climb, 0.3, 0)
check("recto: espejo (el bot se queda en +3)", slots[1].axis == 0 and hint == climb[1].hint)
slots[-1].position = -1
TutorialBot.step(slots, "Flying", climb, 0.3, 0)
check("recto: el jugador se centra y el bot también", slots[1].axis == -1)
TutorialBot.step(slots, "Flying", cues, 0.2, 0.5)
check("girar a la izquierda: el bot va a la izquierda", slots[1].axis == -1)
slots[1].position = 0
TutorialBot.step(slots, "Flying", cues, 0.6, -0.5)
check("girar a la derecha: el bot va a la derecha", slots[1].axis == 1)
check("cuenta atrás", TutorialBot.step(slots, "Countdown", cues, 0, 0):find("A / D") ~= nil)

-- Los tramos pasados: el objetivo sigue delante aunque el ala ya haya salido del tramo.
local course = require(game.ServerScriptService.Glider.Checkpoints).new(tutorial)
local exit = tutorial.Level01.Exit.Position
local goal = course:lookahead(1, exit + Vector3.new(200, 0, 0), 110)
check("objetivo delante tras la salida", goal and goal.X > exit.X + 250, tostring(goal))

print(if failures == 0 then "tutorial OK" else string.format("tutorial: %d fallos", failures))
