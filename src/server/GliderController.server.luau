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
--
-- Tutorial (Map.Tutorial): un jugador + un bot compañero (TutorialBot), 3 tramos cortos. Solo la primera
-- vez que alguien entra (sin PlayerStats.TutorialDone) se le ofrece en pantalla; acepte o rechace, ya no se
-- vuelve a ofrecer. Durante el tutorial se puede saltar (botón SKIP o Lobby). No cuenta para estadísticas
-- ni clasificación.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Glider")
local Config = require(Shared.GliderConfig)
local Checkpoints = require(script.Parent.Checkpoints)
local CollisionGroups = require(script.Parent.CollisionGroups)
local DuoLeaderboard = require(script.Parent.DuoLeaderboard)
local GliderSession = require(script.Parent.GliderSession)
local LevelStreaming = require(script.Parent.LevelStreaming)
local Lobby = require(script.Parent.Lobby)
local PlayerStats = require(script.Parent.PlayerStats)
local TutorialBot = require(script.Parent.TutorialBot)
local remote = Shared:WaitForChild("GliderRemote") :: RemoteEvent

CollisionGroups.setup()
PlayerStats.start()
local map = workspace:FindFirstChild("Map")
local tutorialMap = map and map:FindFirstChild("Tutorial")
local mainCourse = Checkpoints.new(map)
local tutorialCourse = Checkpoints.new(tutorialMap)
LevelStreaming.load(map)
LevelStreaming.load(tutorialMap)
DuoLeaderboard.start(mainCourse:count())

-- Indicaciones del bot por tramo del tutorial.
local tutorialCues: { [number]: { TutorialBot.Cue } } = {}
for index = 1, tutorialCourse:count() do
	tutorialCues[index] = TutorialBot.cuesOf(tutorialMap and tutorialMap:FindFirstChild(string.format("Level%02d", index)))
end

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
local wasFlying: { [Session]: true } = {} -- volaba en el paso anterior (para contar choques)
local inCountdown: { [Session]: true } = {} -- en cuenta atrás en el paso anterior (para cargar la zona al empezarla)
local devRuns: { [Session]: true } = {} -- vuelos de prueba (DevStartLevel): no cuentan para las estadísticas
local tutorialRuns: { [Session]: true } = {} -- vuelos del tutorial (con bot): tampoco cuentan
local courseOf: { [Session]: Checkpoints.Course } = {}
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
	wasFlying[session] = nil
	inCountdown[session] = nil
	devRuns[session] = nil
	courseOf[session] = nil
	local wasTutorial = tutorialRuns[session]
	tutorialRuns[session] = nil
	for _, player in session.members do
		if sessionOf[player] == session then
			sessionOf[player] = nil
		end
	end
	if reason == "empty" then
		return
	end
	if wasTutorial then
		-- Terminado o saltado (botón SKIP o Lobby): ya no vuelve a empezar solo.
		for _, player in riders do
			PlayerStats.markTutorialDone(player)
		end
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

-- Pruebas: con el atributo DevStartLevel (1-50) en Workspace.Map, las alas despegan en
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
	return math.clamp(session.checkpoint + 1, 1, math.max(courseOf[session]:count(), 1))
end

local function publishLevel(session: Session)
	local course = courseOf[session]
	local level = levelOf(session)
	local title, color = course:levelInfo(level)
	local glider = session.glider
	glider:SetAttribute("Level", level)
	glider:SetAttribute("LevelCount", course:count())
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
	courseOf[session] = mainCourse
	if startCheckpoint > 0 then
		devRuns[session] = true
	end
	publishLevel(session)
	for _, player in duo do
		sessionOf[player] = session
		if not devRuns[session] then
			PlayerStats.runStarted(player)
		end
	end
end

-- Tutorial para un jugador, con el bot en el otro hueco. Despega en Map.Tutorial.StartIsland.LaunchPoint.
local function startTutorial(player: Player)
	local start = tutorialMap and tutorialMap:FindFirstChild("StartIsland")
	local launch = start and start:FindFirstChild("LaunchPoint")
	if not (launch and launch:IsA("BasePart")) or tutorialCourse:count() == 0 then
		warn("[Glider] No hay Map.Tutorial: regenera el mapa con MapBuilder para tener tutorial")
		return
	end
	if player.Parent ~= Players or isBusy(player) or not isAlive(player) then
		return
	end
	local bot = TutorialBot.create()
	if not bot then
		return
	end
	nextId += 1
	local session = GliderSession.new(nextId, template, gliderFolder, { player }, onSessionFinished, launch.CFrame, 0)
	session:addBot(bot, TutorialBot.SIDE)
	sessions[session] = true
	courseOf[session] = tutorialCourse
	tutorialRuns[session] = true
	session.glider:SetAttribute("Tutorial", true)
	publishLevel(session)
	sessionOf[player] = session
end

