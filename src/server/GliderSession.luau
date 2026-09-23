--!strict
-- Una sesión = un ala delta clonada de la plantilla + un dúo de jugadores + su vuelo.
-- Autoridad total del servidor: los clientes solo envían su eje A/D (-1, 0, 1).
--
-- Cadena de vuelo:
--   posición de ambos en la barra → LiftInput (distancia al centro) / BalanceInput (centro de masa)
--   → velocidad vertical (suavizada) + alabeo (muelle) → giro de rumbo (suavizado)
--   → LinearVelocity (avance constante + vertical) y AlignOrientation (rumbo, pitch, roll)
-- Los "slots" 1 y 2 solo indican dónde empieza cada uno; ninguno tiene un lado propio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Glider.GliderConfig)
local GliderMath = require(ReplicatedStorage.Glider.GliderMath)
local CollisionGroups = require(script.Parent.CollisionGroups)
local RiderRig = require(script.Parent.RiderRig)

local LEFT, RIGHT = -1, 1

type Slot = {
	player: Player?,
	rig: RiderRig.Rig?,
	axis: number, -- -1 A, 0 nada, 1 D (visual, desde la cámara trasera)
	position: number, -- studs desde el centro de la barra (-izquierda, +derecha), toda la barra
	slideVelocity: number, -- studs/s
	inputWindowStart: number,
	inputCount: number,
	diedConnection: RBXScriptConnection?,
}

-- lobby = el dúo pidió volver al lobby · completed = aterrizó tras cruzar la meta · empty = no queda nadie.
-- Un choque NO termina la sesión: el ala reaparece en su último checkpoint.
export type FinishReason = "lobby" | "completed" | "empty"

local GliderSession = {}
GliderSession.__index = GliderSession

export type Session = typeof(setmetatable(
	{} :: {
		id: number,
		glider: Model,
		root: BasePart,
		respawnForward: Vector3, -- rumbo al reaparecer (salida o último checkpoint)
		respawnCFrame: CFrame, -- dónde reaparece el ala tras chocar o con Reset
		checkpoint: number, -- niveles superados (0 = aún en el primero)
		completed: boolean, -- cruzó la meta: al terminar el vuelo, el dúo vuelve al lobby
		runTime: number, -- cronómetro del recorrido: desde el primer despegue hasta la meta (choques incluidos)
		timing: boolean,
		gliderSize: Vector3,
		wingTop: number,
		linearVelocity: LinearVelocity,
		alignOrientation: AlignOrientation,
		trails: { Trail },
		trailTransparency: number,
		slots: { [number]: Slot },
		flight: { [string]: any },
		lastReset: number,
		finished: boolean,
		members: { Player },
		onFinished: (Session, FinishReason, { Player }) -> (),
	},
	GliderSession
))

local function lateralFor(side: number, outward: number): number
	return side * (Config.BarInnerOffset + outward * (Config.BarOuterOffset - Config.BarInnerOffset))
end

local function newSlot(side: number): Slot
	return {
		player = nil,
		rig = nil,
		axis = 0,
		position = lateralFor(side, Config.StartOutward),
		slideVelocity = 0,
		inputWindowStart = 0,
		inputCount = 0,
		diedConnection = nil,
	}
end

