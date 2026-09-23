--!nonstrict
-- LobbyBuilder v1 — LOBBY LOW-POLY DE COLORES VIVOS.
--
-- Uso (Studio, modo edición, barra de comandos):
--   require(game.ServerScriptService.Glider.DevTools.LobbyBuilder:Clone()).build()
-- Borra Workspace.Lobby y lo regenera. Como el mapa, no se edita a mano mientras sea blockout:
-- se ajustan los números de este archivo y se vuelve a generar.
--
-- Isla flotante a un costado del recorrido, mirando al valle inicial:
--   · Plaza central con el SpawnLocation y un molino de viento (hito visible desde lejos).
--   · Terraza de despegue: 4 DuoPad en semicírculo, cada una con su color, arco y mini ala delta.
--   · Senderos, árboles, rocas, arbustos, flores, farolillos y manga de viento.
--   · 3 islitas satélite unidas por puentes colgantes (una con cascada) y nubes alrededor.
-- Compatibilidad: Lobby.luau busca Parts llamadas Config.DuoPadName dentro de Workspace[Config.LobbyFolderName].
-- Un Lobby antiguo (sin atributo Generated) y los SpawnLocation sueltos en Workspace se guardan en
-- ServerStorage.DevReferencias.LobbyViejo en vez de borrarse.
--
-- Coordenadas locales de la isla: f = adelante (hacia el recorrido), u = derecha, y = arriba (0 = césped).
-- Ángulos φ: 0 = adelante, positivos giran a la DERECHA.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage.Glider.GliderConfig)
local LowPoly = require(game:GetService("ServerScriptService").Glider.DevTools.LowPoly:Clone())

local LobbyBuilder = {}

local VERSION = 1
-- Marco de DISEÑO: todas las medidas del archivo son relativas a él (a escala 1).
local CENTER = Vector3.new(0, 300, -950) -- centro de la isla, a la altura del césped
local LOOK_AT = Vector3.new(400, 300, 0) -- la terraza mira hacia el valle inicial del recorrido
local ORIGIN = CFrame.lookAt(CENTER, Vector3.new(LOOK_AT.X, CENTER.Y, LOOK_AT.Z))
-- Colocación FINAL (elegida a mano en Studio y medida con error 0): al terminar, el lobby entero se escala
-- SCALE veces alrededor de ORIGIN y ORIGIN pasa a estar en PLACEMENT.
local SCALE = 0.859233
local PLACEMENT = CFrame.new(-918.795288, 265.791351, -4.04612207) * CFrame.Angles(0, math.atan2(-0.999277115, 0.0380246639), 0)
-- Retoques hechos a mano que el constructor reproduce: spawn más grande (medidas de diseño, antes de SCALE)
-- y carpetas de Decor sustituidas por modelos propios sueltos en Workspace.
local SPAWN_SIZE = Vector3.new(22.46, 2.246, 22.46)
local DROP_DECOR = { "Trees", "Bushes", "Rocks/Rock" } -- "Carpeta" entera o "Carpeta/NombreDePieza"
local MAIN_R = 160 -- radio (a las esquinas) del hexágono de la isla principal
local PLAZA_F = -30 -- la plaza queda algo por detrás del centro: la terraza gana espacio
local PLAZA_R = 44
local PAD_RING = 110 -- distancia de las DuoPad al centro de la plaza
local PAD_SIZE = 14
local WINDMILL_F = -100

