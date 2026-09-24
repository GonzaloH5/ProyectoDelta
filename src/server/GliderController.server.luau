--!strict
-- Controlador del juego: muchos dúos a la vez, cada uno con su propia ala delta.
--
-- Ciclo:  lobby → plataforma de dúo (2 jugadores) → se clona un ala en la salida → vuelan
--         → cada isla de descanso es un CHECKPOINT (pantalla en ambos clientes)
--         → golpes: el ala resbala y pierde corazones; sin corazones (o botón Respawn) el mismo dúo reaparece
--           en su último PUNTO SEGURO (checkpoint o tramo reciente de vuelo limpio, lo guarda este script)
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
local Analytics = require(script.Parent.Analytics)
local GliderPhysics = require(Shared.GliderPhysics)
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
local runMedals: { [Session]: { [number]: number } } = {} -- medallas de este vuelo: { [3] = oros, [2] = platas, [1] = bronces }
-- Anillos y plumas de cada sesión: anillos cruzados en el nivel actual (se reinician al cambiar de nivel o al
-- reaparecer) y plumas recogidas por nivel (se conservan aunque se pierda el ala).
type Pickups = { level: number, respawns: number, rings: { [number]: true }, feathers: { [number]: { [number]: true } }, counts: { [number]: number }, total: number }
local pickups: { [Session]: Pickups } = {}
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
	local course = courseOf[session]
	courseOf[session] = nil
	local medals = runMedals[session]
	runMedals[session] = nil
	local collected = pickups[session]
	pickups[session] = nil
	local wasTutorial = tutorialRuns[session]
	local wasDev = devRuns[session]
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
			Analytics.funnel(player, Analytics.STEPS.TutorialFinished, { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = reason } :: any)
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

	-- Aterrizaron tras la meta: pantalla de resultados en el lobby (tiempo, medallas, alas perdidas).
	if reason == "completed" and not wasTutorial then
		local summary = {
			time = session.runTime,
			levels = if course then course:count() else session.checkpoint,
			gold = medals and medals[3] or 0,
			silver = medals and medals[2] or 0,
			feathers = if collected then collected.total else 0,
			bronze = medals and medals[1] or 0,
			losses = session.respawns,
			hits = session.impacts,
			practice = wasDev == true, -- empezó en un nivel de pruebas: no cuenta para récords
		}
		task.delay(1.5, function()
			for _, player in riders do
				if player.Parent == Players then
					remote:FireClient(player, "Results", summary)
				end
			end
		end)
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

-- Asistencia de rumbo según el nivel: completa en los capítulos 1-3, se desvanece hasta el capítulo 6.
-- En el tutorial la da el bot (que ya pilota el rumbo), no el servidor.
local function assistStrength(session: Session): number
	if tutorialRuns[session] then
		return 0
	end
	local level = levelOf(session)
	local full, stop = Config.AssistFullUntilLevel, Config.AssistEndLevel
	return math.clamp((stop - level) / math.max(stop - full, 1), 0, 1)
end

