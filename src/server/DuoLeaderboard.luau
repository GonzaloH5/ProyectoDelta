--!strict
-- Clasificación de DÚOS (OrderedDataStore) y su tablón en el lobby.
--
-- Cada pareja de jugadores guarda su mejor marca: llegar más lejos y, a igualdad, en menos tiempo:
--   puntuación = nivel superado × SCALE − centésimas del cronómetro (RunTime al cruzar ese checkpoint)
-- Mientras nadie termine el recorrido, el tablón muestra hasta dónde llegó cada dúo; en cuanto alguien
-- termina, manda el mejor tiempo del recorrido completo. Solo cuentan vuelos de dos jugadores desde la salida.
-- Clave: "<UserId menor>_<UserId mayor>": el mismo dúo cuenta igual vuelen en el orden que vuelen.
--
-- Tablón: una Part llamada "DuoLeaderboard" en cualquier lugar de Workspace (su cara Front muestra la tabla;
-- se coloca y escala a mano en Studio). Si no existe, se crea una detrás y a la izquierda de la plaza del lobby,
-- mirando al SpawnLocation. En Studio sin acceso a API Services no se guarda nada y el tablón sale vacío.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")

local Config = require(ReplicatedStorage:WaitForChild("Glider"):WaitForChild("GliderConfig"))

local DuoLeaderboard = {}

local STORE_NAME = "DuoBest_v1"
local SCALE = 10_000_000 -- centésimas máximas por nivel (~27 h): la puntuación cabe de sobra en un entero
local TOP = 10
local REFRESH_INTERVAL = 60 -- segundos entre lecturas del almacén (GetSortedAsync)
local RECENT_WINDOW = 150 -- una marca de este servidor se muestra aunque el almacén aún no la devuelva
local MAX_ATTEMPTS = 3
local BOARD_NAME = "DuoLeaderboard"
-- Tablón por defecto: desplazamiento respecto al SpawnLocation (X derecha, Z atrás; el spawn mira a la terraza).
local DEFAULT_OFFSET = Vector3.new(-46, 0, 27)
local DEFAULT_SIZE = Vector3.new(22, 14, 1)
local DEFAULT_LIFT = 4.5 -- studs entre el suelo y el borde inferior del panel

export type Entry = { key: string, score: number }
type Row = { frame: Frame, rank: TextLabel, names: TextLabel, level: TextLabel, time: TextLabel }

local store: OrderedDataStore? = nil
local entries: { Entry } = {}
local recent: { [string]: { score: number, at: number } } = {}
local names: { [number]: string } = {}
local levelCount = 0
local rows: { Row } = {}
local emptyLabel: TextLabel? = nil
local footerLabel: TextLabel? = nil

local function encode(level: number, runTime: number): number
	local centiseconds = math.clamp(math.floor(runTime * 100 + 0.5), 0, SCALE - 1)
	return level * SCALE - centiseconds
end

local function decode(score: number): (number, number)
	local level = math.ceil(score / SCALE)
	return level, (level * SCALE - score) / 100
end

local function keyOf(a: number, b: number): string
	return string.format("%d_%d", math.min(a, b), math.max(a, b))
end

local function idsOf(key: string): (number?, number?)
	local a, b = string.match(key, "^(%d+)_(%d+)$")
	return tonumber(a), tonumber(b)
end

local function formatTime(seconds: number): string
	local minutes = math.floor(seconds / 60)
	return string.format("%d:%05.2f", minutes, seconds - minutes * 60)
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
	warn(string.format("[DuoLeaderboard] %s falló: %s", label, tostring(lastError)))
	return false, nil
end

-- ── Nombres ───────────────────────────────────────────────────────────

local function rememberPlayer(player: Player)
	names[player.UserId] = player.DisplayName
end

-- Busca de una vez los nombres que falten (UserService admite lotes).
local function resolveNames(list: { Entry })
	local missing, seen = {}, {}
	for _, entry in list do
		for _, id in { idsOf(entry.key) } do
			if id and not names[id] and not seen[id] then
				seen[id] = true
				table.insert(missing, id)
			end
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok and type(infos) == "table" then
		for _, info in infos :: { any } do
			if type(info) == "table" and type(info.Id) == "number" then
				names[info.Id] = if type(info.DisplayName) == "string" and info.DisplayName ~= "" then info.DisplayName else tostring(info.Username)
			end
		end
	end
	for _, id in missing do
		if not names[id] then
			local found, name = pcall(function()
				return Players:GetNameFromUserIdAsync(id)
			end)
			names[id] = if found and type(name) == "string" then name else "Player"
		end
	end