local COLORS = {
	Grass = Color3.fromRGB(110, 215, 90),
	Rock = Color3.fromRGB(150, 110, 90),
	RockDark = Color3.fromRGB(120, 90, 80),
	Stone = Color3.fromRGB(235, 225, 200), -- plaza
	StoneDark = Color3.fromRGB(212, 200, 172),
	Sand = Color3.fromRGB(245, 210, 150), -- caminos
	Sand2 = Color3.fromRGB(232, 193, 130),
	Wood = Color3.fromRGB(175, 118, 72),
	WoodDark = Color3.fromRGB(110, 75, 52),
	White = Color3.fromRGB(248, 245, 238),
	Roof = Color3.fromRGB(255, 110, 95),
	Trunk = Color3.fromRGB(135, 92, 62),
	Leaf = Color3.fromRGB(95, 200, 85),
	Bush = Color3.fromRGB(80, 185, 80),
	Pad = Color3.fromRGB(255, 255, 255), -- se pinta con el color del dúo
	PadRim = Color3.fromRGB(255, 255, 255),
	Accent = Color3.fromRGB(255, 255, 255),
	Chevron = Color3.fromRGB(255, 255, 255),
	Flower = Color3.fromRGB(255, 255, 255),
	Lamp = Color3.fromRGB(255, 205, 120),
	Water = Color3.fromRGB(80, 190, 255),
	Foam = Color3.fromRGB(230, 248, 255),
	Cloud = Color3.fromRGB(255, 255, 255),
}
local STYLE = {
	PadRim = { neon = true },
	Accent = { neon = true },
	Lamp = { neon = true },
	Water = { neon = true, transparency = 0.35, visual = true },
	Foam = { transparency = 0.3, visual = true },
	Cloud = { visual = true },
	Flower = { visual = true },
	Chevron = { visual = true },
}
local DUO_COLORS = {
	Color3.fromRGB(255, 110, 95), -- coral
	Color3.fromRGB(40, 210, 200), -- turquesa
	Color3.fromRGB(255, 205, 50), -- amarillo
	Color3.fromRGB(165, 120, 255), -- lila
}
local LEAVES = {
	Color3.fromRGB(95, 200, 85),
	Color3.fromRGB(60, 170, 80),
	Color3.fromRGB(145, 225, 80),
}
local BLOSSOMS = {
	Pink = Color3.fromRGB(255, 140, 190),
	Orange = Color3.fromRGB(255, 160, 70),
}
local FLOWERS = {
	Color3.fromRGB(255, 140, 190),
	Color3.fromRGB(255, 205, 50),
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(165, 120, 255),
	Color3.fromRGB(255, 110, 95),
}

local rng = Random.new(20260922) -- semilla fija: regenerar da siempre el mismo lobby

-- ── Primitivas (compartidas en LowPoly) ──────────────────────────────

local kit = LowPoly.kit({ colors = COLORS, style = STYLE, rng = rng })
local newPart, hex, gem = kit.part, kit.hex, kit.gem
local tint, newModel, newFolder, hexEdge = LowPoly.tint, LowPoly.model, LowPoly.folder, LowPoly.hexEdge

-- ── Geometría local ──────────────────────────────────────────────────

local function at(f: number, u: number, y: number): CFrame
	return ORIGIN * CFrame.new(u, y, -f)
end

-- Igual que at(), pero girado para mirar en la dirección φ (su -Z local apunta hacia φ).
local function facing(f: number, u: number, y: number, phi: number): CFrame
	return at(f, u, y) * CFrame.Angles(0, -phi, 0)
end

local function polar(f: number, u: number, r: number, phi: number): (number, number)
	return f + r * math.cos(phi), u + r * math.sin(phi)
end

local function angleTo(f0, u0, f1, u1): number
	return math.atan2(u1 - u0, f1 - f0)
end

-- ── Ocupación (para repartir la decoración sin pisar caminos ni plataformas) ─

local occupied = { circles = {}, segments = {} }

local function occupy(f, u, radius)
	table.insert(occupied.circles, { f = f, u = u, r = radius })
end

local function occupySegment(f0, u0, f1, u1, halfWidth)
	table.insert(occupied.segments, { f0 = f0, u0 = u0, f1 = f1, u1 = u1, w = halfWidth })
end

local function isFree(f, u, radius): boolean
	for _, c in occupied.circles do
		if (f - c.f) ^ 2 + (u - c.u) ^ 2 < (c.r + radius) ^ 2 then
			return false
		end
	end
	for _, s in occupied.segments do
		local df, du = s.f1 - s.f0, s.u1 - s.u0
		local t = math.clamp(((f - s.f0) * df + (u - s.u0) * du) / math.max(df * df + du * du, 1e-6), 0, 1)
		local pf, pu = s.f0 + df * t, s.u0 + du * t
		if (f - pf) ^ 2 + (u - pu) ^ 2 < (s.w + radius) ^ 2 then
			return false
		end
	end
	return true
end

-- Reparte count objetos dentro de un hexágono (centro f,u · radio R) dejando margin hasta el borde.
local function scatter(count: number, cf: number, cu: number, radius: number, margin: number, size: number, place: (number, number) -> ())
	local placed, tries = 0, 0
	while placed < count and tries < count * 40 do
		tries += 1
		local phi = rng:NextNumber(0, 2 * math.pi)
		local r = math.sqrt(rng:NextNumber()) * radius
		if r > hexEdge(radius, phi) - margin then
			continue
		end
		local f, u = polar(cf, cu, r, phi)
		if isFree(f, u, size) then
			place(f, u)
			occupy(f, u, size)
			placed += 1
		end
	end
end

-- ── Piezas de decoración (LowPoly en coordenadas del lobby) ──────────

local function floatingIsland(model: Model, f: number, u: number, top: number, radius: number)
	kit.floatingIsland(model, at(f, u, top), radius)
end

local function tree(parent: Instance, f: number, u: number, y: number, scale: number, color: Color3)
	kit.tree(parent, at(f, u, y), scale, color)
	occupy(f, u, 7 * scale)
