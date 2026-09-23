--!strict
-- Controlador del juego: muchos dúos a la vez, cada uno con su propia ala delta.
--
-- Ciclo:  lobby → plataforma de dúo (2 jugadores) → se clona un ala en la salida → vuelan
--         → cada isla de descanso es un CHECKPOINT (pantalla en ambos clientes)
--         → choque (o botón Reset) → el mismo dúo reaparece en su último checkpoint
--         → botón Lobby (cualquiera de los dos), que uno se vaya o muera, o aterrizar tras la meta
--           → el dúo vuelve al lobby
--
-- Las alas y jugadores de distintos dúos no chocan entre sí (CollisionGroups) y cada
-- cliente ve a los otros dúos ligeramente transparentes (GliderClient).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Glider")
local Config = require(Shared.GliderConfig)
local Checkpoints = require(script.Parent.Checkpoints)
local CollisionGroups = require(script.Parent.CollisionGroups)
local GliderSession = require(script.Parent.GliderSession)
local LevelStreaming = require(script.Parent.LevelStreaming)
local Lobby = require(script.Parent.Lobby)
local remote = Shared:WaitForChild("GliderRemote") :: RemoteEvent

CollisionGroups.setup()
Checkpoints.load(workspace:FindFirstChild("Map"))
LevelStreaming.load(workspace:FindFirstChild("Map"))

-- La AlaDelta del mapa es la plantilla: marca dónde y cómo sale cada ala. Nadie vuela la original.
local template = workspace:WaitForChild(Config.GliderName) :: Model
template.Parent = ServerStorage

local gliderFolder = Instance.new("Folder")
gliderFolder.Name = Config.GliderFolderName
gliderFolder.Parent = workspace

type Session = GliderSession.Session

local sessions: { [Session]: true } = {}
local sessionOf: { [Player]: Session } = {}
local lastPosition: { [Session]: Vector3 } = {} -- posición del ala en el paso anterior (cruce de checkpoints)
local nextId = 0

-- Sesión en la que el jugador sigue colgado (si murió o se soltó, ya no cuenta).
local function activeSession(player: Player): Session?
	local session = sessionOf[player]
	if session and not session.finished and session:slotOf(player) then
		return session
	end
	sessionOf[player] = nil
	return nil
end

local function isBusy(player: Player): boolean
	return activeSession(player) ~= nil
end

local function isAlive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and character:FindFirstChild("HumanoidRootPart") ~= nil
end

local function onSessionFinished(session: Session, reason: GliderSession.FinishReason, riders: { Player })
	sessions[session] = nil
	lastPosition[session] = nil
	for _, player in session.members do
		if sessionOf[player] == session then
			sessionOf[player] = nil
			LevelStreaming.clear(player)
		end
	end
	if reason == "empty" then
		return
	end

	-- Botón Lobby o meta: todo el dúo vuelve al lobby (reaparece en su SpawnLocation).
	for _, player in riders do
		if player.Parent == Players then
			task.spawn(function()
				player:LoadCharacter()
			end)
		end
	end
end

-- Pruebas: con el atributo DevStartLevel (1-10) en Workspace.Map, las alas despegan en
-- Map.DevSpawns.LevelNN en vez de en la StartIsland (y los niveles anteriores cuentan como superados).
-- 0 o sin atributo = recorrido normal.
local function devLaunchPoint(): (CFrame?, number)
	local map = workspace:FindFirstChild("Map")
	local level = map and map:GetAttribute("DevStartLevel")
	if type(level) ~= "number" or level < 1 then
		return nil, 0
	end
	local spawns = map and map:FindFirstChild("DevSpawns")
	local point = spawns and spawns:FindFirstChild(string.format("Level%02d", level))
	if point and point:IsA("BasePart") then
		return point.CFrame, level - 1
	end
	return nil, 0
end

-- Nivel en curso (el siguiente al último checkpoint) para el HUD: número, total, título y color del bioma.
local function levelOf(session: Session): number
	return math.clamp(session.checkpoint + 1, 1, math.max(Checkpoints.count(), 1))
end

