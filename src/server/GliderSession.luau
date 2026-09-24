--!strict
-- Una sesión = un ala delta clonada de la plantilla + un dúo de jugadores + su vuelo.
-- Autoridad total del servidor: los clientes solo envían su eje A/D (-1, 0, 1).
--
-- Cadena de vuelo (ecuaciones en GliderPhysics, compartidas con FlightTester y tools/sim):
--   posición de ambos en la barra → LiftInput (distancia al centro) / BalanceInput (centro de masa)
--   → velocidad vertical (suavizada) + alabeo (muelle) → giro de rumbo (suavizado) [+ asistencia]
--   → LinearVelocity (avance + vertical) y AlignOrientation (rumbo, pitch, roll)
-- Tocar algo no es morir: el ala resbala y pierde corazones (golpes fuertes o roces largos). Sin corazones se
-- pierde el ala: voltereta corta y reaparición en el último PUNTO SEGURO (checkpoint o un tramo reciente de
-- vuelo limpio que guarda el controlador).
-- Los "slots" 1 y 2 solo indican dónde empieza cada uno; ninguno tiene un lado propio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Glider.GliderConfig)
local GliderMath = require(ReplicatedStorage.Glider.GliderMath)
local GliderPhysics = require(ReplicatedStorage.Glider.GliderPhysics)
local CollisionGroups = require(script.Parent.CollisionGroups)
local RiderRig = require(script.Parent.RiderRig)

local LEFT, RIGHT = -1, 1

type Slot = {
	player: Player?,
	bot: Model?, -- compañero bot del tutorial (TutorialBot mueve su `axis`)
	rig: RiderRig.Rig?,
	axis: number, -- -1 A, 0 nada, 1 D (visual, desde la cámara trasera)
	position: number, -- studs desde el centro de la barra (-izquierda, +derecha), toda la barra
	slideVelocity: number, -- studs/s
	inputWindowStart: number,
	inputCount: number,
	diedConnection: RBXScriptConnection?,
}

-- lobby = el dúo pidió volver al lobby · completed = aterrizó tras cruzar la meta · empty = no queda nadie.
-- Perder el ala NO termina la sesión: reaparece en su último punto seguro.
export type FinishReason = "lobby" | "completed" | "empty"

local GliderSession = {}
GliderSession.__index = GliderSession

export type Session = typeof(setmetatable(
	{} :: {
		id: number,
		glider: Model,
		root: BasePart,
		respawnForward: Vector3, -- rumbo al reaparecer (salida o último checkpoint)
		respawnCFrame: CFrame, -- salida o último checkpoint
		safeCFrame: CFrame, -- dónde reaparece el ala al perderla o con Respawn (checkpoint o punto seguro posterior)
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
		physics: GliderPhysics.State,
		health: GliderPhysics.Health,
		dims: GliderPhysics.Dimensions,
		cleanTime: number, -- segundos seguidos de vuelo sin tocar nada
		sinceSafePoint: number, -- segundos de vuelo desde el último punto seguro
		levelLosses: number, -- alas perdidas desde el último checkpoint (viento a favor, medalla)
		levelHits: number, -- golpes desde el último checkpoint (medalla)
		windAssist: boolean,
		assistGoal: Vector3?, -- punto de la línea ideal al que apunta la asistencia (lo pone el controlador)
		assistStrength: number, -- 0-1 según el nivel (lo pone el controlador)
		impacts: number, -- golpes (contador publicado: efectos en el cliente)
		respawns: number, -- reapariciones (contador publicado)
		crashFrom: CFrame?, -- dónde se perdió el ala (voltereta)
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
		bot = nil,
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
		safeCFrame = root.CFrame,
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
			state = "Countdown", -- Countdown | Flying | Ended (ala perdida) | Landed (meta)
			timer = 0,
			countdown = Config.CountdownTime, -- duración de la cuenta atrás actual (más corta al reaparecer)
			time = 0,
			broadcastTimer = 0,
			liftInput = 0,
			balanceInput = 0,
			leftPosition = 0, -- posiciones efectivas (incluye el compañero fantasma en solitario)
			rightPosition = 0,
			scraping = false,
			skimming = false,
		},
		physics = GliderPhysics.newState(GliderMath.yawOf(forward)),
		health = GliderPhysics.newHealth(),
		dims = { span = size.X, wingTop = wingTop },
		cleanTime = 0,
		sinceSafePoint = 0,
		levelLosses = 0,
		levelHits = 0,
		windAssist = false,
		assistGoal = nil,
		assistStrength = 0,
		impacts = 0,
		respawns = 0,
		crashFrom = nil,
		lastReset = -math.huge,
		finished = false,
		members = table.clone(players),
		onFinished = onFinished,
	}, GliderSession)

	for index, player in players do
		self:_board(player, if index == 1 then LEFT else RIGHT)
	end
	glider:SetAttribute("Checkpoint", self.checkpoint)
	glider:SetAttribute("Hearts", self.health.hearts)
	glider:SetAttribute("MaxHearts", Config.WingHearts)
	glider:SetAttribute("Span", size.X) -- efectos del cliente ("Close!")
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
	local physics = self.physics
	local turning = math.abs(physics.turnRate) / Config.MaxTurnRate
	local diving = math.max(0, -physics.verticalSpeed) / Config.MaxFallSpeed
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