local function publishLevel(session: Session)
	local course = courseOf[session]
	local level = levelOf(session)
	local title, color = course:levelInfo(level)
	local glider = session.glider
	session.assistStrength = assistStrength(session)
	glider:SetAttribute("Biome", course:biomeOf(level))
	glider:SetAttribute("Level", level)
	glider:SetAttribute("LevelCount", course:count())
	glider:SetAttribute("LevelTitle", title)
	glider:SetAttribute("LevelColor", color)
	glider:SetAttribute("LevelProgress", if session.completed then 1 else 0)
	local collected = pickups[session]
	glider:SetAttribute("LevelFeatherTotal", #course:feathersOf(level))
	glider:SetAttribute("LevelFeathers", if collected then collected.counts[level] or 0 else 0)
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
	runMedals[session] = {}
	publishLevel(session)
	for _, player in duo do
		sessionOf[player] = session
		if not devRuns[session] then
			PlayerStats.runStarted(player)
			Analytics.funnel(player, Analytics.STEPS.FirstDuoFlight)
			Analytics.levelStarted(player, 1, (mainCourse:levelInfo(1)))
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
	courseOf[session] = tutorialCourse
	tutorialRuns[session] = true
	sessions[session] = true
	session.glider:SetAttribute("Tutorial", true)
	publishLevel(session)
	sessionOf[player] = session
end

-- El ala cruzó un checkpoint: desde aquí reaparece, y ambos ven la pantalla de checkpoint.
-- Récords (solo vuelos desde la salida): estadísticas de cada jugador y clasificación del dúo.
local function reachCheckpoint(session: Session, checkpoint: Checkpoints.Checkpoint)
	-- Medalla del nivel superado (antes de setCheckpoint, que reinicia los contadores del nivel):
	-- oro = sin golpes · plata = sin perder el ala · bronce = superado. El tutorial no da medallas.
	local tutorial = tutorialRuns[session] == true
	local levelHits, levelLosses = session.levelHits, session.levelLosses
	local medal = if tutorial then nil elseif levelHits == 0 and levelLosses == 0 then 3 elseif levelLosses == 0 then 2 else 1
	session:setCheckpoint(checkpoint.index, checkpoint.spawn, checkpoint.final)
	publishLevel(session)
	local counts = not devRuns[session] and not tutorial
	local riders = session:riders()
	local runTime = session.runTime
	local info = table.clone(checkpoint.info)
	info.medal = medal
	local collected = pickups[session]
	local featherTotal = #courseOf[session]:feathersOf(checkpoint.index)
	if featherTotal > 0 then
		info.feathers = if collected then collected.counts[checkpoint.index] or 0 else 0
		info.featherTotal = featherTotal
	end
	if checkpoint.final or tutorial then
		info.time = runTime -- la pantalla de meta muestra el tiempo del recorrido
		info.tutorial = tutorial -- "TUTORIAL COMPLETE!" en vez de "COURSE COMPLETE!"
	end
	if medal then
		local medals = runMedals[session] or {}
		medals[medal] = (medals[medal] or 0) + 1
		runMedals[session] = medals
	end
	local personalBest: { [Player]: boolean } = {}
	for _, player in riders do
		local playerInfo = info
		if counts and medal and PlayerStats.medalEarned(player, checkpoint.index, medal) then
			playerInfo = table.clone(info)
			playerInfo.medalImproved = true -- mejora su medalla guardada de este nivel
		end
		if counts and info.feathers then
			PlayerStats.feathersEarned(player, checkpoint.index, info.feathers)
		end
		remote:FireClient(player, "Checkpoint", playerInfo)
		if counts then
			-- Solo récords: el siguiente vuelo vuelve a empezar en la salida.
			PlayerStats.levelCleared(player, checkpoint.index)
			Analytics.funnel(player, Analytics.STEPS.FirstCheckpoint)
			Analytics.levelCompleted(player, checkpoint.index, info.title or "", levelHits, levelLosses)
			if checkpoint.final then
				personalBest[player] = PlayerStats.courseCompleted(player, runTime)
				Analytics.courseCompleted(player, runTime)
			else
				Analytics.levelStarted(player, checkpoint.index + 1, info.nextTitle or "")
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

Players.PlayerAdded:Connect(function(player)
	Analytics.funnel(player, Analytics.STEPS.Joined)
end)
for _, player in Players:GetPlayers() do
	Analytics.funnel(player, Analytics.STEPS.Joined)
end

-- La primera vez que alguien entra (sin TutorialDone guardado) se le ofrece el tutorial en pantalla
-- ("TutorialOffer"); el cliente responde con "TutorialAnswer" (true = jugar). Se espera a que su personaje
-- esté en el lobby; si no aparece en ~30 s o ya está volando, no se ofrece.
local tutorialOffered: { [Player]: true } = {}
PlayerStats.onLoaded(function(player: Player, stats: PlayerStats.Stats)
	if next(stats.Settings) ~= nil and player.Parent == Players then
		remote:FireClient(player, "Settings", stats.Settings) -- ajustes guardados (volumen, cámara, HUD)
	end
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
				Analytics.funnel(player, Analytics.STEPS.TutorialOffered)
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
local lastCallout: { [Player]: number } = {}
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
	if kind == "Settings" then
		PlayerStats.setSettings(player, value) -- se validan allí (claves conocidas, tipos y rangos)
		return
	end
	if kind == "TutorialAnswer" then
		-- Solo cuenta si se le ofreció: acepte o rechace, ya no se vuelve a ofrecer.
		if tutorialOffered[player] then
			tutorialOffered[player] = nil
			PlayerStats.markTutorialDone(player)
			Analytics.funnel(player, Analytics.STEPS.TutorialAnswered, { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = if value == true then "play" else "skip" } :: any)
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
	elseif kind == "Callout" then
		-- Aviso rápido al compañero ("Climb!", "Dive!"…): se reenvía a los dos del ala, con pausa mínima.
		local now = os.clock()
		local side = session:slotOf(player)
		if type(value) == "number" and Config.Callouts[value] and side and now - (lastCallout[player] or -math.huge) >= Config.CalloutCooldown then
			lastCallout[player] = now
			for _, rider in session:riders() do
				remote:FireClient(rider, "Callout", { side = side, id = value, userId = player.UserId })
			end
		end
	elseif kind == "SkipTutorial" then
		if tutorialRuns[session] then
			session:finish("lobby")
		end
	else
		session:handleMessage(player, kind, value)
	end
end)

-- ── Anillos de impulso y plumas ──────────────────────────────────────

local function pickupsOf(session: Session): Pickups
	local state = pickups[session]
	if not state then
		state = { level = 0, respawns = session.respawns, rings = {}, feathers = {}, counts = {}, total = 0 }
		pickups[session] = state
	end
	return state
end

-- Cada paso en vuelo: anillos cruzados (energía + empujón) y plumas a menos de FeatherRadius.
local function checkPickups(session: Session, course: Checkpoints.Course, level: number, previous: Vector3?, position: Vector3)
	local state = pickupsOf(session)
	if state.level ~= level or state.respawns ~= session.respawns then
		state.level, state.respawns = level, session.respawns
		table.clear(state.rings)
	end
	if previous then
		for _, index in course:ringsCrossed(level, previous, position) do
			if not state.rings[index] then
				state.rings[index] = true
				session:boostRing()
			end
		end
	end
	local taken = state.feathers[level]
	for _, feather in course:feathersOf(level) do
		if (taken == nil or not taken[feather.id]) and (feather.position - position).Magnitude <= Config.FeatherRadius then
			taken = taken or {}
			taken[feather.id] = true
			state.feathers[level] = taken
			state.counts[level] = (state.counts[level] or 0) + 1
			state.total += 1
			session.glider:SetAttribute("LevelFeathers", state.counts[level])
			for _, player in session:riders() do
				remote:FireClient(player, "Feather", { part = feather.part, count = state.counts[level], total = #course:feathersOf(level) })
			end
		end
	end
end

-- ── Puntos seguros ────────────────────────────────────────────────────

-- Tras unos segundos de vuelo limpio, la posición actual pasa a ser el punto de reaparición si está despejada:
-- una caja algo mayor que el ala (y larga hacia delante) no toca nada del mapa. Mira hacia la línea ideal.
local safeOverlap = OverlapParams.new()
safeOverlap.CollisionGroup = CollisionGroups.Probe
local function trySafePoint(session: Session, course: Checkpoints.Course)
	local position = session.root.Position
	local goal = course:lookahead(levelOf(session), position, 80)
	local forward = if goal then (goal - position) * Vector3.new(1, 0, 1) else Vector3.zero
	if forward.Magnitude < 1 then
		forward = GliderPhysics.forwardOf(session.physics.yaw)
	end
	local spawn = CFrame.lookAt(position, position + forward.Unit)
	local margin = Config.SafePointMargin
	local dims = session.dims
	local height = dims.wingTop + Config.FeetBelowRoot
	local box = spawn * CFrame.new(0, (dims.wingTop - Config.FeetBelowRoot) / 2, -40)
	local size = Vector3.new(dims.span + 2 * margin, height + 2 * margin, 80 + 2 * margin)
	if #workspace:GetPartBoundsInBox(box, size, safeOverlap) == 0 then
		session:setSafePoint(spawn)
	else
		session:deferSafePoint(1)
	end
end

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
		local level = levelOf(session)
		local position = session.root.Position
		-- Línea ideal por delante: la asistencia apunta aquí y la cámara la usa para anticipar las curvas.
		session.assistGoal = course:lookahead(level, position, Config.AssistLookahead)
		session.windField = course:windAt(level, position) -- corrientes del mapa (updraft, downdraft, lateral)
		if publishProgress then
			if not session.completed then
				session.glider:SetAttribute("LevelProgress", course:progress(level, position))
			end
			session.glider:SetAttribute("RouteAhead", course:lookahead(level, position, Config.CameraRouteLookahead))
		end
		if tutorialRuns[session] then
			-- Bot: pilota el rumbo hacia la línea ideal del tramo; la subida y bajada las decide el jugador.
			local flying = session.flight.state == "Flying"
			local progress = if flying then course:progress(level, position) else 0
			local balance = if flying
				then TutorialBot.steer(position, GliderPhysics.forwardOf(session.physics.yaw), course:lookahead(level, position, TutorialBot.LOOKAHEAD))
				else 0
			local hint = TutorialBot.step(session.slots, session.flight.state, tutorialCues[level] or {}, progress, balance)
			if session.glider:GetAttribute("TutorialHint") ~= hint then
				session.glider:SetAttribute("TutorialHint", hint)
			end
		end
		-- Checkpoints: tramo recorrido desde el paso anterior (solo en vuelo; tras reaparecer se empieza de cero).
		-- Ala perdida: pasa de volar a "Ended" sin haber cruzado la meta (aterrizar tras la meta no cuenta).
		local flying = session.flight.state == "Flying"
		if wasFlying[session] and session.flight.state == "Ended" and not session.completed and not devRuns[session] and not tutorialRuns[session] then
			for _, player in session:riders() do
				PlayerStats.crashed(player)
				Analytics.wingLost(player, levelOf(session))
			end
		end
		if flying then
			wasFlying[session] = true
		else
			wasFlying[session] = nil
		end
		-- Empieza una cuenta atrás (despegue o reaparición): el ala acaba de saltar de sitio, se pide cargar esa
		-- zona mientras cuenta.
		if session.flight.state == "Countdown" then
			if not inCountdown[session] then
				for _, player in session:riders() do
					LevelStreaming.prepare(player, session.safeCFrame.Position)
				end
			end
			inCountdown[session] = true
		else
			inCountdown[session] = nil
		end
		if flying then
			local previous = lastPosition[session]
			if not session.completed then
				checkPickups(session, course, level, previous, position)
			end
			local checkpoint = previous and course:crossed(previous, position, session.checkpoint)
			if checkpoint then
				reachCheckpoint(session, checkpoint)
			elseif session:wantsSafePoint() then
				trySafePoint(session, course)
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
	lastCallout[player] = nil
	Analytics.forget(player)
	tutorialOffered[player] = nil
end)
