--!strict
-- Flight School (el principio del recorrido para los dúos con alguien nuevo): indicaciones y marcas fantasma.
--   · Indicaciones (atributo "Coach" del nivel, MapBuilder TUTORIAL_LEVELS.coach): una o dos palabras por tramo,
--     en fracciones de la línea ideal; acción 1 = marcas fantasma en la barra del HUD (dónde ponerse cada uno).
--   · Lo que haría falta para seguir la línea ideal: subida (liftFor) y giro (steer), como el piloto del
--     FlightTester. De ahí salen las marcas fantasma (ghosts).
-- Lo usa GliderController, que publica la indicación (atributo TutorialHint) y las marcas (GhostLeft/GhostRight).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Glider = ReplicatedStorage:WaitForChild("Glider")
local Config = require(Glider:WaitForChild("GliderConfig"))
local GliderPhysics = require(Glider:WaitForChild("GliderPhysics"))

local FlightSchool = {}

FlightSchool.LOOKAHEAD = 110 -- studs por delante a los que se mira sobre la línea ideal
local COUNTDOWN_HINT = "Slide along the bar with A / D (or the ◀ ▶ buttons)"

export type Cue = { from: number, to: number, hint: string, ghost: boolean }

-- Indicaciones del nivel (atributo "Coach": "desde|hasta|acción|texto;…"; acción 1 = marcas fantasma).
function FlightSchool.cuesOf(level: Instance?): { Cue }
	local cues: { Cue } = {}
	local raw = level and level:GetAttribute("Coach")
	if type(raw) ~= "string" then
		return cues
	end
	for _, item in string.split(raw, ";") do
		local from, to, action, hint = string.match(item, "^([^|]+)|([^|]+)|([^|]+)|(.*)$")
		if from and to and hint then
			table.insert(cues, { from = tonumber(from) or 0, to = tonumber(to) or 1, hint = hint, ghost = tonumber(action) == 1 })
		end
	end
	return cues
end

-- Balance (−1…1, positivo = girar a la izquierda) para ir hacia `goal` desde `position` con rumbo `forward`.
function FlightSchool.steer(position: Vector3, forward: Vector3, goal: Vector3?): number
	local wantTurn = GliderPhysics.pursuitTurn(position, forward, goal)
	return GliderPhysics.balanceInputFor(wantTurn / Config.MaxTurnRate)
end

-- LiftInput que hace falta para llegar a la altura de `goal`.
function FlightSchool.liftFor(position: Vector3, goal: Vector3?, speed: number?): number
	if not goal then
		return Config.NeutralLiftPoint
	end
	local flat = ((goal - position) * Vector3.new(1, 0, 1)).Magnitude
	local timeToGoal = math.max(flat / (speed or Config.ForwardSpeed), 0.7)
	local wantVy = math.clamp((goal.Y - position.Y) / timeToGoal, -Config.MaxFallSpeed, Config.MaxClimbSpeed)
	return GliderPhysics.liftInputFor(GliderPhysics.liftFor(wantVy))
end

-- Indicación activa en `progress` (fracción recorrida del nivel); solo en vuelo.
function FlightSchool.activeCue(cues: { Cue }, state: string, progress: number): Cue?
	if state ~= "Flying" then
		return nil
	end
	for _, cue in cues do
		if progress >= cue.from and progress < cue.to then
			return cue
		end
	end
	return nil
end

-- Texto de la pantalla: la indicación activa, o cómo moverse durante la cuenta atrás.
function FlightSchool.hintFor(cue: Cue?, state: string): string
	if state == "Countdown" then
		return COUNTDOWN_HINT
	end
	return if cue then cue.hint else ""
end

-- Marcas fantasma: dónde tendría que estar cada uno (studs desde el centro de la barra, izquierda negativa) para
-- dar entre los dos el LiftInput y el BalanceInput que hacen falta. Con el izquierdo en -(inner + oa·r) y el
-- derecho en +(inner + ob·r): LiftInput = (oa+ob)/2 y BalanceInput = oa − ob → oa = lift + balance/2,
-- ob = lift − balance/2.
function FlightSchool.ghosts(lift: number, balance: number): (number, number)
	local inner, outer = Config.BarInnerOffset, Config.BarOuterOffset
	local oa = math.clamp(lift + balance / 2, 0, 1)
	local ob = math.clamp(lift - balance / 2, 0, 1)
	return -(inner + oa * (outer - inner)), inner + ob * (outer - inner)
end

return FlightSchool
