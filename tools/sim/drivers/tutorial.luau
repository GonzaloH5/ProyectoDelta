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
check("cuatro tramos y meta", tutorial and tutorial:FindFirstChild("Level04") and not tutorial:FindFirstChild("Level05") and tutorial:FindFirstChild("FinishIsland"))
-- Tramo BOOST: el bot se balancea en las indicaciones con acción 2.
local TutorialBot = require(game.ServerScriptService.Glider.TutorialBot)
local boostCues = TutorialBot.cuesOf(tutorial.Level04)
local pumpSlots = { [-1] = { rig = true, position = -3, axis = 0 }, [1] = { rig = true, position = 3, axis = 0 } }
TutorialBot.step(pumpSlots, "Flying", boostCues, 0.1, 0)
local pumpsEarly = pumpSlots[1].pumping == true
TutorialBot.step(pumpSlots, "Flying", boostCues, 0.5, 0)
check("el bot se balancea en BOOST y para con las plumas", pumpsEarly and pumpSlots[1].pumping == false)
check("despegue", tutorial and tutorial.StartIsland:FindFirstChild("LaunchPoint") ~= nil)

local TutorialBot = require(game.ServerScriptService.Glider.TutorialBot)
local cues = TutorialBot.cuesOf(tutorial.Level03)
check("indicaciones del giro", #cues == 4, tostring(#cues))
check("texto de la indicación", cues[1].hint == "Lean LEFT too: the Coach alone only turns half!", cues[1] and cues[1].hint)
local climb = TutorialBot.cuesOf(tutorial.Level01)
check("indicaciones de la subida (con resbalón al final)", #climb == 4 and climb[4].drift == true and not climb[1].drift)

-- Rumbo: objetivo a la izquierda → balance positivo (girar a la izquierda), a la derecha → negativo.
local forward = Vector3.new(1, 0, 0) -- mirando a +X, la izquierda es -Z
check("objetivo delante: recto", math.abs(TutorialBot.steer(Vector3.zero, forward, Vector3.new(100, 0, 0))) < 1e-6)
check("objetivo a la izquierda", TutorialBot.steer(Vector3.zero, forward, Vector3.new(100, 0, -30)) > 0)
check("objetivo a la derecha", TutorialBot.steer(Vector3.zero, forward, Vector3.new(100, 0, 30)) < 0)

-- Colocación: el bot hace SU mitad y no copia al jugador.
local neutral = TutorialBot.targetFor(0.5, 0)
local slots = { [-1] = { rig = true, position = -3, axis = 0 }, [1] = { rig = true, position = neutral, axis = 0 } }
local hint = TutorialBot.step(slots, "Flying", climb, 0.1, 0, 0.5, 0)
check("recto y nivelado: el bot se queda en su sitio", slots[1].axis == 0 and hint == climb[1].hint)
slots[-1].position = -1
TutorialBot.step(slots, "Flying", climb, 0.1, 0, 0.5, 0)
check("no copia al jugador (si el jugador se centra, el bot no se mueve)", slots[1].axis == 0)
TutorialBot.step(slots, "Flying", climb, 0.1, 0, 0.9, 0)
check("subir: el bot se abre (su mitad)", slots[1].axis == 1)
TutorialBot.step(slots, "Flying", cues, 0.2, 0.5, 0.5, 0)
check("girar a la izquierda: el bot va a la izquierda", slots[1].axis == -1)
slots[1].position = neutral
TutorialBot.step(slots, "Flying", cues, 0.6, -0.5, 0.5, 0)
check("girar a la derecha: el bot va a la derecha", slots[1].axis == 1)
-- Resbalón: aunque no haga falta girar, el bot se inclina solo (el jugador tiene que compensar).
slots[1].position = neutral
TutorialBot.step(slots, "Flying", climb, 0.9, 0, 0.5, 2)
check("resbalón: el bot se desplaza sin que haga falta girar", slots[1].axis ~= 0)
check("cuenta atrás", TutorialBot.step(slots, "Countdown", cues, 0, 0):find("A / D") ~= nil)

-- Los tramos pasados: el objetivo sigue delante aunque el ala ya haya salido del tramo.
local course = require(game.ServerScriptService.Glider.Checkpoints).new(tutorial)
local exit = tutorial.Level01.Exit.Position
local goal = course:lookahead(1, exit + Vector3.new(200, 0, 0), 110)
check("objetivo delante tras la salida", goal and goal.X > exit.X + 250, tostring(goal))

print(if failures == 0 then "tutorial OK" else string.format("tutorial: %d fallos", failures))
