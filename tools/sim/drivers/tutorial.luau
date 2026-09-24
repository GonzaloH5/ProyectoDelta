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
check("indicaciones del giro", #cues == 4 and cues[1].lean == -1 and cues[3].lean == 1, tostring(#cues))
check("texto de la indicación", cues[1].hint == "Lean LEFT together to turn left!", cues[1] and cues[1].hint)
local climb = TutorialBot.cuesOf(tutorial.Level01)
check("subida sin lado (espejo)", #climb == 2 and climb[1].lean == 0)

-- Paso del bot: espejo y giro.
local slots = { [-1] = { rig = true, position = -3, axis = 0 }, [1] = { rig = true, position = 3, axis = 0 } }
local hint = TutorialBot.step(slots, "Flying", climb, 0.3)
check("espejo: si el jugador está en -3, el bot se queda en +3", slots[1].axis == 0 and hint == climb[1].hint)
slots[-1].position = -1
TutorialBot.step(slots, "Flying", climb, 0.3)
check("espejo: el jugador se centra y el bot va hacia el centro", slots[1].axis == -1)
TutorialBot.step(slots, "Flying", cues, 0.2)
check("giro a la izquierda: el bot va a la izquierda", slots[1].axis == -1)
slots[1].position = -2.2
TutorialBot.step(slots, "Flying", cues, 0.2)
check("giro: llegó a su sitio", slots[1].axis == 0)
TutorialBot.step(slots, "Flying", cues, 0.6)
check("giro a la derecha", slots[1].axis == 1)
check("cuenta atrás", TutorialBot.step(slots, "Countdown", cues, 0):find("A / D") ~= nil)

print(if failures == 0 then "tutorial OK" else string.format("tutorial: %d fallos", failures))