-- Prepara un clon de la plantilla: Root invisible, todo soldado, sin colisiones, sin masa.
local function buildGlider(template: Model, parent: Instance, id: number)
	local glider = template:Clone()
	glider.Name = string.format("%s_%d", Config.GliderName, id)

	local bar = glider:FindFirstChild(Config.BarPartName) :: BasePart
	assert(bar, "La plantilla del ala necesita una pieza llamada " .. Config.BarPartName)

	-- Adelante = perpendicular horizontal a la barra, apuntando hacia la nariz.
	-- Sin pieza de nariz, el ala queda detrás de la barra: adelante = del centro hacia la barra.
	local nose = glider:FindFirstChild(Config.NosePartName)
	local noseHint = if nose and nose:IsA("BasePart")
		then nose.Position - bar.Position
		else bar.Position - glider:GetBoundingBox().Position
	local barAxis = (bar.CFrame.RightVector * Vector3.new(1, 0, 1)).Unit
	local forward = Vector3.yAxis:Cross(barAxis)
	if forward:Dot(noseHint) < 0 then
		forward = -forward
	end

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Anchored = true
	root.RootPriority = 127 -- siempre raíz del ensamblaje, aunque se suelden personajes
	root.CollisionGroup = CollisionGroups.Gliders
	root.CFrame = CFrame.lookAt(bar.Position, bar.Position + forward)
	root.Parent = glider

	for _, part in glider:GetDescendants() do
		if part:IsA("BasePart") and part ~= root then
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CollisionGroup = CollisionGroups.Gliders
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = root
		end
	end
	glider.PrimaryPart = root

	-- Caja del modelo alineada con Root: X = envergadura, Y = alto.
	local boxCFrame, size = glider:GetBoundingBox()
	local wingTop = root.CFrame:PointToObjectSpace(boxCFrame.Position).Y + size.Y / 2

	local attachment = Instance.new("Attachment")
	attachment.Name = "FlightAttachment"
	attachment.Parent = root

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Attachment0 = attachment
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linearVelocity.MaxForce = math.huge
	linearVelocity.Enabled = false
	linearVelocity.Parent = root

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Attachment0 = attachment
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.MaxTorque = math.huge
	alignOrientation.MaxAngularVelocity = math.huge
	alignOrientation.Responsiveness = Config.AlignResponsiveness
	alignOrientation.CFrame = root.CFrame.Rotation
	alignOrientation.Enabled = false
	alignOrientation.Parent = root

	glider:SetAttribute("SessionId", id)
	glider.Parent = parent
	return glider, root, forward, size, wingTop, linearVelocity, alignOrientation
end