end

local function rock(parent: Instance, f: number, u: number, y: number, size: number)
	kit.rock(parent, at(f, u, y), size)
end

local function bush(parent: Instance, f: number, u: number, y: number, size: number)
	kit.bush(parent, at(f, u, y), size, LEAVES)
end

local function flowers(parent: Instance, f: number, u: number, y: number)
	kit.flowers(parent, at(f, u, y), FLOWERS)
end

local function lantern(parent: Instance, f: number, u: number, y: number)
	kit.lantern(parent, at(f, u, y))
	occupy(f, u, 2)
end


-- Sendero de losetas color arena de (f0,u0) a (f1,u1).
local function path(parent: Instance, f0, u0, f1, u1, y)
	local phi = angleTo(f0, u0, f1, u1)
	local length = math.sqrt((f1 - f0) ^ 2 + (u1 - u0) ^ 2)
	local count = math.max(1, math.floor(length / 6))
	for i = 0, count - 1 do
		local tf, tu = polar(f0, u0, (i + 0.5) * length / count, phi)
		local jitter = rng:NextNumber(-0.6, 0.6)
		tf, tu = polar(tf, tu, jitter, phi + math.pi / 2)
		newPart(parent, "Tile", if i % 2 == 0 then "Sand" else "Sand2", Vector3.new(5.5, 0.4, 4.4), facing(tf, tu, y + 0.1, phi + rng:NextNumber(-0.12, 0.12)))
	end
	occupySegment(f0, u0, f1, u1, 4)
end

-- ── Secciones del lobby ──────────────────────────────────────────────

local function buildPlaza(lobby: Folder)
	local plaza = newModel(lobby, "Plaza")
	hex(plaza, "PlazaOuter", "StoneDark", PLAZA_R, 1, at(PLAZA_F, 0, -0.1))
	hex(plaza, "PlazaInner", "Stone", 30, 1, at(PLAZA_F, 0, 0.1) * CFrame.Angles(0, math.rad(30), 0))
	occupy(PLAZA_F, 0, PLAZA_R + 2)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Anchored = true
	spawn.Size = SPAWN_SIZE
	spawn.CFrame = facing(PLAZA_F, 0, 0.3, 0) -- los jugadores aparecen mirando a la terraza
	spawn.Color = DUO_COLORS[3]
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.AllowTeamChangeOnTouch = false
	spawn.Parent = plaza

	-- Farolillos en las esquinas de la plaza (las de delante quedan libres para los caminos).
	for _, deg in { 90, -90, 150, -150 } do
		local f, u = polar(PLAZA_F, 0, PLAZA_R - 6, math.rad(deg))
		lantern(plaza, f, u, 0.4)
	end

	-- Hito: molino de viento low-poly detrás de la plaza, aspas hacia la terraza.
	local mill = Instance.new("Model")
	mill.Name = "Landmark"
	local base = facing(WINDMILL_F, 0, 0, 0)
	local stack = {
		{ "Base", "Stone", 16, 0, 4 },
		{ "Tower", "White", 13, 4, 16 },
		{ "Band", "Roof", 13.6, 19.5, 2 },
		{ "Tower", "White", 11.2, 21.5, 14 },
		{ "Band", "Roof", 11.8, 35, 2 },
		{ "Tower", "White", 9.5, 37, 12 },
		{ "Roof", "Roof", 12, 49, 2 },
		{ "Roof", "Roof", 9, 51, 4 },
		{ "Roof", "Roof", 6, 55, 4 },
		{ "Roof", "Roof", 3, 59, 3 },
	}
	for _, s in stack do
		hex(mill, s[1], s[2], s[3], s[5], base * CFrame.new(0, s[4] + s[5] / 2, 0))
	end
	gem(mill, "Finial", "Accent", 2.5, base * CFrame.new(0, 63.5, 0), DUO_COLORS[3])
	newPart(mill, "Door", "WoodDark", Vector3.new(6, 9, 1.5), base * CFrame.new(0, 8.5, -11.3))
	for _, x in { -3.5, 3.5 } do
		tint(newPart(mill, "Window", "Lamp", Vector3.new(2.5, 3, 0.6), base * CFrame.new(x, 28, -9.7)), DUO_COLORS[3])
	end
	local hub = base * CFrame.new(0, 46, -10.2)
	newPart(mill, "Hub", "WoodDark", Vector3.new(3, 4, 4), hub * CFrame.Angles(0, math.pi / 2, 0), Enum.PartType.Cylinder)
	for k = 0, 3 do
		local blade = hub * CFrame.new(0, 0, -1.6) * CFrame.Angles(0, 0, math.rad(15 + 90 * k))
		newPart(mill, "Spar", "WoodDark", Vector3.new(1, 30, 0.8), blade * CFrame.new(0, 15, 0))
		-- Vela: cuña en el plano de las aspas (X de la cuña = normal, Z = a lo largo del aspa).
		local sail = blade * CFrame.new(3, 17, -0.2) * CFrame.fromMatrix(Vector3.zero, Vector3.zAxis, Vector3.xAxis)
		newPart(mill, "Sail", "White", Vector3.new(0.4, 5, 22), sail, "Wedge")
	end
	mill.Parent = plaza
	occupy(WINDMILL_F, 0, 20)
	return plaza