-- LeftUserId / RightUserId: UserId de quien va en cada hueco, 0 = vacío, -1 = bot del tutorial.
function GliderSession._publishSlots(self: Session)
	local function id(slot: Slot): number
		return if slot.player then slot.player.UserId elseif slot.bot then -1 else 0
	end
	self.glider:SetAttribute("LeftUserId", id(self.slots[LEFT]))
	self.glider:SetAttribute("RightUserId", id(self.slots[RIGHT]))
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

-- Cuelga un personaje bot (TutorialBot) en el hueco `side`. Va dentro del modelo del ala: los clientes lo ven
-- como parte de su ala (OtherDuos) y se destruye con ella al terminar.
function GliderSession.addBot(self: Session, character: Model, side: number)
	local slot = self.slots[side]
	character.Parent = self.glider
	slot.position = lateralFor(side, Config.StartOutward)
	local rig = RiderRig.attach(character, self.root, side, slot.position)
	if not rig then
		character:Destroy()
		return
	end
	slot.bot = character
	slot.rig = rig
	self:_publishSlots()
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
	if #self:riders() == 0 then
		self:finish("empty") -- no queda ningún jugador (un bot solo no vuela)
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
			self:respawn(true) -- botón Respawn: vuelve al último punto seguro
		end
	end
end

-- ── Ciclo de vuelo ────────────────────────────────────────────────────

-- Guarda un checkpoint alcanzado: a partir de ahora el ala reaparece ahí (centro de la isla, a la altura
-- de vuelo, mirando al siguiente nivel) con los corazones llenos. final = meta: al terminar este vuelo el dúo
-- vuelve al lobby.
function GliderSession.setCheckpoint(self: Session, index: number, spawn: CFrame, final: boolean)
	self.checkpoint = index
	self.respawnCFrame = spawn
	self.respawnForward = (spawn.LookVector * Vector3.new(1, 0, 1)).Unit
	self.safeCFrame = spawn
	self.sinceSafePoint = 0
	self.completed = final
	if final then
		self.timing = false -- la meta para el cronómetro
	end
	self.levelLosses = 0
	self.levelHits = 0
	self:_setWindAssist(false)
	self.health.hearts = Config.WingHearts
	self.health.scrapeTime = 0
	self.glider:SetAttribute("Hearts", self.health.hearts)
	self.glider:SetAttribute("Checkpoint", index)
	self.glider:SetAttribute("Completed", final)
	self.glider:SetAttribute("RunTime", self.runTime)
end

