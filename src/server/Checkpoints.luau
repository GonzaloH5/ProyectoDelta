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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GliderPhysics = require(ReplicatedStorage:WaitForChild("Glider"):WaitForChild("GliderPhysics"))

local Checkpoints = {}
Checkpoints.__index = Checkpoints

local LEVELS_PER_CHAPTER = 5 -- MapBuilder: 10 capítulos de 5 niveles, un bioma cada uno

-- Por nivel: línea ideal (Entry → Route → Exit) con distancias acumuladas, título y color del bioma (HUD).
export type Ring = { plane: CFrame, half: Vector3, radius: number? }
export type Feather = { id: number, position: Vector3, part: BasePart }
type Path = { Vector3 }
type LevelInfo = {
	points: { Vector3 },
	alternates: { Path }, -- líneas de los otros carriles de las bifurcaciones (RouteB): la asistencia sigue la más cercana
	lengths: { number },
	total: number,
	title: string,
	tagline: string?, -- frase de identidad del nivel (tarjeta de título)
	intro: string?, -- aviso de algo nuevo al empezar el nivel (p. ej. el impulso)
	color: Color3?,
	biome: string?,
	wind: { GliderPhysics.WindZone },
	rings: { Ring },
	feathers: { Feather },
}

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
		local entry, exit = level:FindFirstChild("Entry"), level:FindFirstChild("Exit")
		-- Línea ideal Entry → marcadores de la ruta → Exit.
		local function pathOf(route: Instance?): Path
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
			return points
		end
		local points = pathOf(level:FindFirstChild("Route"))
		local alternates = {}
		local routeB = level:FindFirstChild("RouteB")
		if routeB then
			table.insert(alternates, pathOf(routeB))
		end
		local lengths, total = { 0 }, 0
		for i = 2, #points do
			total += (points[i] - points[i - 1]).Magnitude
			lengths[i] = total
		end
		local _, color = biomeOf(level)
		local biome = level:GetAttribute("Biome")
		local tagline, intro = level:GetAttribute("Tagline"), level:GetAttribute("Intro")
		levels[index] = { points = points, lengths = lengths, total = total, alternates = alternates, title = levelTitle(map, index), tagline = if type(tagline) == "string" then tagline else nil, intro = if type(intro) == "string" then intro else nil, color = color, biome = if type(biome) == "string" then biome else nil, wind = GliderPhysics.windZones(level), rings = {}, feathers = {} }
		local ringFolder = level:FindFirstChild("Rings")
		if ringFolder then
			for _, plane in ringFolder:GetChildren() do
				if plane:IsA("BasePart") then
					local radius = plane:GetAttribute("Radius")
					table.insert(levels[index].rings, { plane = plane.CFrame, half = plane.Size / 2, radius = if type(radius) == "number" then radius else nil })
				end
			end
		end
		local featherFolder = level:FindFirstChild("Feathers")
		if featherFolder then
			for _, gem in featherFolder:GetChildren() do
				local id = gem:GetAttribute("FeatherId")
				if gem:IsA("BasePart") and type(id) == "number" then
					table.insert(levels[index].feathers, { id = id, position = gem.Position, part = gem })
				end
			end
		end
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
				-- Último nivel de un capítulo: "CHAPTER N CLEAR!" con el nombre de su bioma.
				chapter = if index % LEVELS_PER_CHAPTER == 0 and levelCount >= LEVELS_PER_CHAPTER then index // LEVELS_PER_CHAPTER else nil,
				chapterTitle = biomeOf(map:FindFirstChild(string.format("Level%02d", index))),
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

-- Frase de identidad y aviso de novedad de un nivel (para el HUD).
function Checkpoints.levelText(self: Course, index: number): (string?, string?)
	local info = self.levels[index]
	if not info then
		return nil, nil
	end
	return info.tagline, info.intro
end

local RING_TOLERANCE = 3 -- studs de más alrededor del aro que siguen contando como "pasar por dentro"