end

-- Clona la plantilla del ala a escala reducida, sin física: solo comunica "aquí se vuela".
local function miniGlider(parent: Instance, position: Vector3, direction: Vector3): Model?
	local template = workspace:FindFirstChild(Config.GliderName)
	if not (template and template:IsA("Model")) then
		return nil
	end
	local mini = template:Clone()
	mini.Name = "MiniGlider"
	for _, d in mini:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	mini:ScaleTo(0.6)
	-- La plantilla mira a +X del mundo (rumbo 0 del recorrido): se gira para mirar a "direction".
	local box = mini:GetBoundingBox()
	local relative = CFrame.new(box.Position):ToObjectSpace(mini:GetPivot())
	local frame = CFrame.fromMatrix(position, direction, Vector3.yAxis) * CFrame.Angles(0, 0, math.rad(8))
	mini:PivotTo(frame * relative)
	mini.Parent = parent
	return mini
end

local function buildTerrace(lobby: Folder)
	local terrace = newModel(lobby, "DuoTerrace")
	local pads, arches, minis = newFolder(terrace, "Pads"), newFolder(terrace, "Arches"), newFolder(terrace, "MiniGliders")
	local paths = lobby:FindFirstChild("Paths")
	local list = {}
	for index, deg in { -45, -15, 15, 45 } do
		local phi = math.rad(deg)
		local color = DUO_COLORS[index]
		local f, u = polar(PLAZA_F, 0, PAD_RING, phi)
		local frame = facing(f, u, 0, phi) -- -Z local = hacia fuera (hacia el recorrido)

		local station = Instance.new("Model")
		station.Name = string.format("Duo%d", index)
		hex(station, "Plinth", "Stone", 11, 1.2, frame * CFrame.new(0, 0.4, 0))
		tint(newPart(station, "Rim", "PadRim", Vector3.new(PAD_SIZE + 1.5, 0.6, PAD_SIZE + 1.5), frame * CFrame.new(0, 1.3, 0)), color)
		local pad = newPart(station, Config.DuoPadName, "Pad", Vector3.new(PAD_SIZE, 0.8, PAD_SIZE), frame * CFrame.new(0, 1.8, 0))
		pad.Color = color
		pad:SetAttribute("DuoIndex", index)
		-- Flechas en el césped hacia el recorrido.
		for k = 1, 2 do
			for _, side in { -1, 1 } do
				local chevron = frame * CFrame.new(side * 1.6, 0.15, -(PAD_SIZE / 2 + 2 + 5 * k)) * CFrame.Angles(0, side * math.rad(35), 0)
				tint(newPart(station, "Chevron", "Chevron", Vector3.new(1, 0.3, 5), chevron), color)
			end
		end
		station.Parent = pads

		-- Arco de "equipo" del mismo color, a caballo sobre la plataforma.
		local arch = Instance.new("Model")
		arch.Name = string.format("Arch%d", index)
		local halfSpan = PAD_SIZE / 2 + 2.6
		for _, side in { -1, 1 } do
			tint(newPart(arch, "Pillar", "Pad", Vector3.new(2.2, 20, 2.2), frame * CFrame.new(side * halfSpan, 11, 0)), color)
		end
		tint(newPart(arch, "Beam", "Pad", Vector3.new(2 * halfSpan + 2.2, 2.4, 2.6), frame * CFrame.new(0, 22.2, 0)), color)
		gem(arch, "Gem", "Accent", 3, frame * CFrame.new(0, 25, 0), color)
		arch.Parent = arches

		local glider = miniGlider(minis, (frame * CFrame.new(0, 33, 0)).Position, frame.LookVector)
		if glider then
			glider.Name = string.format("MiniGlider%d", index)
		end

		-- Camino de la plaza a la plataforma.
		local sf, su = polar(PLAZA_F, 0, PLAZA_R + 2, phi)
		local ef, eu = polar(PLAZA_F, 0, PAD_RING - PAD_SIZE / 2 - 3, phi)
		path(paths, sf, su, ef, eu, 0)
		occupy(f, u, 14)
		local cf, cu = polar(PLAZA_F, 0, PAD_RING + 17, phi)
		occupy(cf, cu, 8)
		table.insert(list, { index = index, pad = pad })
	end

	-- Farolillos entre los caminos de la terraza.
	for _, deg in { -30, 0, 30 } do
		local f, u = polar(PLAZA_F, 0, 75, math.rad(deg))
		lantern(terrace, f, u, 0)
	end
	return terrace, list