-- Punto seguro: el controlador lo guarda cada SafePointInterval s de vuelo limpio (sitio despejado, mirando
-- hacia la línea ideal). Perder el ala o Respawn reaparecen aquí en vez de en el checkpoint.
function GliderSession.wantsSafePoint(self: Session): boolean
	return self.flight.state == "Flying"
		and not self.completed
		and self.sinceSafePoint >= Config.SafePointInterval
		and self.cleanTime >= Config.SafePointCleanTime
end

function GliderSession.setSafePoint(self: Session, cframe: CFrame)
	self.safeCFrame = cframe
	self.sinceSafePoint = 0
end

-- El sitio no estaba despejado: se vuelve a intentar dentro de `seconds`.
function GliderSession.deferSafePoint(self: Session, seconds: number)
	self.sinceSafePoint = Config.SafePointInterval - seconds
end

function GliderSession._setWindAssist(self: Session, enabled: boolean)
	if self.windAssist ~= enabled then
		self.windAssist = enabled
		self.glider:SetAttribute("WindAssist", enabled)
	end
end

-- Reaparece en el último punto seguro (o checkpoint, o salida) con los corazones llenos y una cuenta atrás
-- corta. lostWing = viene de perder el ala o de Respawn: cuenta para el "viento a favor".
function GliderSession.respawn(self: Session, lostWing: boolean?)
	self.root.Anchored = true
	self.linearVelocity.Enabled = false
	self.alignOrientation.Enabled = false
	self:_setTrails(false)
	local spawn = self.safeCFrame
	self.root.CFrame = spawn
	self.root.AssemblyLinearVelocity = Vector3.zero
	self.root.AssemblyAngularVelocity = Vector3.zero

	local forward = spawn.LookVector * Vector3.new(1, 0, 1)
	self.physics = GliderPhysics.newState(GliderMath.yawOf(if forward.Magnitude > 1e-3 then forward.Unit else self.respawnForward))
	self.health = GliderPhysics.newHealth()
	self.cleanTime = 0
	self.sinceSafePoint = 0
	self.crashFrom = nil
	for side, slot in self.slots do
		slot.position = lateralFor(side, Config.StartOutward)
		slot.slideVelocity = 0
	end
	if lostWing and not self.completed then
		self.levelLosses += 1
		if self.levelLosses >= Config.WindAssistAfterCrashes then
			self:_setWindAssist(true)
		end
	end
	self.respawns += 1
	self.glider:SetAttribute("Respawns", self.respawns)
	self.glider:SetAttribute("Hearts", self.health.hearts)
	self.flight.countdown = Config.RespawnCountdown
	self.flight.scraping = false
	self.flight.skimming = false
	self:_setState("Countdown")
end

-- Compatibilidad: antes solo se reaparecía en el checkpoint.
function GliderSession.resetToCheckpoint(self: Session)
	self:respawn(true)
end

function GliderSession._launch(self: Session)
	local rotation = self.safeCFrame.Rotation
	self.alignOrientation.CFrame = rotation
	self.root.Anchored = false
	self.root:SetNetworkOwner(nil) -- servidor dueño: ningún cliente simula el ala
	self.linearVelocity.VectorVelocity = GliderPhysics.forwardOf(self.physics.yaw) * self.physics.speed
	self.linearVelocity.Enabled = true
	if not self.completed then
		self.timing = true -- el primer despegue arranca el cronómetro (los siguientes no lo reinician)
	end
	self.alignOrientation.Enabled = true
	self:_setTrails(true)
	self:_setState("Flying")
end

-- Sin corazones (o caída fuera del mundo): el ala se pierde. Voltereta corta (CrashPauseTime) y reaparición.
function GliderSession._crash(self: Session)
	self.crashFrom = self.root.CFrame
	self.root.Anchored = true
	self.linearVelocity.Enabled = false
	self.alignOrientation.Enabled = false
	self:_setTrails(false)
	self.health.hearts = 0
	self.glider:SetAttribute("Hearts", 0)
	self:_setState("Ended")
