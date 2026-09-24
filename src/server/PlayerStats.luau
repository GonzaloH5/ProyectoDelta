--!strict
-- Estadísticas guardadas de cada jugador (DataStore). Solo récords y contadores:
--   · HighestLevel  mayor nivel superado (checkpoint más alto alcanzado; el total = meta)
--   · BestTime      mejor tiempo del recorrido completo desde la salida (segundos; nil = aún no lo terminó)
--   · Completions   recorridos terminados · Runs  vuelos empezados · Crashes  choques
--   · TutorialDone  ya hizo (o saltó) el tutorial: no vuelve a empezar solo al entrar
-- NO se guarda por dónde iba: cada vuelo empieza siempre en la salida.
--
-- Guardado con fusión (UpdateAsync): los récords se combinan con max/min y los contadores suman lo pendiente.
-- Así nunca se pisa lo guardado aunque la carga haya fallado o el jugador esté en otro servidor a la vez.
-- En Studio sin "Enable Studio Access to API Services" no se guarda nada (aviso en la salida) y el juego sigue.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local PlayerStats = {}

local STORE_NAME = "PlayerStats_v1"
local AUTOSAVE_INTERVAL = 120 -- segundos entre guardados de quien tenga cambios pendientes
local MAX_ATTEMPTS = 3 -- intentos por lectura o escritura (espera 1, 2 s entre ellos)
local VERSION = 1

export type Stats = {
	HighestLevel: number,
	BestTime: number?,
	Completions: number,
	Runs: number,
	Crashes: number,
	TutorialDone: boolean,
}

-- Sumas aún no escritas en el DataStore.
type Pending = { Completions: number, Runs: number, Crashes: number }

type Entry = {
	stats: Stats, -- lo que se muestra: guardado + pendiente
	pending: Pending,
	dirty: boolean,
	loaded: boolean, -- la lectura terminó (bien o mal): ya se puede guardar
	leaderstats: Folder,
}

local store: DataStore? = nil
local entries: { [Player]: Entry } = {}
local busy = 0 -- guardados en marcha (BindToClose espera a que terminen)
local loadedListeners: { (Player, Stats) -> () } = {}

local function emptyPending(): Pending
	return { Completions = 0, Runs = 0, Crashes = 0 }
end

local function emptyStats(): Stats
	return { HighestLevel = 0, BestTime = nil, Completions = 0, Runs = 0, Crashes = 0, TutorialDone = false }
end

-- Datos guardados → Stats, descartando lo que no tenga el tipo esperado.
local function sanitize(raw: unknown): Stats
	local stats = emptyStats()
	if type(raw) ~= "table" then
		return stats
	end
	local data = raw :: { [string]: unknown }
	local function number(key: string): number?
		local value = data[key]
		if type(value) == "number" and value == value and value >= 0 and value < math.huge then
			return value
		end
		return nil
	end
	stats.HighestLevel = math.floor(number("HighestLevel") or 0)
	stats.BestTime = number("BestTime")
	stats.Completions = math.floor(number("Completions") or 0)
	stats.Runs = math.floor(number("Runs") or 0)
	stats.Crashes = math.floor(number("Crashes") or 0)
	stats.TutorialDone = data.TutorialDone == true
	return stats
end

local function formatTime(seconds: number?): string
	if not seconds then
		return "--:--"
	end
	local minutes = math.floor(seconds / 60)
	return string.format("%d:%05.2f", minutes, seconds - minutes * 60)
end

-- Refleja las estadísticas en leaderstats (lista de jugadores) y en atributos del Player (para la interfaz).
local function publish(player: Player, entry: Entry)
	local stats = entry.stats
	local folder = entry.leaderstats
	local level = folder:FindFirstChild("Level") :: IntValue?
	local best = folder:FindFirstChild("Best") :: StringValue?
	if level then
		level.Value = stats.HighestLevel
	end
	if best then
		best.Value = formatTime(stats.BestTime)
	end
	player:SetAttribute("HighestLevel", stats.HighestLevel)
	player:SetAttribute("BestTime", stats.BestTime)
	player:SetAttribute("Completions", stats.Completions)
	player:SetAttribute("Runs", stats.Runs)
	player:SetAttribute("Crashes", stats.Crashes)
end

local function createLeaderstats(player: Player): Folder
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Parent = folder
	local best = Instance.new("StringValue")
	best.Name = "Best"
	best.Value = formatTime(nil)
	best.Parent = folder
	folder.Parent = player
	return folder
end

local function retry<T>(label: string, action: () -> T): (boolean, T?)
	local lastError: unknown = nil
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(action)
		if ok then
			return true, result
		end
		lastError = result
		if attempt < MAX_ATTEMPTS then
			task.wait(attempt)
		end
	end
	warn(string.format("[PlayerStats] %s falló: %s", label, tostring(lastError)))
	return false, nil
end

local function keyOf(userId: number): string
	return "Player_" .. userId
end

local function load(player: Player, entry: Entry)
	local dataStore = store
	if dataStore then
		local ok, raw = retry("cargar " .. player.Name, function()
			return dataStore:GetAsync(keyOf(player.UserId))
		end)
		if ok and entries[player] == entry then
			-- Lo ocurrido mientras cargaba (pendiente y récords en memoria) se combina con lo guardado.
			local saved = sanitize(raw)
			local stats = entry.stats
			stats.HighestLevel = math.max(stats.HighestLevel, saved.HighestLevel)
			if saved.BestTime and (not stats.BestTime or saved.BestTime < stats.BestTime) then
				stats.BestTime = saved.BestTime
			end
			local pending = entry.pending
			stats.Completions = saved.Completions + pending.Completions
			stats.Runs = saved.Runs + pending.Runs
			stats.Crashes = saved.Crashes + pending.Crashes
			stats.TutorialDone = stats.TutorialDone or saved.TutorialDone
		end
	end
	entry.loaded = true
	if entries[player] == entry then
		publish(player, entry)
		for _, listener in loadedListeners do
			task.spawn(listener, player, table.clone(entry.stats))
		end
	end
