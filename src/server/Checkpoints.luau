--!strict
-- Checkpoints del recorrido: las islas de descanso del mapa (Map.RestIslandNN.CheckpointZone) y la meta
-- (Map.FinishIsland: línea del arco de meta). Un ala alcanza un checkpoint cuando CRUZA el plano de su zona hacia
-- adelante (test de segmento: no se lo salta aunque el servidor vaya a tirones).
-- El índice de un checkpoint = número de niveles superados al llegar (RestIsland03 → 3, meta → total).
-- Cada recorrido (el principal en Map, el tutorial en Map.Tutorial) es un objeto Course: Checkpoints.new(root).

export type Checkpoint = {
	index: number,
	plane: CFrame, -- plano que hay que cruzar: -Z local = hacia adelante del recorrido
	half: Vector3, -- medio tamaño del plano (X ancho, Y alto)
	spawn: CFrame, -- dónde reaparece el ala: centro de la zona, mirando hacia adelante (horizontal)
	final: boolean, -- meta: el recorrido termina aquí
	info: { [string]: any }, -- lo que ve el cliente en la pantalla de checkpoint
}

local Checkpoints = {}
Checkpoints.__index = Checkpoints

-- Por nivel: línea ideal (Entry → Route → Exit) con distancias acumuladas, título y color del bioma (HUD).
type LevelInfo = { points: { Vector3 }, lengths: { number }, total: number, title: string, color: Color3? }

export type Course = typeof(setmetatable(
	{} :: {
		root: Instance?,
		list: { Checkpoint },
		levelCount: number,
		levels: { [number]: LevelInfo },
	},
	Checkpoints
))

local function levelTitle(map: Instance, index: number): string
	local level = map:FindFirstChild(string.format("Level%02d", index))
	local title = level and level:GetAttribute("Title")
	return if type(title) == "string" then title else ""
end

local function biomeOf(model: Instance?): (string?, Color3?)
	if not model then
		return nil, nil
	end
	local title, color = model:GetAttribute("BiomeTitle"), model:GetAttribute("BiomeColor")
	return if type(title) == "string" then title else nil, if typeof(color) == "Color3" then color else nil
end

local function flatSpawn(zone: BasePart): CFrame
	local look = zone.CFrame.LookVector * Vector3.new(1, 0, 1)
	local forward = if look.Magnitude > 1e-3 then look.Unit else Vector3.xAxis
	return CFrame.lookAt(zone.Position, zone.Position + forward)
end

-- Lee un recorrido (una vez, al arrancar el servidor). Sin recorrido no hay checkpoints: se reaparece en la salida.
function Checkpoints.new(map: Instance?): Course
	local list: { Checkpoint } = {}
	local levels: { [number]: LevelInfo } = {}
	local levelCount = 0
	local course = setmetatable({ root = map, list = list, levelCount = 0, levels = levels }, Checkpoints)
	if not map then
		return course
	end
	while map:FindFirstChild(string.format("Level%02d", levelCount + 1)) do
		levelCount += 1
	end
	for index = 1, levelCount do
		local level = map:FindFirstChild(string.format("Level%02d", index)) :: Instance
		local entry, exit, route = level:FindFirstChild("Entry"), level:FindFirstChild("Exit"), level:FindFirstChild("Route")
		local points = {}
		if entry and entry:IsA("BasePart") then
			table.insert(points, entry.Position)
		end
		if route then
			local markers = route:GetChildren()
			table.sort(markers, function(a, b)
				return a.Name < b.Name
			end)
			for _, marker in markers do
				if marker:IsA("BasePart") then
					table.insert(points, marker.Position)
				end
			end
		end
		if exit and exit:IsA("BasePart") then
			table.insert(points, exit.Position)
		end
		local lengths, total = { 0 }, 0
		for i = 2, #points do
			total += (points[i] - points[i - 1]).Magnitude
			lengths[i] = total
		end
		local _, color = biomeOf(level)
		levels[index] = { points = points, lengths = lengths, total = total, title = levelTitle(map, index), color = color }
	end

	local previousBiome = biomeOf(map:FindFirstChild("StartIsland"))
	for index = 1, levelCount do
		local final = index == levelCount
		local model = map:FindFirstChild(if final then "FinishIsland" else string.format("RestIsland%02d", index))
		if not model then
			continue
		end
		local zone = model:FindFirstChild("CheckpointZone")
		if not (zone and zone:IsA("BasePart")) then
			continue
		end
		-- Meta: el plano es la línea del arco de meta, pero con el ancho de todo el valle (pasar por fuera
		-- del arco también cuenta; si no, el dúo reaparecería en bucle antes de la meta).
		local line = if final then model:FindFirstChild("FinishLine") else nil
		local plane = if line and line:IsA("BasePart") then line.CFrame else zone.CFrame
		local biome, color = biomeOf(model)
		table.insert(list, {
			index = index,
			plane = plane,
			half = zone.Size / 2,
			spawn = flatSpawn(zone),
			final = final,
			info = {
				index = index,
				total = levelCount,
				title = levelTitle(map, index),
				nextTitle = if final then nil else levelTitle(map, index + 1),
				final = final,
				color = color,
				newBiome = if biome and biome ~= previousBiome then biome else nil, -- anuncia el cambio de bioma
			},
		})
		previousBiome = biome or previousBiome
	end
	course.levelCount = levelCount
	return course
end

function Checkpoints.count(self: Course): number
	return self.levelCount
end

-- Título y color del bioma de un nivel (para el HUD).
function Checkpoints.levelInfo(self: Course, index: number): (string, Color3?)
	local info = self.levels[index]
	if not info then
		return "", nil
	end
	return info.title, info.color
end

-- Fracción recorrida del nivel (0-1): proyección de la posición sobre su línea ideal, sin retroceder a
-- tramos lejanos (se toma el punto más cercano de toda la polilínea).
function Checkpoints.progress(self: Course, index: number, position: Vector3): number
	local info = self.levels[index]
	if not info or #info.points < 2 or info.total <= 0 then
		return 0
	end
	local best, bestDistance = 0, math.huge
	for i = 2, #info.points do
		local a, b = info.points[i - 1], info.points[i]
		local ab = b - a
		local t = math.clamp((position - a):Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
		local distance = (a + ab * t - position).Magnitude
		if distance < bestDistance then
			bestDistance = distance
			best = info.lengths[i - 1] + ab.Magnitude * t
		end
	end
	return math.clamp(best / info.total, 0, 1)
end

-- Primer checkpoint con índice > afterIndex cuyo plano se cruzó hacia adelante entre from y to.
function Checkpoints.crossed(self: Course, from: Vector3, to: Vector3, afterIndex: number): Checkpoint?
	for _, checkpoint in self.list do
		if checkpoint.index <= afterIndex then
			continue
		end
		local a = checkpoint.plane:PointToObjectSpace(from)
		local b = checkpoint.plane:PointToObjectSpace(to)
		if a.Z > 0 and b.Z <= 0 then
			local hit = a:Lerp(b, a.Z / (a.Z - b.Z))
			if math.abs(hit.X) <= checkpoint.half.X and math.abs(hit.Y) <= checkpoint.half.Y then
				return checkpoint
			end
		end
	end
	return nil
end

return Checkpoints
