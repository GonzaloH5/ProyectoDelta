--!strict
-- Compañero bot del tutorial: un personaje R15 colgado del ala como un jugador más (GliderSession.addBot) y
-- movido por el servidor en cada paso.
--
-- El bot PILOTA el rumbo: mira un punto de la línea ideal del tramo (Route) unos studs por delante
-- (persecución pura, como FlightTester) y se coloca en la barra para que el peso de los dos juntos dé el giro
-- necesario: centro de masa deseado = −giro × media barra, así que su sitio = 2 × centro − posición del jugador.
--   · Si vais bien encarados, eso es justo el ESPEJO del jugador: el ala va recta y subir o bajar depende de él.
--   · Si hay que girar, el bot se va hacia ese lado; si el jugador se queda al otro, el peso se compensa y el
--     giro sale a medias: hay que acompañarlo (lo dicen las indicaciones de las curvas).
-- Las indicaciones de texto vienen del atributo "Coach" de cada tramo (MapBuilder: TUTORIAL_LEVELS.coach) y se
-- publican en el ala (atributo TutorialHint) para la pantalla del jugador.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Glider = ReplicatedStorage:WaitForChild("Glider")
local Config = require(Glider:WaitForChild("GliderConfig"))
local GliderPhysics = require(Glider:WaitForChild("GliderPhysics"))

local TutorialBot = {}

TutorialBot.SIDE = 1 -- el bot va en el hueco derecho; el jugador, en el izquierdo
TutorialBot.LOOKAHEAD = 110 -- studs por delante a los que mira sobre la línea ideal
local DEADBAND = 0.3 -- studs de tolerancia al colocarse
local COUNTDOWN_HINT = "Slide along the bar with A / D (or the ◀ ▶ buttons)"

export type Cue = { from: number, to: number, hint: string }

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

-- Indicaciones de un nivel del tutorial (atributo "Coach": "desde|hasta|lado|texto;…"; el lado ya no se usa).
function TutorialBot.cuesOf(level: Instance?): { Cue }
	local cues: { Cue } = {}
	local raw = level and level:GetAttribute("Coach")
	if type(raw) ~= "string" then
		return cues
	end
	for _, item in string.split(raw, ";") do
		local from, to, _, hint = string.match(item, "^([^|]+)|([^|]+)|([^|]+)|(.*)$")
		if from and to and hint then
			table.insert(cues, { from = tonumber(from) or 0, to = tonumber(to) or 1, hint = hint })
		end
	end
	return cues
end

-- Balance (−1…1, positivo = girar a la izquierda) para ir hacia `goal` desde `position` con rumbo `forward`.
function TutorialBot.steer(position: Vector3, forward: Vector3, goal: Vector3?): number
	local wantTurn = GliderPhysics.pursuitTurn(position, forward, goal)
	return GliderPhysics.balanceInputFor(wantTurn / Config.MaxTurnRate)
end

-- Un paso del bot. slots = huecos de la sesión (bot en SIDE, jugador en -SIDE); balance = giro deseado
-- (TutorialBot.steer; 0 en la cuenta atrás); progress = fracción recorrida del nivel.
-- Devuelve el texto de la indicación actual.
function TutorialBot.step(slots: { [number]: any }, state: string, cues: { Cue }, progress: number, balance: number): string
	local bot, player = slots[TutorialBot.SIDE], slots[-TutorialBot.SIDE]
	if not (bot and bot.rig) then
		return ""
	end
	local outer = Config.BarOuterOffset
	local playerPosition = if player and player.rig then player.position else -bot.position
	-- balanceInput = −centro / media barra → centro deseado = −balance × media barra.
	local center = -balance * (outer - Config.BarInnerOffset) / 2
	local target = math.clamp(2 * center - playerPosition, -outer, outer)
	local delta = target - bot.position
	bot.axis = if math.abs(delta) > DEADBAND then math.sign(delta) else 0
	if state == "Countdown" then
		return COUNTDOWN_HINT
	end
	for _, cue in cues do
		if progress >= cue.from and progress < cue.to then
			return cue.hint
		end
	end
	return ""
end

return TutorialBot
