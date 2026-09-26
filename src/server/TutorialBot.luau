--!strict
-- Compañero bot del tutorial: un personaje R15 colgado del ala como un jugador más (GliderSession.addBot) y
-- movido por el servidor en cada paso.
--
-- El bot hace SOLO SU MITAD, como un compañero real: calcula lo que haría falta para seguir la línea ideal
-- (subida por la altura del punto de mira, giro por persecución pura) y se coloca donde le tocaría a él si el
-- jugador hiciera la otra mitad. NO copia al jugador: si el jugador no se abre, el ala sube a medias; si no se
-- inclina con él, gira a medias; si se va a un lado, el ala se va con él. Hay que corregir de verdad.
-- Además, en los tramos marcados (acción 3) el bot "resbala": se inclina solo hacia un lado y otro durante unos
-- segundos y el jugador tiene que compensarlo inclinándose al contrario para mantener el ala recta.
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
local DRIFT = 0.9 -- desequilibrio (BalanceInput) de los resbalones del bot
local MAX_STEER = 0.6 -- el bot nunca pide más giro que esto: en las curvas cerradas el jugador tiene que inclinarse
local DRIFT_RATE = 0.8 -- rad/s: un resbalón hacia cada lado cada ~4 s
local DRIFT_SELF_CORRECTION = 0 -- durante un resbalón el bot no corrige el rumbo: lo tiene que hacer el jugador
local COUNTDOWN_HINT = "Slide along the bar with A / D (or the ◀ ▶ buttons)"
local LAND_HINT = "Great! Both to the CENTER to glide down and land on the island"
local LAND_LIFT = 0.15 -- tras la meta el bot va hacia el centro (bajar suave) para aterrizar

export type Cue = { from: number, to: number, hint: string, pump: boolean, drift: boolean }

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

-- Indicaciones de un nivel del tutorial (atributo "Coach": "desde|hasta|acción|texto;…"; acción 2 = el bot se
-- balancea (impulso) durante esa indicación · acción 3 = el bot resbala: el jugador tiene que compensarlo).
function TutorialBot.cuesOf(level: Instance?): { Cue }
	local cues: { Cue } = {}
	local raw = level and level:GetAttribute("Coach")
	if type(raw) ~= "string" then
		return cues
	end
	for _, item in string.split(raw, ";") do
		local from, to, action, hint = string.match(item, "^([^|]+)|([^|]+)|([^|]+)|(.*)$")
		if from and to and hint then
			table.insert(cues, { from = tonumber(from) or 0, to = tonumber(to) or 1, hint = hint, pump = tonumber(action) == 2, drift = tonumber(action) == 3 })
		end
	end
	return cues
end

-- Balance (−1…1, positivo = girar a la izquierda) para ir hacia `goal` desde `position` con rumbo `forward`.
function TutorialBot.steer(position: Vector3, forward: Vector3, goal: Vector3?): number
	local wantTurn = GliderPhysics.pursuitTurn(position, forward, goal)
	return GliderPhysics.balanceInputFor(wantTurn / Config.MaxTurnRate)
end

-- LiftInput que hace falta para llegar a la altura de `goal` (como el piloto del FlightTester).
function TutorialBot.liftFor(position: Vector3, goal: Vector3?, speed: number?): number
	if not goal then
		return Config.NeutralLiftPoint
	end
	local flat = ((goal - position) * Vector3.new(1, 0, 1)).Magnitude
	local timeToGoal = math.max(flat / (speed or Config.ForwardSpeed), 0.7)
	local wantVy = math.clamp((goal.Y - position.Y) / timeToGoal, -Config.MaxFallSpeed, Config.MaxClimbSpeed)
	return GliderPhysics.liftInputFor(GliderPhysics.liftFor(wantVy))
end

-- Sitio del bot en la barra para su mitad: lift = LiftInput que hace falta, balance = BalanceInput que hace
-- falta (entre los dos). Con el jugador en -(inner + oa·r) y el bot en +(inner + ob·r): LiftInput = (oa+ob)/2 y
-- BalanceInput = oa − ob, así que la mitad del bot es ob = lift − balance/2 (la del jugador, oa = lift + balance/2).
function TutorialBot.targetFor(lift: number, balance: number): number
	local inner, outer = Config.BarInnerOffset, Config.BarOuterOffset
	local ob = math.clamp(lift - balance / 2, 0, 1)
	return TutorialBot.SIDE * (inner + ob * (outer - inner))
end

-- Un paso del bot. slots = huecos de la sesión (bot en SIDE, jugador en -SIDE); balance / lift = lo que hace
-- falta entre los dos (TutorialBot.steer / liftFor; neutro en la cuenta atrás); progress = fracción recorrida del
-- nivel; now = reloj de la sesión (resbalones). Devuelve el texto de la indicación actual.
-- completed = ya cruzaron la meta: el bot baja a aterrizar (sin eso mantendría la altura y el vuelo no acabaría).
function TutorialBot.step(slots: { [number]: any }, state: string, cues: { Cue }, progress: number, balance: number, lift: number?, now: number?, completed: boolean?): string
	local bot = slots[TutorialBot.SIDE]
	if not (bot and bot.rig) then
		return ""
	end
	if completed then
		local target = TutorialBot.targetFor(LAND_LIFT, 0)
		local delta = target - bot.position
		bot.axis = if math.abs(delta) > DEADBAND then math.sign(delta) else 0
		bot.pumping = false
		return if state == "Flying" then LAND_HINT else ""
	end
	local active: Cue? = nil
	if state == "Flying" then
		for _, cue in cues do
			if progress >= cue.from and progress < cue.to then
				active = cue
				break
			end
		end
	end
	local steerShare = math.clamp(balance, -MAX_STEER, MAX_STEER)
	if active and active.drift then
		-- Resbalón: se inclina solo hacia un lado y otro y apenas corrige; el ala se desvía si el jugador no compensa.
		steerShare = balance * DRIFT_SELF_CORRECTION + DRIFT * math.sin((now or 0) * DRIFT_RATE)
	end
	local target = TutorialBot.targetFor(lift or Config.NeutralLiftPoint, steerShare)
	local delta = target - bot.position
	bot.axis = if math.abs(delta) > DEADBAND then math.sign(delta) else 0
	bot.pumping = active ~= nil and active.pump
	if state == "Countdown" then
		return COUNTDOWN_HINT
	end
	return if active then active.hint else ""
end

return TutorialBot