end

local function windsock(parent: Instance, f: number, u: number)
	local model = Instance.new("Model")
	model.Name = "Windsock"
	newPart(model, "Pole", "White", Vector3.new(1.2, 28, 1.2), at(f, u, 14))
	newPart(model, "Ring", "WoodDark", Vector3.new(3, 0.6, 3), at(f, u, 26.5))
	-- El viento sopla hacia el recorrido (adelante-derecha); la manga cae un poco.
	local sock = facing(f, u, 26, math.rad(30)) * CFrame.Angles(math.rad(-10), 0, 0)
	for k = 0, 3 do
		local size = 4.4 - 0.7 * k
		tint(newPart(model, "Sock", "Pad", Vector3.new(size, size, 3.4), sock * CFrame.new(0, 0, -(2 + 3.5 * k))), if k % 2 == 0 then Color3.fromRGB(235, 60, 50) else COLORS.White)
	end
	tint(newPart(model, "Tip", "Pad", Vector3.new(1.6, 1.6, 2.5), sock * CFrame.new(0, 0, -15.4), "Wedge"), Color3.fromRGB(235, 60, 50))
	model.Parent = parent
	occupy(f, u, 4)
end

local function bridge(parent: Instance, name: string, a: { number }, b: { number })
	local model = Instance.new("Model")
	model.Name = name
	local wa = at(a[1], a[2], a[3] + 0.3).Position
	local wb = at(b[1], b[2], b[3] + 0.3).Position
	local length = (wb - wa).Magnitude
	local count = math.ceil(length / 3)
	local sag = math.min(6, length * 0.08)
	local points = {}
	for i = 0, count do
		local t = i / count
		table.insert(points, wa:Lerp(wb, t) - Vector3.new(0, 4 * sag * t * (1 - t), 0))
	end
	local side = (wb - wa):Cross(Vector3.yAxis).Unit
	for i = 1, count do
		local p, q = points[i], points[i + 1]
		local plank = newPart(model, "Plank", "Wood", Vector3.new(9, 0.6, 2.6), CFrame.lookAt((p + q) / 2, q))
		if i % 2 == 0 then
			plank.Color = COLORS.Wood:Lerp(COLORS.WoodDark, 0.25)
		end
	end
	for _, s in { -1, 1 } do
		local offset = side * (4.6 * s) + Vector3.new(0, 3.2, 0)
		for i = 1, count, 2 do
			local p, q = points[i] + offset, points[math.min(i + 2, count + 1)] + offset
			newPart(model, "Rope", "WoodDark", Vector3.new(0.35, 0.35, (q - p).Magnitude + 0.3), CFrame.lookAt((p + q) / 2, q))
			if i > 1 then
				newPart(model, "Hanger", "WoodDark", Vector3.new(0.3, 3.2, 0.3), CFrame.new(points[i] + side * (4.6 * s) + Vector3.new(0, 1.6, 0)))
			end
		end
		for _, p in { points[1], points[count + 1] } do
			newPart(model, "Post", "WoodDark", Vector3.new(1.2, 5, 1.2), CFrame.new(p + side * (4.6 * s) + Vector3.new(0, 2, 0)))
		end
	end
	model.Parent = parent
end