end

-- Voltereta del ala perdida: cae girando sobre sí misma mientras avanza un poco (anclada, sin física).
function GliderSession._tumble(self: Session)
	local from = self.crashFrom
	if not from then
		return
	end
	local t = self.flight.timer
	local forward = self.physics.speed * 0.4
	self.root.CFrame = from * CFrame.new(0, -14 * t * t, -forward * t) * CFrame.Angles(-1.2 * t, 0, 6 * t)
end

-- Aterrizaje en la isla de meta: el ala se desliza hasta pararse, nivelada, y el dúo vuelve al lobby.
function GliderSession._land(self: Session)
	self.root.Anchored = true
	self.linearVelocity.Enabled = false
	self.alignOrientation.Enabled = false
	self:_setTrails(false)
	self.flight.landSpeed = self.physics.speed
	self:_setState("Landed")
end

function GliderSession._slideToStop(self: Session, dt: number)
	local flight = self.flight
	flight.landSpeed = GliderMath.approach(flight.landSpeed or 0, 0, 1.4, dt)
	local current = self.root.CFrame
	local level = CFrame.new(current.Position) * CFrame.Angles(0, self.physics.yaw, 0)
	local rotation = current.Rotation:Lerp(level.Rotation, 1 - math.exp(-6 * dt))
	self.root.CFrame = CFrame.new(current.Position + GliderPhysics.forwardOf(self.physics.yaw) * flight.landSpeed * dt) * rotation
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
-- El cuerpo cuelga de las manos como un péndulo: se balancea al deslizarse y se queda "vertical" cuando el ala
-- alabea (RiderRig.setPose).
function GliderSession._updateSlides(self: Session, dt: number)
	local reach = Config.BarOuterOffset
	local roll = self.physics.roll
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
		local swing = -slot.slideVelocity / Config.PlayerSlideSpeed * Config.RiderSlideSwing - roll * Config.RiderRollSwing
		RiderRig.setPose(rig, slot.position, swing)
	end
end

-- Posiciones de ambos cuerpos → LiftInput y BalanceInput (GliderPhysics.inputs). No existe "lado" de cada
-- jugador: LiftInput = lo abiertos que están (da igual hacia qué lado) · BalanceInput = hacia dónde cae el peso.
-- En solitario, el hueco vacío es un compañero fantasma en espejo: sube y baja pero no gira.
function GliderSession._computeInputs(self: Session)
	local left, right = self.slots[LEFT], self.slots[RIGHT]
	local a, b = left.position, right.position
	if left.rig and not right.rig then
		b = -a
	elseif right.rig and not left.rig then
		a = -b
	end
	local flight = self.flight
	flight.leftPosition, flight.rightPosition = a, b
	flight.liftInput, flight.balanceInput = GliderPhysics.inputs(a, b)
end