-- El ala cruzó un checkpoint: desde aquí reaparece, y ambos ven la pantalla de checkpoint.
-- Récords (solo vuelos desde la salida): estadísticas de cada jugador y clasificación del dúo.
local function reachCheckpoint(session: Session, checkpoint: Checkpoints.Checkpoint)
	session:setCheckpoint(checkpoint.index, checkpoint.spawn, checkpoint.final)
	publishLevel(session)
	local counts = not devRuns[session] and not tutorialRuns[session]
	local riders = session:riders()
	local runTime = session.runTime
	local info = checkpoint.info
	if checkpoint.final or tutorialRuns[session] then
		info = table.clone(info)
		info.time = runTime -- la pantalla de meta muestra el tiempo del recorrido
		info.tutorial = tutorialRuns[session] -- "TUTORIAL COMPLETE!" en vez de "COURSE COMPLETE!"
	end
	local personalBest: { [Player]: boolean } = {}
	for _, player in riders do
		remote:FireClient(player, "Checkpoint", info)
		if counts then
			-- Solo récords: el siguiente vuelo vuelve a empezar en la salida.
			PlayerStats.levelCleared(player, checkpoint.index)
			if checkpoint.final then
				personalBest[player] = PlayerStats.courseCompleted(player, runTime)
			end
		end
	end
	if not counts then
		return
	end
	-- En la meta, cada uno recibe su resultado cuando responde el almacén (récord del dúo y puesto).
	local onResult = if checkpoint.final
		then function(duoRecord: boolean, rank: number?)
			for _, player in riders do
				if player.Parent == Players then
					remote:FireClient(player, "DuoResult", { time = runTime, duoRecord = duoRecord, rank = rank, personalBest = personalBest[player] == true })
				end
			end
		end
		else nil
	DuoLeaderboard.submit(riders, checkpoint.index, runTime, onResult)
end

Lobby.start({ isBusy = isBusy, onDuoReady = startSession })

-- La primera vez que alguien entra (sin TutorialDone guardado) se le ofrece el tutorial en pantalla
-- ("TutorialOffer"); el cliente responde con "TutorialAnswer" (true = jugar). Se espera a que su personaje
-- esté en el lobby; si no aparece en ~30 s o ya está volando, no se ofrece.
local tutorialOffered: { [Player]: true } = {}
PlayerStats.onLoaded(function(player: Player, stats: PlayerStats.Stats)
	if stats.TutorialDone or tutorialCourse:count() == 0 then
		return
	end
	for _ = 1, 60 do
		if player.Parent ~= Players or isBusy(player) then
			return
		end
		if isAlive(player) then
			task.wait(1.5) -- un momento en el lobby antes de preguntar
			if player.Parent == Players and not isBusy(player) then
				tutorialOffered[player] = true
				remote:FireClient(player, "TutorialOffer")
			end
			return
		end
		task.wait(0.5)
	end
end)

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
	if kind == "TutorialAnswer" then
		-- Solo cuenta si se le ofreció: acepte o rechace, ya no se vuelve a ofrecer.
		if tutorialOffered[player] then
			tutorialOffered[player] = nil
			PlayerStats.markTutorialDone(player)
			if value == true then
				startTutorial(player)
			end
		end
		return
	end
	local session = activeSession(player)
	if not session then
		return
	end
	if kind == "Lobby" then
		session:finish("lobby") -- cualquiera de los dos cancela el vuelo del dúo
	elseif kind == "SkipTutorial" then
		if tutorialRuns[session] then
			session:finish("lobby")
		end
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
		local course = courseOf[session]
		if publishProgress and not session.completed then
			session.glider:SetAttribute("LevelProgress", course:progress(levelOf(session), session.root.Position))
		end
		if tutorialRuns[session] then
			local level = levelOf(session)
			local progress = if session.flight.state == "Flying" then course:progress(level, session.root.Position) else 0
			local hint = TutorialBot.step(session.slots, session.flight.state, tutorialCues[level] or {}, progress)
			if session.glider:GetAttribute("TutorialHint") ~= hint then
				session.glider:SetAttribute("TutorialHint", hint)
			end
		end
		-- Checkpoints: tramo recorrido desde el paso anterior (solo en vuelo; tras reaparecer se empieza de cero).
		-- Choque: pasa de volar a "Ended" sin haber cruzado la meta (aterrizar tras la meta no es choque).
		local flying = session.flight.state == "Flying"
		if wasFlying[session] and session.flight.state == "Ended" and not session.completed and not devRuns[session] and not tutorialRuns[session] then
			for _, player in session:riders() do
				PlayerStats.crashed(player)
			end
		end
		if flying then
			wasFlying[session] = true
		else
			wasFlying[session] = nil
		end
		-- Empieza una cuenta atrás (despegue o reaparición en el checkpoint): el ala acaba de saltar de sitio,
		-- se pide cargar esa zona mientras cuenta.
		if session.flight.state == "Countdown" then
			if not inCountdown[session] then
				for _, player in session:riders() do
					LevelStreaming.prepare(player, session.respawnCFrame.Position)
				end
			end
			inCountdown[session] = true
		else
			inCountdown[session] = nil
		end
		if flying then
			local position = session.root.Position
			local previous = lastPosition[session]
			local checkpoint = previous and course:crossed(previous, position, session.checkpoint)
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
	tutorialOffered[player] = nil
end)