end

-- Escribe lo pendiente de un jugador. Devuelve cuando termina (se puede llamar desde BindToClose).
local function save(player: Player, entry: Entry)
	local dataStore = store
	if not dataStore or not entry.loaded or not entry.dirty then
		return
	end
	local pending = entry.pending
	local highest = entry.stats.HighestLevel
	local bestTime = entry.stats.BestTime
	local tutorialDone = entry.stats.TutorialDone
	entry.pending = emptyPending()
	entry.dirty = false

	local ok = retry("guardar " .. player.Name, function()
		return dataStore:UpdateAsync(keyOf(player.UserId), function(raw: unknown)
			local saved = sanitize(raw)
			saved.HighestLevel = math.max(saved.HighestLevel, highest)
			if bestTime and (not saved.BestTime or bestTime < saved.BestTime) then
				saved.BestTime = bestTime
			end
			saved.Completions += pending.Completions
			saved.Runs += pending.Runs
			saved.Crashes += pending.Crashes
			saved.TutorialDone = saved.TutorialDone or tutorialDone
			local data = saved :: any
			data.Version = VERSION
			return data, { player.UserId } -- UserIds: para peticiones de borrado de datos (GDPR)
		end)
	end)
	if not ok then
		-- Se reintenta en el próximo guardado: lo pendiente vuelve a la cola.
		entry.pending.Completions += pending.Completions
		entry.pending.Runs += pending.Runs
		entry.pending.Crashes += pending.Crashes
		entry.dirty = true
	end
end

local function change(player: Player, apply: (stats: Stats, pending: Pending) -> ())
	local entry = entries[player]
	if not entry then
		return
	end
	apply(entry.stats, entry.pending)
	entry.dirty = true
	publish(player, entry)
end

-- ── API para el controlador ───────────────────────────────────────────

-- Empezó un vuelo desde la salida.
function PlayerStats.runStarted(player: Player)
	change(player, function(stats, pending)
		stats.Runs += 1
		pending.Runs += 1
	end)
end

-- Chocó (el ala reaparece en su checkpoint).
function PlayerStats.crashed(player: Player)
	change(player, function(stats, pending)
		stats.Crashes += 1
		pending.Crashes += 1
	end)
end

-- Superó el nivel `level` (cruzó el checkpoint de ese índice). Devuelve true si es récord nuevo.
function PlayerStats.levelCleared(player: Player, level: number): boolean
	local entry = entries[player]
	if not entry or level <= entry.stats.HighestLevel then
		return false
	end
	entry.stats.HighestLevel = level
	entry.dirty = true
	publish(player, entry)
	return true
end

-- Cruzó la meta con el recorrido completo. Devuelve true si es mejor tiempo nuevo.
function PlayerStats.courseCompleted(player: Player, runTime: number): boolean
	local entry = entries[player]
	if not entry then
		return false
	end
	local best = entry.stats.BestTime
	local record = runTime > 0 and (not best or runTime < best)
	change(player, function(stats, pending)
		stats.Completions += 1
		pending.Completions += 1
		if record then
			stats.BestTime = runTime
		end
	end)
	return record
end

-- Terminó o saltó el tutorial: no vuelve a empezar solo.
function PlayerStats.markTutorialDone(player: Player)
	local entry = entries[player]
	if not entry or entry.stats.TutorialDone then
		return
	end
	entry.stats.TutorialDone = true
	entry.dirty = true
end

-- Llama a listener(player, stats) cuando termina la lectura de cada jugador (también si falló: estadísticas
-- vacías). Los que ya habían cargado reciben la llamada enseguida.
function PlayerStats.onLoaded(listener: (Player, Stats) -> ())
	table.insert(loadedListeners, listener)
	for player, entry in entries do
		if entry.loaded then
			task.spawn(listener, player, table.clone(entry.stats))
		end
	end
end

function PlayerStats.get(player: Player): Stats?
	local entry = entries[player]
	return entry and table.clone(entry.stats)
end

-- ── Ciclo de vida ─────────────────────────────────────────────────────

local function onPlayerAdded(player: Player)
	if entries[player] then
		return
	end
	local entry: Entry = {
		stats = emptyStats(),
		pending = emptyPending(),
		dirty = false,
		loaded = false,
		leaderstats = createLeaderstats(player),
	}
	entries[player] = entry
	publish(player, entry)
	load(player, entry)
end

local function onPlayerRemoving(player: Player)
	local entry = entries[player]
	if not entry then
		return
	end
	entries[player] = nil
	busy += 1
	-- Si aún está cargando, se espera a que termine para no perder lo pendiente.
	while not entry.loaded do
		task.wait(0.5)
	end
	save(player, entry)
	busy -= 1
end

function PlayerStats.start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[PlayerStats] DataStore no disponible, las estadísticas no se guardarán: " .. tostring(result))
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player, entry in entries do
				task.spawn(save, player, entry)
			end
		end
	end)

	-- Al cerrar el servidor: guarda a todos en paralelo y espera (máx. ~30 s que da Roblox).
	-- Al cerrar el servidor: guarda a quien quede (en paralelo) y espera a todos los guardados en marcha,
	-- también los de PlayerRemoving (Roblox da ~30 s).
	game:BindToClose(function()
		for player in entries do
			task.spawn(onPlayerRemoving, player)
		end
		local deadline = os.clock() + 25
		while busy > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return PlayerStats