-- Cascada falsa: charca + arroyo hacia el borde + cuñas de agua cayendo al vacío.
local function waterfall(parent: Instance, f: number, u: number, top: number, radius: number, phi: number)
	local model = Instance.new("Model")
	model.Name = "Waterfall"
	local edge = hexEdge(radius, phi)
	local pf, pu = polar(f, u, 10, phi)
	hex(model, "Pond", "Water", 10, 0.6, at(pf, pu, top + 0.05))
	for k = 0, 5 do
		local rf, ru = polar(pf, pu, 11, math.rad(60 * k + 30))
		if k ~= 0 and k ~= 5 then -- el hueco hacia el borde deja salir el arroyo
			rock(model, rf, ru, top, rng:NextNumber(3, 4.5))
		end
	end
	local streamStart, streamEnd = 17, edge + 1
	local sf, su = polar(f, u, (streamStart + streamEnd) / 2, phi)
	newPart(model, "Stream", "Water", Vector3.new(5, 0.5, streamEnd - streamStart), facing(sf, su, top + 0.05, phi))
	local lf, lu = polar(f, u, edge + 2, phi)
	newPart(model, "Lip", "Water", Vector3.new(5.5, 3, 4), facing(lf, lu, top - 1.3, phi), "Wedge")
	for k = 1, 7 do
		local ff, fu = polar(f, u, edge + 4.5 + 0.8 * k, phi)
		local piece = newPart(model, "Fall", "Water", Vector3.new(5 + 0.7 * k, 22, 1.5 + 0.2 * k), facing(ff, fu, top - 3 - 22 * (k - 0.5), phi) * CFrame.Angles(0, if k % 2 == 0 then math.pi else 0, 0), if k % 2 == 0 then "Wedge" else nil)
		piece.Transparency = 0.3 + 0.08 * k
	end
	for k = 1, 3 do
		local ff, fu = polar(f, u, edge + 3 + k, phi + rng:NextNumber(-0.06, 0.06))
		newPart(model, "Foam", "Foam", Vector3.one * rng:NextNumber(3, 4.5), at(ff, fu, top - 1 - k), Enum.PartType.Ball)
	end
	local mf, mu = polar(f, u, edge + 12, phi)
	for k = 1, 2 do
		local mist = newPart(model, "Mist", "Cloud", Vector3.one * (16 + 6 * k), at(mf, mu + (k - 1.5) * 10, top - 170 + k * 4), Enum.PartType.Ball)
		mist.Transparency = 0.25
	end
	model.Parent = parent
	occupy(pf, pu, 13)
	occupySegment(f, u, lf, lu, 4)
end

local SATELLITES = {
	{ name = "Cascada", f = -10, u = -250, top = -12, radius = 48 },
	{ name = "Mirador", f = 60, u = 240, top = 8, radius = 40 },
	{ name = "Huerto", f = -215, u = 150, top = -4, radius = 32 },
}

local function buildSatellites(lobby: Folder)
	local satellites = newModel(lobby, "Satellites")
	local bridges = newFolder(satellites, "Bridges")
	local paths = lobby:FindFirstChild("Paths")
	for _, sat in SATELLITES do
		local model = Instance.new("Model")
		model.Name = sat.name
		floatingIsland(model, sat.f, sat.u, sat.top, sat.radius)

		-- Puente desde el borde de la isla principal al borde de la satélite.
		local phi = angleTo(0, 0, sat.f, sat.u)
		local mf, mu = polar(0, 0, hexEdge(MAIN_R, phi) - 3, phi)
		local sf, su = polar(sat.f, sat.u, hexEdge(sat.radius, phi + math.pi) - 3, phi + math.pi)
		bridge(bridges, "Bridge" .. sat.name, { mf, mu, 0 }, { sf, su, sat.top })
		occupySegment(mf, mu, sf, su, 7)

		-- Caminos: plaza → cabeza del puente, y cabeza del puente → centro de la satélite.
		local toHead = angleTo(PLAZA_F, 0, mf, mu)
		local pf, pu = polar(PLAZA_F, 0, PLAZA_R + 2, toHead)
		local hf, hu = polar(0, 0, hexEdge(MAIN_R, phi) - 5, phi)
		path(paths, pf, pu, hf, hu, 0)
		local cf, cu = polar(sat.f, sat.u, 10, phi + math.pi)
		local bf, bu = polar(sat.f, sat.u, hexEdge(sat.radius, phi + math.pi) - 5, phi + math.pi)
		path(paths, bf, bu, cf, cu, sat.top)
		for _, s in { -1, 1 } do
			local lf, lu = polar(hf, hu, 7.5, phi + s * math.pi / 2)
			lf, lu = polar(lf, lu, -4, phi)
			lantern(satellites, lf, lu, 0)
			local rf, ru = polar(bf, bu, 7.5, phi + s * math.pi / 2)
			lantern(satellites, rf, ru, sat.top)
		end

		if sat.name == "Cascada" then
			waterfall(model, sat.f, sat.u, sat.top, sat.radius, math.rad(-120))
			tree(model, sat.f + 18, sat.u - 14, sat.top, 0.9, BLOSSOMS.Pink)
		elseif sat.name == "Mirador" then
			-- Banco mirando al recorrido.
			local bench = facing(sat.f + 18, sat.u, sat.top, 0)
			newPart(model, "BenchSeat", "Wood", Vector3.new(9, 0.8, 2.6), bench * CFrame.new(0, 2, 0))
			newPart(model, "BenchBack", "Wood", Vector3.new(9, 2.4, 0.6), bench * CFrame.new(0, 3.6, 1.1))
			for _, x in { -3.6, 3.6 } do
				newPart(model, "BenchLeg", "WoodDark", Vector3.new(0.8, 1.8, 2.2), bench * CFrame.new(x, 0.9, 0))
			end
			occupy(sat.f + 18, sat.u, 7)
			tree(model, sat.f - 12, sat.u + 16, sat.top, 1.1, LEAVES[1])
			tree(model, sat.f - 18, sat.u - 6, sat.top, 0.8, BLOSSOMS.Orange)
		else
			tree(model, sat.f, sat.u, sat.top, 1.5, BLOSSOMS.Pink)
		end
		local y = sat.top
		scatter(4, sat.f, sat.u, sat.radius, 6, 3, function(f, u)
			bush(model, f, u, y, rng:NextNumber(4, 7))
		end)
		scatter(5, sat.f, sat.u, sat.radius, 4, 2, function(f, u)
			flowers(model, f, u, y)
		end)
		scatter(2, sat.f, sat.u, sat.radius, 6, 3, function(f, u)
			rock(model, f, u, y, rng:NextNumber(4, 7))
		end)
		model.Parent = satellites
	end
	return satellites
