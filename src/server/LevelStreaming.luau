--!strict
-- Ventana de niveles cargados por jugador (StreamingEnabled + modelos PersistentPerPlayer del mapa).
-- Mientras un jugador vuela con checkpoint c (niveles superados), se le fijan:
--   · la isla donde está o de la que salió (StartIsland si c = 0, si no RestIsland c)
--   · los niveles c+1 … c+AHEAD y las islas entre ellos (en el nivel 3 se carga hasta el 6), y la meta si entra
-- Lo demás deja de estar fijado: lo ya superado no vuelve a verse y el streaming lo descarga, y lo muy lejano
-- no llega. La colisión es del servidor (lo tiene todo), así que esto solo afecta a lo que dibuja cada cliente.

local LevelStreaming = {}

local AHEAD = 4 -- niveles fijados por delante, contando el actual

local levels: { [number]: Model } = {}
local islands: { [number]: Model } = {} -- 0 = StartIsland, n = RestIsland n, count = FinishIsland
local levelCount = 0
local pinned: { [Player]: { [Model]: true } } = {}

local function modelOf(parent: Instance, name: string): Model?
	local model = parent:FindFirstChild(name)
	if model and model:IsA("Model") and model.ModelStreamingMode == Enum.ModelStreamingMode.PersistentPerPlayer then
		return model
	end
	return nil
end

function LevelStreaming.load(map: Instance?)
	table.clear(levels)
	table.clear(islands)
	levelCount = 0
	if not map then
		return
	end
	while map:FindFirstChild(string.format("Level%02d", levelCount + 1)) do
		levelCount += 1
		levels[levelCount] = modelOf(map, string.format("Level%02d", levelCount)) :: Model
	end
	islands[0] = modelOf(map, "StartIsland") :: Model
	for index = 1, levelCount - 1 do
		islands[index] = modelOf(map, string.format("RestIsland%02d", index)) :: Model
	end
	islands[levelCount] = modelOf(map, "FinishIsland") :: Model
end

local function apply(player: Player, wanted: { [Model]: true })
	local current = pinned[player] or {}
	for model in current do
		if not wanted[model] and model.Parent then
			pcall(model.RemovePersistentPlayer, model, player)
		end
	end
	for model in wanted do
		if not current[model] then
			pcall(model.AddPersistentPlayer, model, player)
		end
	end
	pinned[player] = wanted
end

-- Fija la ventana del jugador según sus niveles superados (checkpoint).
function LevelStreaming.setWindow(player: Player, checkpoint: number)
	local wanted: { [Model]: true } = {}
	local island = islands[checkpoint]
	if island then
		wanted[island] = true
	end
	for index = checkpoint + 1, math.min(checkpoint + AHEAD, levelCount) do
		local level = levels[index]
		if level then
			wanted[level] = true
		end
		local after = islands[index]
		if after then
			wanted[after] = true
		end
	end
	apply(player, wanted)
end

-- Deja de fijar todo (vuelve al lobby o se va del juego).
function LevelStreaming.clear(player: Player)
	apply(player, {})
	pinned[player] = nil
end

-- Para comprobar: nombres de los modelos fijados a un jugador.
function LevelStreaming.pinnedNames(player: Player): { string }
	local names = {}
	for model in pinned[player] or {} do
		table.insert(names, model.Name)
	end
	table.sort(names)
	return names
end

return LevelStreaming
