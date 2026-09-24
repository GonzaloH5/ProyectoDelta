--!strict
-- Compañero bot del tutorial: un personaje R15 colgado del ala como un jugador más (GliderSession.addBot) y
-- movido por el servidor en cada paso. Sigue las indicaciones que MapBuilder deja en cada tramo del
-- tutorial (atributo "Coach" del nivel, fracciones de su Route):
--   · sin lado (subir / bajar): hace de ESPEJO del jugador → la sustentación depende de lo que haga él
--     y el ala va recta.
--   · con lado (-1 izquierda / +1 derecha): se inclina hacia ese lado; el jugador tiene que acompañarlo
--     para girar de verdad (si se queda al otro lado, el peso se equilibra y el ala no gira).
-- Además publica en el ala el texto de la indicación (atributo TutorialHint) para la pantalla del jugador.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Glider"):WaitForChild("GliderConfig"))

local TutorialBot = {}

TutorialBot.SIDE = 1 -- el bot va en el hueco derecho; el jugador, en el izquierdo
local LEAN = 2.2 -- studs desde el centro de la barra a los que se inclina el bot (no del todo: el jugador cuenta)
local DEADBAND = 0.3 -- studs de tolerancia al colocarse
local COUNTDOWN_HINT = "Slide along the bar with A / D (or the ◀ ▶ buttons)"

export type Cue = { from: number, to: number, lean: number, hint: string }

-- Personaje del bot (sin avatar de ningún usuario: descripción por defecto con colores propios).
function TutorialBot.create(): Model?
	local description = Instance.new("HumanoidDescription")
	local skin = Color3.fromRGB(255, 205, 150)
	description.HeadColor = skin
	description.LeftArmColor = skin
	description.RightArmColor = skin
	description.TorsoColor = Color3.fromRGB(255, 205, 50)
	description.LeftLegColor = Color3.fromRGB(40, 60, 90)
	description.RightLegColor = Color3.fromRGB(40, 60, 90)
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not result then
		warn("[TutorialBot] No se pudo crear el bot: " .. tostring(result))
		return nil
	end
	local character = result :: Model
	character.Name = "Coach"
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = "Coach"
		humanoid.BreakJointsOnDeath = false
	end
	return character
end

-- Indicaciones de un nivel del tutorial (atributo "Coach": "desde|hasta|lado|texto;…").
function TutorialBot.cuesOf(level: Instance?): { Cue }
	local cues: { Cue } = {}
	local raw = level and level:GetAttribute("Coach")
	if type(raw) ~= "string" then
		return cues
	end
	for _, item in string.split(raw, ";") do
		local from, to, lean, hint = string.match(item, "^([^|]+)|([^|]+)|([^|]+)|(.*)$")
		if from and to and lean and hint then
			table.insert(cues, { from = tonumber(from) or 0, to = tonumber(to) or 1, lean = tonumber(lean) or 0, hint = hint })
		end
	end
	return cues
end

-- Un paso del bot. slots = huecos de la sesión (bot en SIDE, jugador en -SIDE); state = estado del vuelo;
-- progress = fracción recorrida del nivel. Devuelve el texto de la indicación actual.
function TutorialBot.step(slots: { [number]: any }, state: string, cues: { Cue }, progress: number): string
	local bot, player = slots[TutorialBot.SIDE], slots[-TutorialBot.SIDE]
	if not (bot and bot.rig) then
		return ""
	end
	local cue: Cue? = nil
	for _, candidate in cues do
		if progress >= candidate.from and progress < candidate.to then
			cue = candidate
			break
		end
	end
	local target = if cue and cue.lean ~= 0
		then cue.lean * LEAN
		elseif player and player.rig then -player.position -- espejo
		else TutorialBot.SIDE * (Config.BarInnerOffset + Config.StartOutward * (Config.BarOuterOffset - Config.BarInnerOffset))
	local delta = target - bot.position
	bot.axis = if math.abs(delta) > DEADBAND then math.sign(delta) else 0
	if state == "Countdown" then
		return COUNTDOWN_HINT
	end
	return if cue then cue.hint else ""
end

return TutorialBot