-- Puntas del ala en el espacio de Root: la esquina más alejada hacia cada lado
-- (entre las igual de alejadas, la más trasera, que es donde termina un ala delta).
local function findWingTips(glider: Model, root: BasePart): (Vector3, Vector3)
	local corners = {}
	for _, part in glider:GetDescendants() do
		if part:IsA("BasePart") and part ~= root then
			local cframe = root.CFrame:ToObjectSpace(part.CFrame)
			local half = part.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						table.insert(corners, cframe * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
					end
				end
			end
		end
	end
	local function tip(side: number): Vector3
		local reach = -math.huge
		for _, corner in corners do
			reach = math.max(reach, corner.X * side)
		end
		local best: Vector3? = nil
		for _, corner in corners do
			local isOutermost = corner.X * side >= reach - 0.5
			if isOutermost and (best == nil or corner.Z > best.Z) then
				best = corner
			end
		end
		return best :: Vector3
	end
	return tip(-1), tip(1)
end

-- Una estela por punta: un Trail entre dos Attachments separados verticalmente.
local function makeTrails(glider: Model, root: BasePart): { Trail }
	if not Config.TrailEnabled then
		return {}
	end
	local trails = {}
	local left, right = findWingTips(glider, root)
	for index, tip in { left, right } do
		local top = Instance.new("Attachment")
		top.Name = "TrailTop" .. index
		top.Position = tip + Vector3.new(0, Config.TrailWidth / 2, 0)
		top.Parent = root
		local bottom = Instance.new("Attachment")
		bottom.Name = "TrailBottom" .. index
		bottom.Position = tip - Vector3.new(0, Config.TrailWidth / 2, 0)
		bottom.Parent = root

		local trail = Instance.new("Trail")
		trail.Name = "WingTrail" .. index
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.Lifetime = Config.TrailLifetime
		trail.Color = ColorSequence.new(Config.TrailColor)
		trail.LightEmission = 1 -- brilla un poco para destacar contra el cielo y las paredes
		trail.FaceCamera = true
		trail.MinLength = 0.05
		trail.WidthScale = NumberSequence.new(1, 0.1)
		trail.Transparency = NumberSequence.new(Config.TrailCalmTransparency, 1)
		trail.Enabled = false
		trail.Parent = root
		table.insert(trails, trail)
	end
	return trails
end

function GliderSession.new(
	id: number,
	template: Model,
	parent: Instance,
	players: { Player },
	onFinished: (Session, FinishReason, { Player }) -> (),
	launchAt: CFrame?, -- pruebas: despegar en otro punto (DevSpawns) en vez de donde está la plantilla
	startCheckpoint: number? -- niveles que se dan por superados al despegar (pruebas con DevSpawns)
): Session
	local glider, root, forward, size, wingTop, linearVelocity, alignOrientation = buildGlider(template, parent, id)
	if launchAt then
		glider:PivotTo(launchAt)
		forward = (launchAt.LookVector * Vector3.new(1, 0, 1)).Unit
	end

	local self = setmetatable({
		id = id,
		glider = glider,
		root = root,
		respawnForward = forward,
		respawnCFrame = root.CFrame,
		checkpoint = startCheckpoint or 0,
		completed = false,
		runTime = 0,
		timing = false,
		gliderSize = size,
		wingTop = wingTop,
		linearVelocity = linearVelocity,
		alignOrientation = alignOrientation,
		trails = makeTrails(glider, root),
		trailTransparency = Config.TrailCalmTransparency,
		slots = { [LEFT] = newSlot(LEFT), [RIGHT] = newSlot(RIGHT) },
		flight = {
			state = "Countdown", -- Countdown | Flying | Ended
			timer = 0,
			yaw = GliderMath.yawOf(forward),
			verticalSpeed = 0,
			roll = 0,
			rollVelocity = 0,
			pitch = 0,
			pitchVelocity = 0,
			turnRate = 0,
			time = 0,
			broadcastTimer = 0,
			liftInput = 0,
			balanceInput = 0,
			leftPosition = 0, -- posiciones efectivas (incluye el compañero fantasma en solitario)
			rightPosition = 0,
		},
		lastReset = -math.huge,
		finished = false,
		members = table.clone(players),
		onFinished = onFinished,
	}, GliderSession)

	for index, player in players do
		self:_board(player, if index == 1 then LEFT else RIGHT)
	end
	glider:SetAttribute("Checkpoint", self.checkpoint)
	self:_setState("Countdown")
	self:_publishSlots()
	return self
end

-- ── Jugadores ─────────────────────────────────────────────────────────

function GliderSession._setState(self: Session, state: string)
	self.flight.state = state
	self.flight.timer = 0
	self.glider:SetAttribute("State", state)
end

function GliderSession._setTrails(self: Session, enabled: boolean)
	for _, trail in self.trails do
		trail.Enabled = enabled
	end
end

-- Estelas de viento: más marcadas cuanto más fuerte gira o más rápido cae en picado.
function GliderSession._updateTrails(self: Session)
	local flight = self.flight
	local turning = math.abs(flight.turnRate) / Config.MaxTurnRate
	local diving = math.max(0, -flight.verticalSpeed) / Config.MaxFallSpeed
	local intensity = math.clamp(turning + diving, 0, 1)
	local transparency = Config.TrailCalmTransparency
		+ (Config.TrailIntenseTransparency - Config.TrailCalmTransparency) * intensity
	if math.abs(transparency - self.trailTransparency) < 0.03 then
		return -- evita replicar cambios imperceptibles
	end
	self.trailTransparency = transparency
	local sequence = NumberSequence.new(transparency, 1)
	for _, trail in self.trails do
		trail.Transparency = sequence
	end
end

function GliderSession._publishSlots(self: Session)
	local left, right = self.slots[LEFT].player, self.slots[RIGHT].player
	self.glider:SetAttribute("LeftUserId", if left then left.UserId else 0)
	self.glider:SetAttribute("RightUserId", if right then right.UserId else 0)
end

function GliderSession._board(self: Session, player: Player, side: number)
	local character = player.Character
	if not character then
		return
	end
	local slot = self.slots[side]
	slot.position = lateralFor(side, Config.StartOutward)
	local rig = RiderRig.attach(character, self.root, side, slot.position)
	if not rig then
		return
	end
	slot.player = player
	slot.rig = rig
	slot.diedConnection = rig.humanoid.Died:Once(function()
		self:removePlayer(player)
	end)
end

function GliderSession.slotOf(self: Session, player: Player): number?
	for side, slot in self.slots do
		if slot.player == player then
			return side
		end
	end
	return nil
end

function GliderSession.riderCount(self: Session): number
	local count = 0
	for _, slot in self.slots do
		if slot.rig then
			count += 1
		end
	end
	return count
end

function GliderSession.riders(self: Session): { Player }
	local list = {}
	for _, slot in self.slots do
		if slot.player then
			table.insert(list, slot.player)
		end
	end
	return list
end

-- Un jugador sale del ala (murió o se desconectó). En un dúo de dos jugadores la partida se cancela y el
-- compañero vuelve al lobby (igual que el botón Lobby). Si no queda nadie, la sesión termina sin más.
function GliderSession.removePlayer(self: Session, player: Player)
	local side = self:slotOf(player)
	if not side then
		return
	end
	local slot = self.slots[side]
	if slot.diedConnection then
		slot.diedConnection:Disconnect()
	end
	if slot.rig then
		RiderRig.detach(slot.rig)
	end
	self.slots[side] = newSlot(side)
	self:_publishSlots()
	if self:riderCount() == 0 then
		self:finish("empty")
	elseif #self.members >= 2 then
		self:finish("lobby")
	end
end

-- ── Mensajes de los clientes (ya validados por el controlador) ────────

function GliderSession.handleMessage(self: Session, player: Player, kind: unknown, value: unknown)
	local side = self:slotOf(player)
	if not side then
		return
	end
	local slot = self.slots[side]

	local now = os.clock()
	if now - slot.inputWindowStart > 1 then
		slot.inputWindowStart = now
		slot.inputCount = 0
	end
	slot.inputCount += 1
	if slot.inputCount > Config.MaxInputsPerSecond then
		return -- sin spam
	end

	if kind == "Axis" then
		if type(value) ~= "number" or value ~= value then
			return -- tipo inválido o NaN
		end
		slot.axis = math.sign(math.clamp(math.round(value), -1, 1))
	elseif kind == "Reset" then
		if now - self.lastReset >= Config.ResetCooldown then
			self.lastReset = now
			self:resetToCheckpoint()
		end
	end
end

-- ── Ciclo de vuelo ────────────────────────────────────────────────────

-- Guarda un checkpoint alcanzado: a partir de ahora el ala reaparece ahí (centro de la isla, a la altura
-- de vuelo, mirando al siguiente nivel). final = meta: al terminar este vuelo el dúo vuelve al lobby.
function GliderSession.setCheckpoint(self: Session, index: number, spawn: CFrame, final: boolean)
	self.checkpoint = index
	self.respawnCFrame = spawn
	self.respawnForward = (spawn.LookVector * Vector3.new(1, 0, 1)).Unit
	self.completed = final
	if final then
		self.timing = false -- la meta para el cronómetro
	end
	self.glider:SetAttribute("Checkpoint", index)
	self.glider:SetAttribute("Completed", final)
	self.glider:SetAttribute("RunTime", self.runTime)
end

-- Vuelve al último checkpoint (o a la salida) con el mismo dúo y repite la cuenta atrás.
function GliderSession.resetToCheckpoint(self: Session)
	local flight = self.flight
	self.root.Anchored = true
	self.linearVelocity.Enabled = false
	self.alignOrientation.Enabled = false
	self:_setTrails(false)
	self.root.CFrame = self.respawnCFrame
	self.root.AssemblyLinearVelocity = Vector3.zero
	self.root.AssemblyAngularVelocity = Vector3.zero

	flight.yaw = GliderMath.yawOf(self.respawnForward)
	flight.verticalSpeed = 0
	flight.roll, flight.rollVelocity = 0, 0
	flight.pitch, flight.pitchVelocity = 0, 0
	flight.turnRate = 0
	for side, slot in self.slots do
		slot.position = lateralFor(side, Config.StartOutward)
		slot.slideVelocity = 0
	end
	self:_setState("Countdown")
end

function GliderSession._launch(self: Session)
	self.alignOrientation.CFrame = self.respawnCFrame.Rotation
	self.root.Anchored = false
	self.root:SetNetworkOwner(nil) -- servidor dueño: ningún cliente simula el ala
	self.linearVelocity.VectorVelocity = self.respawnForward * Config.ForwardSpeed
	self.linearVelocity.Enabled = true
	if not self.completed then
		self.timing = true -- el primer despegue arranca el cronómetro (los siguientes no lo reinician)
	end
	self.alignOrientation.Enabled = true
	self:_setTrails(true)
	self:_setState("Flying")
end

function GliderSession._crash(self: Session)
	self.root.Anchored = true
	self.linearVelocity.Enabled = false
	self.alignOrientation.Enabled = false
	self:_setTrails(false)
	self:_setState("Ended")
end

-- Termina la sesión: suelta a los jugadores, destruye el ala y avisa al controlador.
function GliderSession.finish(self: Session, reason: FinishReason)
	if self.finished then
		return
	end
	self.finished = true
	local riders = self:riders()
	for side, slot in self.slots do
		if slot.diedConnection then
			slot.diedConnection:Disconnect()
		end
		if slot.rig then
			RiderRig.detach(slot.rig)
		end
		self.slots[side] = newSlot(side)
	end
	self.glider:Destroy()
	self.onFinished(self, reason, riders)
end

-- Los jugadores no chocan entre sí: cada uno se mueve libre por toda la barra.
function GliderSession._updateSlides(self: Session, dt: number)
	local reach = Config.BarOuterOffset
	for _, slot in self.slots do
		local rig = slot.rig
		if not rig then
			continue
		end
		-- A = izquierda, D = derecha, igual para ambos jugadores y en toda la barra.
		local targetVelocity = slot.axis * Config.PlayerSlideSpeed
		slot.slideVelocity = GliderMath.approach(slot.slideVelocity, targetVelocity, Config.PlayerSlideResponse, dt)
		slot.position += slot.slideVelocity * dt
		if math.abs(slot.position) >= reach then
			slot.position = math.clamp(slot.position, -reach, reach)
			slot.slideVelocity = 0
		end
		RiderRig.setLateral(rig, slot.position)
	end
end

-- Posiciones de ambos cuerpos → LiftInput y BalanceInput. No existe "lado" de cada jugador:
--   LiftInput    = promedio de lo lejos del centro que está cada uno (da igual hacia qué lado)
--                  ambos centrados → 0 → baja · ambos pegados a un extremo (cualquiera) → 1 → sube
--   BalanceInput = hacia dónde cae el peso de los dos juntos (centro de masa)
--                  equilibrado respecto al centro → 0 → recto · peso a un lado → gira hacia ese lado
-- En solitario, el hueco vacío es un compañero fantasma en espejo: sube y baja pero no gira.
function GliderSession._computeInputs(self: Session)
	local inner, outer = Config.BarInnerOffset, Config.BarOuterOffset
	local left, right = self.slots[LEFT], self.slots[RIGHT]
	local a, b = left.position, right.position
	if left.rig and not right.rig then
		b = -a
	elseif right.rig and not left.rig then
		a = -b
	end
	local flight = self.flight
	flight.leftPosition, flight.rightPosition = a, b

	local function outwardness(position: number): number
		return math.clamp((math.abs(position) - inner) / (outer - inner), 0, 1)
	end
	flight.liftInput = (outwardness(a) + outwardness(b)) / 2

	local centerOfMass = (a + b) / 2
	flight.balanceInput = math.clamp(-centerOfMass / ((outer - inner) / 2), -1, 1)
end

-- Una superficie que mira hacia abajo es un techo: se roza, nunca es un choque.
local function isCeiling(result: RaycastResult): boolean
	return result.Normal.Y < -0.5
end

-- Techo: máxima velocidad vertical permitida (math.huge si no hay techo cerca).
-- Al acercarse frena la subida; si ya roza, lo empuja apenas hacia abajo.
function GliderSession._ceilingLimit(self: Session, params: RaycastParams): number
	local rollRadians = math.rad(math.abs(self.flight.roll))
	local topExtent = self.wingTop * math.cos(rollRadians) + self.gliderSize.X / 2 * math.sin(rollRadians)
	local origin = self.root.Position
	local result = workspace:Raycast(origin, Vector3.new(0, topExtent + Config.CeilingProbeDistance, 0), params)
	if not (result and isCeiling(result)) then
		return math.huge
	end
	local gap = result.Position.Y - (origin.Y + topExtent)
	return (gap - Config.CeilingClearance) * Config.CeilingStiffness
end

function GliderSession._hitSomething(self: Session, velocity: Vector3, dt: number, params: RaycastParams): boolean
	local position = self.root.Position
	if position.Y < Config.KillHeight then
		return true
	end

	local groundProbe = Config.FeetBelowRoot + Config.GroundClearance
	if workspace:Raycast(position, Vector3.new(0, -groundProbe, 0), params) then
		return true
	end

	-- Volumen del ala + jugadores colgados, barrido en la dirección de vuelo.
	local height = self.wingTop + Config.FeetBelowRoot
	local center = self.root.CFrame * CFrame.new(0, (self.wingTop - Config.FeetBelowRoot) / 2, 0)
	local size = Vector3.new(self.gliderSize.X, height, 2)
	local sweep = velocity.Unit * (velocity.Magnitude * dt + Config.ObstacleProbeDistance)
	local result = workspace:Blockcast(center, size, sweep, params)
	return result ~= nil and not isCeiling(result)
end

function GliderSession._fly(self: Session, dt: number, params: RaycastParams)
	local flight = self.flight
	local maxVertical = self:_ceilingLimit(params)

	-- Sustentación: lift ∈ [-1, 1] alrededor del punto neutro, con curva arcade.
	local neutral = Config.NeutralLiftPoint
	local liftInput = flight.liftInput
	local lift = if liftInput <= neutral then (liftInput - neutral) / neutral else (liftInput - neutral) / (1 - neutral)
	lift = GliderMath.curve(lift, Config.LiftCurve)
	local targetVertical = if lift >= 0 then lift * Config.MaxClimbSpeed else lift * Config.MaxFallSpeed
	flight.verticalSpeed = GliderMath.approach(flight.verticalSpeed, targetVertical, Config.VerticalResponse, dt)
	-- El techo recorta la subida guardada: al bajar la sustentación, el ala se despega enseguida.
	flight.verticalSpeed = math.min(flight.verticalSpeed, maxVertical)

	-- Balance → alabeo (muelle con rebote) → giro de rumbo.
	local balance = GliderMath.curve(flight.balanceInput, Config.BalanceCurve)
	local targetRoll = balance * Config.MaxRoll
	flight.roll, flight.rollVelocity =
		GliderMath.spring(flight.roll, flight.rollVelocity, targetRoll, Config.RollResponse, Config.RollDamping, dt)
	local targetTurn = (flight.roll / Config.MaxRoll) * Config.MaxTurnRate
	flight.turnRate = GliderMath.approach(flight.turnRate, targetTurn, Config.TurnResponse, dt)
	flight.yaw += math.rad(flight.turnRate) * dt

	-- Pitch visual según la velocidad vertical actual (rozando el techo queda nivelado).
	local verticalRange = if flight.verticalSpeed >= 0 then Config.MaxClimbSpeed else Config.MaxFallSpeed
	local targetPitch = (flight.verticalSpeed / verticalRange) * Config.MaxPitch
	flight.pitch, flight.pitchVelocity =
		GliderMath.spring(flight.pitch, flight.pitchVelocity, targetPitch, Config.PitchResponse, Config.PitchDamping, dt)

	-- Corrientes de aire: continuas, lentas y pequeñas. Cada ala tiene su propio "viento".
	local t = flight.time * Config.WindFlowSpeed + self.id * 17.3
	local wind = Config.WindFlowStrength
	local windPitch = GliderMath.flow(t, 1.7) * Config.WindPitchAmplitude * wind
	local windRoll = GliderMath.flow(t, 5.3) * Config.WindRollAmplitude * wind
	local windVertical = GliderMath.flow(t * 0.8, 9.1) * Config.WindVerticalAmplitude * wind

	local heading = CFrame.Angles(0, flight.yaw, 0)
	local vertical = math.min(flight.verticalSpeed + windVertical, maxVertical)
	local velocity = heading.LookVector * Config.ForwardSpeed + Vector3.new(0, vertical, 0)
	self.linearVelocity.VectorVelocity = velocity
	self.alignOrientation.CFrame = heading
		* CFrame.Angles(math.rad(flight.pitch + windPitch), 0, 0)
		* CFrame.Angles(0, 0, math.rad(flight.roll + windRoll))

	if self:_hitSomething(velocity, dt, params) then
		self:_crash()
	end
end

function GliderSession._broadcast(self: Session, dt: number)
	local flight = self.flight
	flight.broadcastTimer += dt
	if flight.broadcastTimer < Config.StateBroadcastInterval then
		return
	end
	flight.broadcastTimer = 0
	local glider = self.glider
	glider:SetAttribute("LeftPosition", flight.leftPosition / Config.BarOuterOffset)
	glider:SetAttribute("RightPosition", flight.rightPosition / Config.BarOuterOffset)
	glider:SetAttribute("LiftInput", flight.liftInput)
	glider:SetAttribute("BalanceInput", flight.balanceInput)
	glider:SetAttribute("VerticalSpeed", flight.verticalSpeed)
	glider:SetAttribute("Roll", flight.roll)
	glider:SetAttribute("TurnRate", flight.turnRate)
	glider:SetAttribute("Countdown", math.max(0, Config.CountdownTime - flight.timer))
	glider:SetAttribute("Altitude", self.root.Position.Y)
	glider:SetAttribute("RunTime", self.runTime)
	if flight.state == "Flying" then
		self:_updateTrails()
	end
end

function GliderSession.step(self: Session, dt: number, params: RaycastParams)
	if self.finished then
		return
	end
	local flight = self.flight
	flight.time += dt
	flight.timer += dt
	if self.timing then
		self.runTime += dt
	end

	self:_updateSlides(dt)
	self:_computeInputs()

	local state = flight.state
	if state == "Countdown" then
		if flight.timer >= Config.CountdownTime then
			self:_launch()
		end
	elseif state == "Flying" then
		self:_fly(dt, params)
	elseif state == "Ended" then
		if flight.timer >= Config.CrashPauseTime then
			if self.completed then
				self:finish("completed") -- aterrizaron tras la meta: fin del recorrido
				return
			end
			self:resetToCheckpoint() -- choque: el mismo dúo sigue desde su último checkpoint
		end
	end

	self:_broadcast(dt)
end

return GliderSession