end

local function duoName(key: string): string
	local a, b = idsOf(key)
	return string.format("%s & %s", a and names[a] or "…", b and names[b] or "…")
end

-- ── Tablón ────────────────────────────────────────────────────────────

local RANK_COLORS = { Color3.fromRGB(255, 205, 50), Color3.fromRGB(215, 225, 235), Color3.fromRGB(225, 145, 85) }
local PANEL = Color3.fromRGB(18, 22, 30)
local ACCENT = Color3.fromRGB(255, 110, 95)

local function label(parent: Instance, font: Enum.Font, size: number, color: Color3, align: Enum.TextXAlignment, position: UDim2, extent: UDim2): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Font = font
	text.TextSize = size
	text.TextColor3 = color
	text.TextXAlignment = align
	text.TextTruncate = Enum.TextTruncate.AtEnd
	text.Position = position
	text.Size = extent
	text.Text = ""
	text.Parent = parent
	return text
end

-- Suelo bajo un punto del lobby (rayo hacia abajo); si no encuentra nada razonable, la altura del spawn.
local function groundBelow(point: Vector3, spawn: BasePart, ignore: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local best: number? = nil
	for _, dx in { -DEFAULT_SIZE.X / 2, 0, DEFAULT_SIZE.X / 2 } do
		local origin = point + spawn.CFrame.RightVector * dx + Vector3.new(0, 40, 0)
		local hit = workspace:Raycast(origin, Vector3.new(0, -80, 0), params)
		if hit and math.abs(hit.Position.Y - spawn.Position.Y) < 12 then
			best = if best then math.min(best, hit.Position.Y) else hit.Position.Y
		end
	end
	return best or spawn.Position.Y - 0.3
end

-- Tablón por defecto: panel sobre dos postes, detrás y a la izquierda de la plaza, mirando al spawn.
local function createDefaultBoard(): BasePart?
	local lobby = workspace:FindFirstChild(Config.LobbyFolderName)
	local spawn = lobby and lobby:FindFirstChild("SpawnLocation", true)
	if not (spawn and spawn:IsA("BasePart")) then
		warn("[DuoLeaderboard] No hay Lobby con SpawnLocation: pon una Part llamada " .. BOARD_NAME .. " para ver el tablón")
		return nil
	end
	local model = Instance.new("Model")
	model.Name = BOARD_NAME .. "Board"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local base = (spawn.CFrame * CFrame.new(DEFAULT_OFFSET)).Position
	local ground = groundBelow(base, spawn, { model, spawn })
	local center = Vector3.new(base.X, ground + DEFAULT_LIFT + DEFAULT_SIZE.Y / 2, base.Z)
	local target = Vector3.new(spawn.Position.X, center.Y, spawn.Position.Z)
	local frame = CFrame.lookAt(center, target) -- Front (-Z) hacia el spawn

	local function piece(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.Size = size
		part.CFrame = cframe
		part.Color = color
		part.Material = material
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
		return part
	end
	local postHeight = DEFAULT_LIFT + DEFAULT_SIZE.Y + 1
	for _, side in { -1, 1 } do
		local x = side * (DEFAULT_SIZE.X / 2 - 1.5)
		piece("Post", Vector3.new(1.4, postHeight, 1.4), frame * CFrame.new(x, -DEFAULT_SIZE.Y / 2 - DEFAULT_LIFT + postHeight / 2, 1.2), Color3.fromRGB(110, 75, 52), Enum.Material.SmoothPlastic)
	end
	piece("Trim", Vector3.new(DEFAULT_SIZE.X + 1, 1, 1.6), frame * CFrame.new(0, DEFAULT_SIZE.Y / 2 + 0.5, 0), ACCENT, Enum.Material.Neon)
	local panel = piece(BOARD_NAME, DEFAULT_SIZE, frame, PANEL, Enum.Material.SmoothPlastic)
	model.Parent = workspace
	return panel
end

local function buildGui(part: BasePart)
	local old = part:FindFirstChild("DuoLeaderboardGui")
	if old then
		old:Destroy()
	end
	local width = 1100
	local height = math.floor(width * part.Size.Y / math.max(part.Size.X, 1))
	local gui = Instance.new("SurfaceGui")
	gui.Name = "DuoLeaderboardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(width, height)
	gui.LightInfluence = 0
	gui.MaxDistance = 300

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = PANEL
	background.BorderSizePixel = 0
	background.Parent = gui

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 118)
	header.BackgroundColor3 = ACCENT
	header.BorderSizePixel = 0
	header.Parent = background
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
	gradient.Rotation = 90
	gradient.Parent = header
	local title = label(header, Enum.Font.GothamBlack, 64, Color3.new(1, 1, 1), Enum.TextXAlignment.Center, UDim2.fromOffset(0, 8), UDim2.new(1, 0, 0, 68))
	title.Text = "TOP DUOS"
	local subtitle = label(header, Enum.Font.GothamBold, 24, Color3.fromRGB(255, 240, 235), Enum.TextXAlignment.Center, UDim2.fromOffset(0, 78), UDim2.new(1, 0, 0, 30))
	subtitle.Text = "FURTHEST LEVEL  ·  THEN FASTEST TIME"

	local columns: { { title: string, x: number, width: number } } = {
		{ title = "#", x = 20, width = 70 },
		{ title = "DUO", x = 100, width = 580 },
		{ title = "LEVEL", x = 690, width = 170 },
		{ title = "TIME", x = 870, width = 210 },
	}
	for _, column in columns do
		local text = label(background, Enum.Font.GothamBold, 22, Color3.fromRGB(150, 160, 178), Enum.TextXAlignment.Left, UDim2.fromOffset(column.x, 128), UDim2.fromOffset(column.width, 30))
		text.Text = column.title
	end

	table.clear(rows)
	local rowHeight = math.floor((height - 118 - 40 - 50) / TOP)
	for index = 1, TOP do
		local frame = Instance.new("Frame")
		frame.Position = UDim2.fromOffset(10, 160 + (index - 1) * rowHeight)
		frame.Size = UDim2.new(1, -20, 0, rowHeight - 4)
		frame.BackgroundColor3 = Color3.new(1, 1, 1)
		frame.BackgroundTransparency = if index % 2 == 1 then 0.93 else 0.97
		frame.BorderSizePixel = 0
		frame.Parent = background
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = frame
		local textSize = math.min(32, rowHeight - 14)
		local row = {
			frame = frame,
			rank = label(frame, Enum.Font.GothamBlack, textSize, Color3.new(1, 1, 1), Enum.TextXAlignment.Left, UDim2.fromOffset(10, 0), UDim2.new(0, 70, 1, 0)),
			names = label(frame, Enum.Font.GothamBold, textSize, Color3.new(1, 1, 1), Enum.TextXAlignment.Left, UDim2.fromOffset(90, 0), UDim2.new(0, 580, 1, 0)),
			level = label(frame, Enum.Font.GothamBold, textSize - 2, Color3.fromRGB(215, 222, 235), Enum.TextXAlignment.Left, UDim2.fromOffset(680, 0), UDim2.new(0, 170, 1, 0)),
			time = label(frame, Enum.Font.RobotoMono, textSize - 2, Color3.new(1, 1, 1), Enum.TextXAlignment.Left, UDim2.fromOffset(860, 0), UDim2.new(0, 210, 1, 0)),
		}
		table.insert(rows, row)
	end

	local empty = label(background, Enum.Font.GothamBold, 34, Color3.fromRGB(215, 222, 235), Enum.TextXAlignment.Center, UDim2.fromOffset(40, 200), UDim2.new(1, -80, 0, 200))
	empty.TextWrapped = true
	empty.TextTruncate = Enum.TextTruncate.None
	empty.Text = "No duo has flown yet.\nTeam up on a platform and set the first mark!"
	emptyLabel = empty
	local footer = label(background, Enum.Font.GothamMedium, 20, Color3.fromRGB(130, 140, 158), Enum.TextXAlignment.Center, UDim2.new(0, 0, 1, -44), UDim2.new(1, 0, 0, 36))
	footer.Text = "Updated every minute"
	footerLabel = footer
	gui.Parent = part
end

local function redraw()
	for index, row in rows do
		local entry = entries[index]
		row.frame.Visible = entry ~= nil
		if entry then
			local level, time = decode(entry.score)
			row.rank.Text = tostring(index)
			row.rank.TextColor3 = RANK_COLORS[index] or Color3.new(1, 1, 1)
			row.names.Text = duoName(entry.key)
			local finished = levelCount > 0 and level >= levelCount
			row.level.Text = if finished then "FINISHED" else string.format("LVL %d", level)
			row.level.TextColor3 = if finished then RANK_COLORS[1] else Color3.fromRGB(215, 222, 235)
			row.time.Text = formatTime(time)
		end
	end
	if emptyLabel then
		emptyLabel.Visible = #entries == 0
	end
	if footerLabel then
		footerLabel.Text = if store then "Updated every minute" else "Leaderboard offline (enable API Services to save)"
	end
end

-- ── Datos ─────────────────────────────────────────────────────────────

local function sortEntries(list: { Entry })
	table.sort(list, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.key < b.key
	end)
end

-- Añade las marcas recientes de este servidor que el almacén todavía no refleje.
local function mergeRecent(list: { Entry }): { Entry }
	local now = os.clock()
	local byKey: { [string]: Entry } = {}
	for _, entry in list do
		byKey[entry.key] = entry
	end
	for key, mark in recent do
		if now - mark.at > RECENT_WINDOW then
			recent[key] = nil
		elseif not byKey[key] then
			local entry = { key = key, score = mark.score }
			byKey[key] = entry
			table.insert(list, entry)
		elseif byKey[key].score < mark.score then
			byKey[key].score = mark.score
		end
	end
	sortEntries(list)
	while #list > TOP do
		table.remove(list)
	end
	return list
end

local function refresh()
	local fetched: { Entry } = {}
	local dataStore = store
	if dataStore then
		local ok, page = retry("leer la clasificación", function()
			return dataStore:GetSortedAsync(false, TOP):GetCurrentPage()
		end)
		if ok and type(page) == "table" then
			for _, item in page :: { any } do
				if type(item.key) == "string" and type(item.value) == "number" and item.value > 0 then
					table.insert(fetched, { key = item.key, score = item.value })
				end
			end
		else
			fetched = table.clone(entries) -- sin conexión: se conserva lo último que se vio
		end
	end
	local list = mergeRecent(fetched)
	resolveNames(list)
	entries = list
	redraw()
end

-- Posición (1..TOP) del dúo en el tablón, si está.
local function rankOf(key: string): number?
	for index, entry in entries do
		if entry.key == key then
			return index
		end
	end
	return nil
end

-- ── API ───────────────────────────────────────────────────────────────

-- total = niveles del recorrido (para marcar FINISHED).
function DuoLeaderboard.start(total: number)
	levelCount = total
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[DuoLeaderboard] OrderedDataStore no disponible, la clasificación no se guardará: " .. tostring(result))
	end
	for _, player in Players:GetPlayers() do
		rememberPlayer(player)
	end
	Players.PlayerAdded:Connect(rememberPlayer)

	local part = workspace:FindFirstChild(BOARD_NAME, true)
	local board = if part and part:IsA("BasePart") then part else createDefaultBoard()
	if board then
		buildGui(board)
	end
	task.spawn(function()
		while true do
			refresh()
			task.wait(REFRESH_INTERVAL)
		end
	end)
end

-- El dúo cruzó el checkpoint `level` con el cronómetro en `runTime` (vuelos desde la salida).
-- onResult(improved, rank): improved = nueva mejor marca del dúo; rank = puesto en el tablón (o nil).
-- Solo cuentan los vuelos de dos jugadores: en solitario (pruebas) responde enseguida sin guardar nada.
function DuoLeaderboard.submit(players: { Player }, level: number, runTime: number, onResult: ((boolean, number?) -> ())?)
	if #players ~= 2 or level < 1 then
		if onResult then
			onResult(false, nil)
		end
		return
	end
	for _, player in players do
		rememberPlayer(player)
	end
	local key = keyOf(players[1].UserId, players[2].UserId)
	local score = encode(level, runTime)
	task.spawn(function()
		local improved = false
		local dataStore = store
		if dataStore then
			local ok = retry("guardar " .. key, function()
				return dataStore:UpdateAsync(key, function(old: number?): number
					if type(old) == "number" and old >= score then
						improved = false
						return nil :: any -- nil = no escribe (no mejora)
					end
					improved = true
					return score
				end)
			end)
			if not ok then
				improved = false
			end
		else
			local mark = recent[key]
			improved = mark == nil or mark.score < score
		end
		if improved then
			recent[key] = { score = score, at = os.clock() }
			entries = mergeRecent(table.clone(entries))
			resolveNames(entries)
			redraw()
		end
		if onResult then
			onResult(improved, rankOf(key))
		end
	end)
end

DuoLeaderboard.encode = encode
DuoLeaderboard.decode = decode
DuoLeaderboard.formatTime = formatTime

return DuoLeaderboard