end

local function buildDecor(lobby: Folder)
	local decor = newModel(lobby, "Decor")
	local trees, rocks, bushes, flowerBeds = newFolder(decor, "Trees"), newFolder(decor, "Rocks"), newFolder(decor, "Bushes"), newFolder(decor, "Flowers")
	local TREES = {
		{ -80, -70, 1.2, LEAVES[1] },
		{ -118, -45, 1.0, LEAVES[2] },
		{ -40, -100, 1.1, BLOSSOMS.Pink },
		{ 30, -112, 0.9, LEAVES[3] },
		{ 110, -70, 0.8, BLOSSOMS.Orange },
		{ -70, 100, 1.2, LEAVES[2] },
		{ -125, 25, 0.9, LEAVES[1] },
		{ -10, 122, 1.0, LEAVES[3] },
		{ 60, 110, 0.9, BLOSSOMS.Pink },
		{ 110, 70, 0.8, BLOSSOMS.Orange },
	}
	for _, t in TREES do
		tree(trees, t[1], t[2], 0, t[3], t[4])
	end
	windsock(decor, 95, -100)
	scatter(10, 0, 0, MAIN_R, 10, 4, function(f, u)
		rock(rocks, f, u, 0, rng:NextNumber(4, 9))
	end)
	scatter(16, 0, 0, MAIN_R, 8, 3, function(f, u)
		bush(bushes, f, u, 0, rng:NextNumber(4, 8))
	end)
	scatter(22, 0, 0, MAIN_R, 5, 2, function(f, u)
		flowers(flowerBeds, f, u, 0)
	end)
	-- Rocas flotantes sueltas alrededor (profundidad).
	for _, r in { { -150, 230, 20, 12 }, { -40, 260, -30, 16 }, { 40, 300, -50, 10 }, { 115, 220, -40, 14 }, { -120, 330, 10, 9 } } do
		local f, u = polar(0, 0, r[2], math.rad(r[1]))
		gem(rocks, "FloatingRock", "Rock", r[4], at(f, u, r[3]))
		newPart(rocks, "FloatingGrass", "Grass", Vector3.new(r[4] * 0.9, 1.5, r[4] * 0.9), at(f, u, r[3] + r[4] * 0.62) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0))
	end
	return decor
end

local function buildClouds(lobby: Folder)
	local clouds = newModel(lobby, "Clouds")
	local function cloud(f, u, y, scale)
		kit.cloud(clouds, at(f, u, y), scale)
	end
	for _ = 1, 14 do
		local phi = rng:NextNumber(-math.pi, math.pi)
		local f, u = polar(0, 0, rng:NextNumber(270, 460), phi)
		-- Delante solo por debajo: no tapan la vista del recorrido.
		local y = if math.abs(phi) < math.rad(55) then rng:NextNumber(-170, -70) else rng:NextNumber(-150, 50)
		cloud(f, u, y, 1)
	end
	for k = 1, 3 do
		local f, u = polar(0, 0, rng:NextNumber(40, 120), math.rad(120 * k))
		cloud(f, u, rng:NextNumber(-230, -200), 1.4)
	end
	return clouds
end

-- ── Iluminación (global, idempotente) ────────────────────────────────

local function applyLighting()
	local correction = Lighting:FindFirstChild("LobbyVibrance") or Instance.new("ColorCorrectionEffect")
	correction.Name = "LobbyVibrance"
	correction.Saturation = 0.15
	correction.Contrast = 0.05
	correction.Parent = Lighting
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = 0.2
	end
end

local function countParts(root: Instance): number
	local parts = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	return parts
end