function GliderSession._fly(self: Session, dt: number, params: RaycastParams)
	local flight, physics = self.flight, self.physics
	local position = self.root.Position
	if position.Y < Config.KillHeight then
		self:_crash()
		return
	end

	-- Corrientes de aire: continuas, lentas y pequeñas. Cada ala tiene su propio "viento".
	local t = flight.time * Config.WindFlowSpeed + self.id * 17.3
	local wind = Config.WindFlowStrength
	local windPitch = GliderMath.flow(t, 1.7) * Config.WindPitchAmplitude * wind
	local windRoll = GliderMath.flow(t, 5.3) * Config.WindRollAmplitude * wind
	local windVertical = GliderMath.flow(t * 0.8, 9.1) * Config.WindVerticalAmplitude * wind

	-- Asistencia: gira un poco hacia la línea ideal; con viento a favor, además sube o baja hacia ella.
	local assistTurn = 0
	local goal = self.assistGoal
	if goal and not self.completed then
		local fraction = Config.AssistTurnFraction * self.assistStrength
		if self.windAssist then
			fraction = math.max(fraction, Config.WindAssistTurnFraction)
			windVertical += math.clamp((goal.Y - position.Y) * 0.5, -Config.WindAssistVertical, Config.WindAssistVertical)
		end
		if fraction > 0 then
			assistTurn = GliderPhysics.pursuitTurn(position, GliderPhysics.forwardOf(physics.yaw), goal, physics.speed) * fraction
		end
	end

	local result = GliderPhysics.fly(physics, self.health, flight.liftInput, flight.balanceInput, position, self.dims, dt, params, {
		now = flight.time,
		assistTurn = assistTurn,
		landing = self.completed,
		windVertical = windVertical,
	})
	if result.landed then
		self:_land()
		return
	end
	local glider = self.glider
	if result.event == "impact" or result.event == "crash" then
		self.impacts += 1
		self.levelHits += 1
		glider:SetAttribute("Impacts", self.impacts)
		glider:SetAttribute("Hearts", self.health.hearts)
	end
	if result.event == "crash" then
		self:_crash()
		return
	end
	local contact = result.contact
	if contact then
		self.cleanTime = 0
		if result.event == "impact" or not flight.scraping then
			glider:SetAttribute("ContactPoint", contact.Position) -- chispas en el cliente
		end
	else
		self.cleanTime += dt
	end
	flight.scraping = contact ~= nil
	flight.skimming = result.skimming
	self.sinceSafePoint += dt

	self.linearVelocity.VectorVelocity = result.velocity
	self.alignOrientation.CFrame = CFrame.Angles(0, physics.yaw, 0)
		* CFrame.Angles(math.rad(physics.pitch + windPitch), 0, 0)
		* CFrame.Angles(0, 0, math.rad(physics.roll + windRoll))
end

function GliderSession._broadcast(self: Session, dt: number)
	local flight, physics = self.flight, self.physics
	flight.broadcastTimer += dt
	if flight.broadcastTimer < Config.StateBroadcastInterval then
		return
	end
	flight.broadcastTimer = 0
	local glider = self.glider
	glider:SetAttribute("LeftPosition", flight.leftPosition / Config.BarOuterOffset)
	glider:SetAttribute("RightPosition", flight.rightPosition / Config.BarOuterOffset)
	glider:SetAttribute("LeftAxis", self.slots[LEFT].axis) -- intención de cada uno (flechas en el HUD)
	glider:SetAttribute("RightAxis", self.slots[RIGHT].axis)
	glider:SetAttribute("LiftInput", flight.liftInput)
	glider:SetAttribute("BalanceInput", flight.balanceInput)
	glider:SetAttribute("VerticalSpeed", physics.verticalSpeed)
	glider:SetAttribute("Speed", physics.speed)
	glider:SetAttribute("Roll", physics.roll)
	glider:SetAttribute("TurnRate", physics.turnRate)
	glider:SetAttribute("Countdown", math.max(0, flight.countdown - flight.timer))
	glider:SetAttribute("Altitude", self.root.Position.Y)
	glider:SetAttribute("RunTime", self.runTime)
	glider:SetAttribute("Scraping", flight.scraping)
	glider:SetAttribute("Skimming", flight.skimming)
	glider:SetAttribute("Invulnerable", flight.time < self.health.invulnerableUntil)
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
		if flight.timer >= flight.countdown then
			self:_launch()
		end
	elseif state == "Flying" then
		self:_fly(dt, params)
	elseif state == "Ended" then
		if flight.timer >= Config.CrashPauseTime then
			if self.completed then
				self:finish("completed") -- tras la meta, perder el ala también termina el recorrido
				return
			end
			self:respawn(true) -- el mismo dúo sigue desde su último punto seguro
		else
			self:_tumble()
		end
	elseif state == "Landed" then
		if flight.timer >= Config.LandingTime then
			self:finish("completed") -- aterrizaron tras la meta: fin del recorrido
			return
		end
		self:_slideToStop(dt)
	end

	self:_broadcast(dt)
end

return GliderSession
