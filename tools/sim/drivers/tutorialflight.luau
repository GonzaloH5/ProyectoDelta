-- Vuela Flight School como en el juego: modo práctica (tocar no quita corazones; golpe fuerte = "bonk"), viento a
-- favor si se atascan contra algo más de Config.PracticeStuckTime, indicaciones y marcas fantasma reales.
--   duo=true: los dos jugadores siguen su marca fantasma (con reacción); al cruzar la salida pasarían al nivel 1.
--   por defecto: un jugador con el Coach (TutorialBot hace su mitad) y ARGS.player:
--     "full" (sigue su fantasma y compensa el resbalón del Coach) · "lift" (solo sube y baja: gira a medias) ·
--     "idle" (no se mueve nunca: sin la ayuda del atasco no pasaría ni el primer tramo).
--   Con el Coach, tras la meta se sigue volando hasta aterrizar, chocar o agotar FinishLandTimeout.
-- Informe: tiempo hasta la salida, bonks, veces que ayudó el viento a favor y desvío máximo de la línea ideal.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Glider.GliderConfig)
local GliderMath = require(ReplicatedStorage.Glider.GliderMath)
local GliderPhysics = require(ReplicatedStorage.Glider.GliderPhysics)

local template = Instance.new("Model")
template.Name = "AlaDelta"
local bar = Instance.new("Part")
bar.Name = "Agarre"
bar.Size = Vector3.new(1, 0.5, 10)
bar.Parent = template
template.Parent = workspace
local SPAN, WING_TOP = 32, 4

local MapBuilder = require(game.ServerScriptService.Glider.DevTools.MapBuilder:Clone())
MapBuilder.build({ dress = ARGS.dress == true })
local tutorial = workspace.Map.Tutorial
local Checkpoints = require(game.ServerScriptService.Glider.Checkpoints)
local TutorialBot = require(game.ServerScriptService.Glider.TutorialBot)
local course = Checkpoints.new(tutorial)
local cues = TutorialBot.cuesOf(tutorial.Level01)

local params = RaycastParams.new()
params.FilterDescendantsInstances = { template }
local DT = 1 / 60
local inner, outer = Config.BarInnerOffset, Config.BarOuterOffset
local duo = ARGS.duo == true
local mode = if duo then "duo" else (ARGS.player or "full")
local REACTION = 0.45

local launch = tutorial.StartIsland.LaunchPoint.CFrame
local pos = launch.Position
local state = GliderPhysics.newState(GliderMath.yawOf(launch.LookVector))
local health = GliderPhysics.newHealth()
local dims = { span = SPAN, wingTop = WING_TOP }
local slots = {
	[-1] = { rig = true, position = -(inner + Config.StartOutward * (outer - inner)), axis = 0, velocity = 0, pending = {} },
	[1] = { rig = true, position = inner + Config.StartOutward * (outer - inner), axis = 0, velocity = 0, pending = {} },
}
local t, result = 0, "NO LLEGA"
local bonks, assists = 0, 0
local stuck, clean, windAssist = 0, 0, false
local maxOff = 0
local previous = pos
local finishedAt: number? = nil

-- Un jugador simulado va hacia `goal` (posición en la barra) con retraso de reacción.
local function follow(slot, goal: number)
	table.insert(slot.pending, { at = t + REACTION, goal = goal })
	while #slot.pending > 1 and slot.pending[2].at <= t do
		table.remove(slot.pending, 1)
	end
	local order = slot.pending[1]
	if order.at <= t then
		local d = order.goal - slot.position
		slot.axis = if math.abs(d) > 0.3 then math.sign(d) else 0
	end
end

while t < 150 do
	t += DT
	local forward = GliderPhysics.forwardOf(state.yaw)
	local progress = course:progress(1, pos)
	local goal = course:lookahead(1, pos, TutorialBot.LOOKAHEAD)
	local balance = TutorialBot.steer(pos, forward, goal)
	local lift = TutorialBot.liftFor(pos, goal, state.speed)
	local cue = TutorialBot.activeCue(cues, "Flying", progress)
	local ghostLeft, ghostRight = TutorialBot.ghosts(lift, balance)
	if finishedAt then
		ghostLeft, ghostRight = TutorialBot.ghosts(0.15, 0) -- aterrizar: los dos al centro
	end
	-- Jugador izquierdo (el humano).
	if mode == "full" or mode == "duo" then
		local target = ghostLeft
		if cue and cue.drift and not duo then
			-- Compensar el resbalón del Coach: pone también la mitad de giro que el Coach no pone.
			target = -(inner + math.clamp(lift + balance, 0, 1) * (outer - inner))
		end
		follow(slots[-1], target)
	elseif mode == "lift" then
		follow(slots[-1], -(inner + math.clamp(lift, 0, 1) * (outer - inner)))
	end
	-- Jugador derecho: el segundo humano (dúo) o el Coach.
	if duo then
		follow(slots[1], ghostRight)
	else
		TutorialBot.step(slots, cue, balance, lift, t, finishedAt ~= nil)
	end
	for _, slot in slots do
		slot.velocity = GliderMath.approach(slot.velocity, slot.axis * Config.PlayerSlideSpeed, Config.PlayerSlideResponse, DT)
		slot.position = math.clamp(slot.position + slot.velocity * DT, -outer, outer)
	end
	local liftInput, balanceInput = GliderPhysics.inputs(slots[-1].position, slots[1].position)

	-- Viento a favor del atasco (como GliderSession en modo práctica).
	local assistTurn, windVertical = 0, 0
	if windAssist and goal then
		assistTurn = GliderPhysics.pursuitTurn(pos, forward, goal, state.speed) * Config.WindAssistTurnFraction
		windVertical = math.clamp((goal.Y - pos.Y) * 0.5, -Config.PracticeAssistVertical, Config.PracticeAssistVertical)
	end
	local flown = GliderPhysics.fly(state, health, liftInput, balanceInput, pos, dims, DT, params, {
		now = t,
		assistTurn = assistTurn,
		windVertical = windVertical,
		landing = finishedAt ~= nil,
		practice = true,
	})
	if flown.landed then
		result = string.format("META en %.1f s · ATERRIZA %.1f s después", finishedAt or 0, t - (finishedAt or t))
		break
	end
	if flown.event == "bonk" then
		bonks += 1
	end
	stuck = if state.speed < Config.ForwardSpeed * 0.5 then stuck + DT else 0
	clean = if flown.contact then 0 else clean + DT
	if stuck > Config.PracticeStuckTime and not windAssist then
		windAssist = true
		assists += 1
	elseif windAssist and clean > 3 then
		windAssist = false
	end
	local onLine = course:lookahead(1, pos, 0)
	if onLine and progress > 0.02 and progress < 0.98 and not finishedAt then
		maxOff = math.max(maxOff, ((pos - onLine) * Vector3.new(1, 0, 1)).Magnitude)
	end
	pos += flown.velocity * DT
	local crossed = course:crossed(previous, pos, if finishedAt then 1 else 0)
	if crossed and crossed.final and not finishedAt then
		finishedAt = t
		if duo then
			result = string.format("SALIDA en %.1f s (→ nivel 1)", t)
			break
		end
	end
	previous = pos
	if finishedAt and t - finishedAt >= Config.FinishLandTimeout then
		result = string.format("META en %.1f s · sin aterrizar en %d s (vuelta al lobby por tiempo)", finishedAt, Config.FinishLandTimeout)
		break
	end
end
print(string.format("jugador=%s · %s · bonks %d · viento a favor %d · desvío máx %.0f", mode, result, bonks, assists, maxOff))
