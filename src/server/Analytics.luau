--!strict
-- Eventos para Analytics del Creator Dashboard (AnalyticsService). Sirven para ver dónde se atasca la gente:
--   · embudo de entrada (onboarding): entra → se le ofrece el tutorial → lo acepta/rechaza → lo termina/salta →
--     primer vuelo en dúo → primer checkpoint
--   · progresión por nivel: empieza / supera cada nivel (con golpes y alas perdidas en ese nivel)
--   · eventos sueltos: ala perdida (por nivel), recorrido completado (tiempo)
-- Todo va en pcall: si el servicio falla o no está disponible (Studio), el juego sigue igual.
-- Los vuelos de prueba (DevStartLevel) y el tutorial no cuentan como progresión.

local AnalyticsService = game:GetService("AnalyticsService")

local Analytics = {}

local PATH = "Course" -- nombre del recorrido en los informes de progresión

-- Pasos del embudo de entrada (en orden; cada paso se registra una vez por jugador y sesión).
Analytics.STEPS = table.freeze({
	Joined = 1,
	TutorialOffered = 2,
	TutorialAnswered = 3,
	TutorialFinished = 4,
	FirstDuoFlight = 5,
	FirstCheckpoint = 6,
})
local STEP_NAMES = {
	[1] = "Joined",
	[2] = "Tutorial offered",
	[3] = "Tutorial answered",
	[4] = "Tutorial finished or skipped",
	[5] = "First duo flight",
	[6] = "First checkpoint",
}

local logged: { [Player]: { [number]: true } } = {}
local warned: { [string]: true } = {} -- cada tipo de fallo se avisa una sola vez

local function safely(label: string, action: () -> ())
	local ok, problem = (pcall :: any)(action)
	if not ok and not warned[label] then
		warned[label] = true
		warn(string.format("[Analytics] %s: %s", label, tostring(problem)))
	end
end

function Analytics.funnel(player: Player, step: number, fields: { [string]: any }?)
	local done = logged[player] or {}
	logged[player] = done
	if done[step] then
		return
	end
	done[step] = true
	safely("onboarding", function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, STEP_NAMES[step] or tostring(step), fields :: any)
	end)
end

function Analytics.levelStarted(player: Player, level: number, title: string)
	safely("progression start", function()
		AnalyticsService:LogProgressionStartEvent(player, PATH, level, title)
	end)
end

function Analytics.levelCompleted(player: Player, level: number, title: string, hits: number, losses: number)
	safely("progression complete", function()
		AnalyticsService:LogProgressionCompleteEvent(player, PATH, level, title, { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = string.format("hits %d", math.min(hits, 5)), [Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = string.format("losses %d", math.min(losses, 5)) } :: any)
	end)
end

function Analytics.wingLost(player: Player, level: number)
	safely("wing lost", function()
		AnalyticsService:LogCustomEvent(player, "WingLost", 1, { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = string.format("level %02d", level) } :: any)
	end)
end

function Analytics.courseCompleted(player: Player, seconds: number)
	safely("course completed", function()
		AnalyticsService:LogCustomEvent(player, "CourseCompleted", math.floor(seconds))
	end)
end

function Analytics.forget(player: Player)
	logged[player] = nil
end

return Analytics
