-- Vuela Flight School como en el juego: modo práctica (tocar no quita corazones; golpe fuerte = "bonk"), viento a
-- favor si el ala se queda casi parada más de Config.PracticeStuckTime, indicaciones y marcas fantasma reales.
-- El jugador derecho sigue siempre su marca fantasma (con reacción); el izquierdo, según ARGS.player:
--   "full" (por defecto: sigue su fantasma) · "lift" (solo sube y baja: en las curvas gira a medias) ·
--   "idle" (no se mueve nunca: sin la ayuda del atasco no pasaría del primer tramo).
-- Al cruzar la línea de relevo (despegue de los veteranos) se sigue volando hasta la entrada del nivel 1: el
-- recorrido es continuo.
-- Informe: tiempo hasta el relevo y hasta el nivel 1, bonks, veces que ayudó el viento a favor y desvío máximo.
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
local FlightSchool = require(game.ServerScriptService.Glider.FlightSchool)
local course = Checkpoints.new(tutorial)
local cues = FlightSchool.cuesOf(tutorial.Level01)
local levelOneEntry = workspace.Map.Level01.Entry

local params = RaycastParams.new()
params.FilterDescendantsInstances = { template }
local DT = 1 / 60
local inner, outer = Config.BarInnerOffset, Config.BarOuterOffset
local mode = ARGS.player or "full"
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
	local goal = course:lookahead(1, pos, FlightSchool.LOOKAHEAD)
	local balance = FlightSchool.steer(pos, forward, goal)
	local lift = FlightSchool.liftFor(pos, goal, state.speed)
	local ghostLeft, ghostRight = FlightSchool.ghosts(lift, balance)
	if mode == "full" then
		follow(slots[-1], ghostLeft)
	elseif mode == "lift" then
		follow(slots[-1], -(inner + math.clamp(lift, 0, 1) * (outer - inner)))
	end
	follow(slots[1], ghostRight)
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
		practice = finishedAt == nil,
	})
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
	end
	previous = pos
	if finishedAt then
		-- Tras el relevo, el recorrido de verdad: seguir recto hasta la boca del nivel 1.
		local toEntry = levelOneEntry.CFrame:PointToObjectSpace(pos)
		if toEntry.Z < 0 then
			local inside = math.abs(toEntry.X) < 100 and math.abs(toEntry.Y) < 85
			result = string.format("RELEVO en %.1f s · entra al nivel 1 a los %.1f s%s", finishedAt, t, if inside then "" else " (FUERA DE LA BOCA)")
			break
		end
	end
end
print(string.format("jugador=%s · %s · bonks %d · viento a favor %d · desvío máx %.0f", mode, result, bonks, assists, maxOff))