local function publishLevel(session: Session)
	local level = levelOf(session)
	local title, color = Checkpoints.levelInfo(level)
	local glider = session.glider
	glider:SetAttribute("Level", level)
	glider:SetAttribute("LevelCount", Checkpoints.count())
	glider:SetAttribute("LevelTitle", title)
	glider:SetAttribute("LevelColor", color)
	glider:SetAttribute("LevelProgress", if session.completed then 1 else 0)
end

local function startSession(players: { Player })
	local duo = {}
	for _, player in players do
		if player.Parent == Players and not isBusy(player) and isAlive(player) then
			table.insert(duo, player)
		end
	end
	local required = if Config.RequireBothPlayers then 2 else 1
	if #duo < required then
		return
	end

	nextId += 1
	local launchAt, startCheckpoint = devLaunchPoint()
	local session = GliderSession.new(nextId, template, gliderFolder, duo, onSessionFinished, launchAt, startCheckpoint)
	sessions[session] = true
	publishLevel(session)
	for _, player in duo do
		sessionOf[player] = session
		LevelStreaming.setWindow(player, session.checkpoint)
	end
end

-- El ala cruzó un checkpoint: desde aquí reaparece, y ambos ven la pantalla de checkpoint.
local function reachCheckpoint(session: Session, checkpoint: Checkpoints.Checkpoint)
	session:setCheckpoint(checkpoint.index, checkpoint.spawn, checkpoint.final)
	publishLevel(session)
	for _, player in session:riders() do
		LevelStreaming.setWindow(player, checkpoint.index)
		remote:FireClient(player, "Checkpoint", checkpoint.info)
	end
end

Lobby.start({ isBusy = isBusy, onDuoReady = startSession })

-- ── Mensajes de los clientes ──────────────────────────────────────────

-- Filtro previo contra inundar el remoto: tipo de mensaje válido y tope de mensajes por jugador
-- (el doble del límite de Axis; la sesión aplica además sus propios límites y el cooldown de Reset).
local messageWindow: { [Player]: { start: number, count: number } } = {}
local function allowMessage(player: Player, kind: unknown): boolean
	if type(kind) ~= "string" or #kind > 32 then
		return false
	end
	local now = os.clock()
	local window = messageWindow[player]
	if not window or now - window.start > 1 then
		window = { start = now, count = 0 }
		messageWindow[player] = window
	end
	window.count += 1
	return window.count <= Config.MaxInputsPerSecond * 2
end

remote.OnServerEvent:Connect(function(player: Player, kind: unknown, value: unknown)
	if not allowMessage(player, kind) then
		return
	end
	local session = activeSession(player)
	if not session then
		return
	end
	if kind == "Lobby" then
		session:finish("lobby") -- cualquiera de los dos cancela el vuelo del dúo
	else
		session:handleMessage(player, kind, value)
	end
end)

-- ── Simulación ────────────────────────────────────────────────────────

local probeParams = CollisionGroups.probeParams()
local lobbyTimer = 0
local progressTimer = 0

RunService.Heartbeat:Connect(function(rawDt)
	local dt = math.min(rawDt, Config.MaxDeltaTime)
	progressTimer += rawDt
	local publishProgress = progressTimer >= Config.StateBroadcastInterval
	if publishProgress then
		progressTimer = 0
	end
	for session in sessions do
		if publishProgress and not session.completed then
			session.glider:SetAttribute("LevelProgress", Checkpoints.progress(levelOf(session), session.root.Position))
		end
		-- Checkpoints: tramo recorrido desde el paso anterior (solo en vuelo; tras reaparecer se empieza de cero).
		if session.flight.state == "Flying" then
			local position = session.root.Position
			local previous = lastPosition[session]
			local checkpoint = previous and Checkpoints.crossed(previous, position, session.checkpoint)
			if checkpoint then
				reachCheckpoint(session, checkpoint)
			end
			lastPosition[session] = position
		else
			lastPosition[session] = nil
		end
		session:step(dt, probeParams)
	end

	lobbyTimer += rawDt
	if lobbyTimer >= Config.LobbyTickInterval then
		Lobby.step(lobbyTimer)
		lobbyTimer = 0
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local session = activeSession(player)
	if session then
		session:removePlayer(player)
	end
	sessionOf[player] = nil
	messageWindow[player] = nil
	LevelStreaming.clear(player)
end)