-- Nunca borra trabajo a mano. El Lobby actual solo se destruye si sigue EXACTAMENTE como se generó
-- (mismo número de piezas que marca GeneratedParts). Si se editó a mano (o es de antes de esta marca),
-- build() se niega salvo con force = true, y aun así lo guarda en ServerStorage.DevReferencias.LobbyViejo.
-- Los SpawnLocation sueltos en Workspace también se guardan ahí. Los modelos sueltos (decoración propia)
-- no se tocan nunca.
local function archiveLegacy(force: boolean): (number?, string?)
	local references = ServerStorage:FindFirstChild("DevReferencias") or newFolder(ServerStorage, "DevReferencias")
	local archive = references:FindFirstChild("LobbyViejo") or newFolder(references, "LobbyViejo")
	local archived = 0
	local old = workspace:FindFirstChild(Config.LobbyFolderName)
	if old then
		local parts = countParts(old)
		local untouched = old:GetAttribute("GeneratedParts") == parts
		if untouched then
			old:Destroy()
		elseif not force then
			return nil, string.format(
				"Workspace.%s se editó a mano (%d piezas; generado: %s). No se regenera para no perder esos cambios.\n"
					.. "build({ force = true }) lo reemplaza y guarda el actual en ServerStorage.DevReferencias.LobbyViejo.",
				Config.LobbyFolderName,
				parts,
				tostring(old:GetAttribute("GeneratedParts") or "sin marca")
			)
		else
			old.Name = string.format("%s_%s", Config.LobbyFolderName, os.date("%Y%m%d_%H%M%S"))
			old.Parent = archive
			archived += 1
		end
	end
	for _, child in workspace:GetChildren() do
		if child:IsA("SpawnLocation") then
			child.Enabled = false
			child.Parent = archive
			archived += 1
		end
	end
	return archived, nil
end

function LobbyBuilder.build(options): string
	table.clear(occupied.circles)
	table.clear(occupied.segments)
	local archived, refusal = archiveLegacy(options ~= nil and options.force == true)
	if refusal then
		return refusal
	end

	local lobby = Instance.new("Folder")
	lobby.Name = Config.LobbyFolderName
	lobby:SetAttribute("Generated", true)
	lobby:SetAttribute("Version", VERSION)

	local island = newModel(lobby, "Island")
	floatingIsland(island, 0, 0, 0, MAIN_R)
	newModel(lobby, "Paths")
	buildPlaza(lobby)
	local _, pads = buildTerrace(lobby)
	buildSatellites(lobby)
	buildDecor(lobby)
	buildClouds(lobby)
	applyLighting()
	-- Decoración que se sustituyó por modelos propios (sueltos en Workspace): se genera igual para no
	-- alterar la secuencia aleatoria del resto, y se quita al final.
	for _, entry in DROP_DECOR do
		local folderName, pieceName = entry:match("^([^/]+)/?(.*)$")
		local folder = lobby.Decor:FindFirstChild(folderName)
		if folder and pieceName == "" then
			folder:Destroy()
		elseif folder then
			for _, piece in folder:GetChildren() do
				if piece.Name == pieceName then
					piece:Destroy()
				end
			end
		end
	end

	-- Colocación final: escalar alrededor de ORIGIN y llevar ORIGIN a PLACEMENT (con un Model temporal,
	-- porque una Folder no se puede escalar ni mover de golpe).
	local wrapper = Instance.new("Model")
	for _, child in lobby:GetChildren() do
		child.Parent = wrapper
	end
	wrapper.WorldPivot = ORIGIN
	wrapper:ScaleTo(SCALE)
	wrapper:PivotTo(PLACEMENT)
	for _, child in wrapper:GetChildren() do
		child.Parent = lobby
	end
	wrapper:Destroy()
	local parts = countParts(lobby)
	lobby:SetAttribute("GeneratedParts", parts) -- si cambia, es que alguien lo editó a mano (ver archiveLegacy)
	lobby.Parent = workspace
	local summary = { string.format("Lobby v%d · %d piezas · centro %s · escala %.3f · %d elementos antiguos → ServerStorage.DevReferencias.LobbyViejo", VERSION, parts, tostring(PLACEMENT.Position), SCALE, archived) }
	for _, entry in pads do
		local p = entry.pad.Position
		table.insert(summary, string.format("DuoPad %d  (%.0f, %.1f, %.0f)", entry.index, p.X, p.Y + entry.pad.Size.Y / 2, p.Z))
	end
	local spawn = lobby:FindFirstChild("SpawnLocation", true)
	table.insert(summary, string.format("Spawn    (%.0f, %.1f, %.0f)", spawn.Position.X, spawn.Position.Y + 0.5, spawn.Position.Z))
	if not workspace:FindFirstChild(Config.GliderName) then
		table.insert(summary, "Aviso: no hay Workspace." .. Config.GliderName .. ": se omitieron las mini alas")
	end
	return table.concat(summary, "\n")
end

return LobbyBuilder