-- Cruce de un plano (-Z local = hacia adelante) entre from y to: dentro del círculo de `radius` (anillos
-- redondos) o, sin radio, dentro de su rectángulo.
local function crossesPlane(plane: CFrame, half: Vector3, from: Vector3, to: Vector3, radius: number?): boolean
	local a = plane:PointToObjectSpace(from)
	local b = plane:PointToObjectSpace(to)
	if a.Z > 0 and b.Z <= 0 then
		local hit = a:Lerp(b, a.Z / (a.Z - b.Z))
		if radius then
			return math.sqrt(hit.X * hit.X + hit.Y * hit.Y) <= radius + RING_TOLERANCE
		end
		return math.abs(hit.X) <= half.X and math.abs(hit.Y) <= half.Y
	end
	return false
end

-- Anillos de impulso del nivel `index` cruzados entre from y to (índices en la lista del nivel).
function Checkpoints.ringsCrossed(self: Course, index: number, from: Vector3, to: Vector3): { number }
	local crossed = {}
	local info = self.levels[index]
	if info then
		for i, ring in info.rings do
			if crossesPlane(ring.plane, ring.half, from, to, ring.radius) then
				table.insert(crossed, i)
			end
		end
	end
	return crossed
end

-- Plumas del nivel `index` (id, posición y pieza).
function Checkpoints.feathersOf(self: Course, index: number): { Feather }
	local info = self.levels[index]
	return if info then info.feathers else {}
end

-- Corriente del mapa en `position` (zonas del nivel `index`; Vector3.zero fuera de ellas).
function Checkpoints.windAt(self: Course, index: number, position: Vector3): Vector3
	local info = self.levels[index]
	return if info then GliderPhysics.windAt(info.wind, position) else Vector3.zero
end

-- Bioma del nivel (atributo Biome del modelo: la iluminación del cliente cambia con él).
function Checkpoints.biomeOf(self: Course, index: number): string?
	local info = self.levels[index]
	return info and info.biome
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

-- Punto de la línea ideal del nivel `distance` studs por delante de la proyección de `position` (para el
-- piloto del bot del tutorial). Pasado el final, sigue en la dirección del último tramo. nil sin línea.
-- Tramo más cercano de una línea: índice del final del tramo, punto proyectado y distancia.
local function closest(points: Path, position: Vector3): (number, Vector3, number)
	local segment, cursor, bestDistance = 2, points[1], math.huge
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local ab = b - a
		local t = math.clamp((position - a):Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
		local projected = a + ab * t
		local d = (projected - position).Magnitude
		if d < bestDistance then
			bestDistance, segment, cursor = d, i, projected
		end
	end
	return segment, cursor, bestDistance
end

function Checkpoints.lookahead(self: Course, index: number, position: Vector3, distance: number): Vector3?
	local info = self.levels[index]
	if not info or #info.points < 2 then
		return nil
	end
	-- En una bifurcación se sigue el carril por el que va el ala (la línea más cercana).
	local points = info.points
	local segment, cursor, bestDistance = closest(points, position)
	for _, alternate in info.alternates do
		if #alternate >= 2 then
			local altSegment, altCursor, altDistance = closest(alternate, position)
			if altDistance < bestDistance then
				points, segment, cursor, bestDistance = alternate, altSegment, altCursor, altDistance
			end
		end
	end
	-- Ya pasada la salida (en el valle): el objetivo sigue delante del ala, en la dirección del último tramo.
	local lastDir = points[#points] - points[#points - 1]
	lastDir = if lastDir.Magnitude > 1e-6 then lastDir.Unit else Vector3.xAxis
	local beyond = (position - points[#points]):Dot(lastDir)
	if segment == #points and beyond > 0 then
		return points[#points] + lastDir * (beyond + distance)
	end
	local remaining = distance
	for i = segment, #points do
		local step = (points[i] - cursor).Magnitude
		if step >= remaining then
			return cursor:Lerp(points[i], remaining / math.max(step, 1e-6))
		end
		remaining -= step
		cursor = points[i]
	end
	return cursor + lastDir * remaining
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
