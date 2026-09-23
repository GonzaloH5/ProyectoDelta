--!nonstrict
-- MapBuilder v2 — CORREDORES DE VUELO GUIADOS.
--
-- Uso (Studio, modo edición, barra de comandos):
--   require(game.ServerScriptService.Glider.DevTools.MapBuilder:Clone()).build()
-- Borra Workspace.Map y lo regenera. El mapa no se edita a mano mientras sea blockout:
-- se ajustan los números de este archivo y se vuelve a generar.
--
-- Filosofía: cada nivel = corredor contenido (paredes laterales + suelo + techo) + UNA idea de juego.
--   · El trazado del corredor se escribe como órdenes de "tortuga": recto, curva, subir/bajar, estrechar.
--   · Paredes y suelo son mortales (como en el juego), el techo se roza sin chocar (limita la altura).
--   · Obstáculos DENTRO del corredor, nunca ventanas: lomas (subir), vigas colgadas (bajar),
--     salientes de pared (apartarse). Anillos amarillos = guía visual, se atraviesan.
--   · Entre niveles: valle abierto con isla de descanso; cada corredor empieza en la boca de un acantilado.
--
-- Escala del ala (GliderConfig actual): avance 60 studs/s · radio de giro mínimo ~51, medio ~82 ·
-- subida máx 26 studs/s (23°) · caída máx 30 (27°) · envergadura 32, alto ~10 con los jugadores.
-- Rumbo: 0 = +X; ángulos positivos giran a la IZQUIERDA (-Z). "u" = lateral (+ derecha), "v" = vertical.
--
-- Vestido visual: tras generar cada nivel/valle, MapDresser lo "viste" con el bioma de su capítulo (Biomes).
-- .build({ dress = false }) genera el blockout puro (para depurar la jugabilidad). DRESS_LEVELS limita
-- hasta qué nivel se viste mientras el pase visual está a medias.

local DevTools = game:GetService("ServerScriptService").Glider.DevTools
local Biomes = require(DevTools.Biomes:Clone())
local MapDresser = require(DevTools.MapDresser:Clone())

local MapBuilder = {}

local DRESS_LEVELS = 10 -- se visten los niveles hasta este (y sus valles); más allá queda el blockout

local CRUISE = 400 -- altitud del despegue
local START = Vector3.new(100, CRUISE, 0) -- comienzo del valle inicial (fondo de la StartIsland)
local LAUNCH_S = 300 -- el despegue está a esta distancia del comienzo del valle inicial
local VALLEY = { length = 600, width = 700, floorDepth = 320, wallTop = 420 } -- pausas entre corredores
local WALL_T = 24 -- grosor de paredes
local SLAB_T = 8 -- grosor de suelo y techo
local RIM = 60 -- las paredes sobresalen por encima del techo: se lee como cañón
local STEP = 20 -- resolución del trazado
local MAX_SEGMENT = 300 -- largo máximo de cada pieza de pared/suelo en rectas
local MAX_TURN_PER_SEGMENT = math.rad(4) -- en curvas, una pieza cada 4° de giro
local ROUTE_SPACING = 150 -- puntos de la línea ideal en los tramos sin obstáculos

local COLORS = {
	Cliff = Color3.fromRGB(128, 116, 104), -- paredes del corredor y acantilados
	Ground = Color3.fromRGB(92, 116, 76), -- suelo (mortal)
	Ceiling = Color3.fromRGB(175, 215, 255), -- techo semitransparente (se roza)
	Obstacle = Color3.fromRGB(215, 80, 60), -- lomas, vigas y salientes
	Guide = Color3.fromRGB(255, 205, 40), -- anillos guía (visuales)
	Portal = Color3.fromRGB(235, 240, 255), -- boca de entrada de cada nivel (visual)
	Grass = Color3.fromRGB(95, 165, 80),
	Rock = Color3.fromRGB(115, 100, 88),
	Beacon = Color3.fromRGB(255, 200, 90),
	Finish = Color3.fromRGB(120, 255, 140),
}
local STYLE = {
	Ceiling = { transparency = 0.65, noShadow = true },
	Guide = { neon = true, visual = true },
	Portal = { neon = true, visual = true },
	Finish = { neon = true, visual = true },
	Beacon = { neon = true },
}
local BEACON_COLORS = {
	Color3.fromRGB(255, 120, 120),
	Color3.fromRGB(255, 200, 90),
	Color3.fromRGB(150, 255, 120),
	Color3.fromRGB(110, 220, 255),
	Color3.fromRGB(190, 140, 255),
}

-- ── Primitivas ───────────────────────────────────────────────────────

-- shape: Enum.PartType (Ball, Cylinder…) o "Wedge" para una WedgePart (sube hacia su +Z local).
local function newPart(parent: Instance, name: string, kind: string, size: Vector3, cframe: CFrame, shape: any?)
	local style = STYLE[kind] or {}
	local part = Instance.new(if shape == "Wedge" then "WedgePart" else "Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = COLORS[kind]
	part.Material = if style.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	part.Transparency = style.transparency or 0
	part.CastShadow = not style.noShadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if typeof(shape) == "EnumItem" then
		(part :: Part).Shape = shape
	end
	if style.visual then
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
	end
	part:SetAttribute("Kind", kind)
	part.Parent = parent
	return part
end

-- Marcador invisible (Entry, Exit, rutas, spawns, zonas futuras): no colisiona ni cuenta como choque.
local function marker(parent: Instance, name: string, cframe: CFrame, size: Vector3?)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = size or Vector3.new(4, 4, 4)
	part.CFrame = cframe
	part.Parent = parent
	return part
end

local function newModel(parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- llega entero: siempre legible
	model.Parent = parent
	return model
end

local function newFolder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- Anillo rectangular orientado (visual): cf mira en la dirección del recorrido.
local function ring(parent, name, kind, cf: CFrame, w, h, bar, depth)
	local model = Instance.new("Model")
	model.Name = name
	local hw, hh = w / 2, h / 2
	newPart(model, "Top", kind, Vector3.new(w + 2 * bar, bar, depth), cf * CFrame.new(0, hh + bar / 2, 0))
	newPart(model, "Bottom", kind, Vector3.new(w + 2 * bar, bar, depth), cf * CFrame.new(0, -hh - bar / 2, 0))
	newPart(model, "Left", kind, Vector3.new(bar, h, depth), cf * CFrame.new(-hw - bar / 2, 0, 0))
	newPart(model, "Right", kind, Vector3.new(bar, h, depth), cf * CFrame.new(hw + bar / 2, 0, 0))
	model.Parent = parent
	return model
end

-- ── Trazado ("tortuga") ──────────────────────────────────────────────

local function forwardOf(heading: number): Vector3
	return Vector3.new(math.cos(heading), 0, -math.sin(heading))
end

local function rightOf(heading: number): Vector3
	return Vector3.new(math.sin(heading), 0, math.cos(heading))
end

local function frameCFrame(f): CFrame
	return CFrame.lookAt(f.pos, f.pos + forwardOf(f.heading))
end

-- Órdenes: { kind = "straight", length } | { kind = "arc", angle (grados, + izquierda), radius }
-- Cualquier orden acepta rise (subida total), width y height (cambian de forma progresiva).
-- { kind = "mark", name } guarda la distancia de ese punto para colocar obstáculos respecto a un tramo.
local function tracePath(start: Vector3, heading: number, width: number, height: number, commands)
	local frames = { { s = 0, pos = start, heading = heading, width = width, height = height } }
	local marks = {}
	local pos, h, w, hh, s = start, heading, width, height, 0
	for _, command in commands do
		if command.kind == "mark" then
			marks[command.name] = s
			continue
		end
		local length = if command.kind == "arc" then command.radius * math.rad(math.abs(command.angle)) else command.length
		local steps = math.max(1, math.ceil(length / STEP))
		local dl = length / steps
		local dh = if command.kind == "arc" then math.rad(command.angle) / steps else 0
		local dy = (command.rise or 0) / steps
		local w0, w1 = w, command.width or w
		local h0, h1 = hh, command.height or hh
		for i = 1, steps do
			pos += forwardOf(h + dh / 2) * dl + Vector3.new(0, dy, 0)
			h += dh
			s += dl
			local k = i / steps
			table.insert(frames, { s = s, pos = pos, heading = h, width = w0 + (w1 - w0) * k, height = h0 + (h1 - h0) * k })
		end
		w, hh = w1, h1
	end
	return frames, marks
end

local function frameAt(frames, s: number)
	s = math.clamp(s, 0, frames[#frames].s)
	for i = 1, #frames - 1 do
		local a, b = frames[i], frames[i + 1]
		if s <= b.s then
			local t = (s - a.s) / math.max(b.s - a.s, 1e-6)
			return {
				s = s,
				pos = a.pos:Lerp(b.pos, t),
				heading = a.heading + (b.heading - a.heading) * t,
				width = a.width + (b.width - a.width) * t,
				height = a.height + (b.height - a.height) * t,
			}
		end
	end
	return frames[#frames]
end

-- Agrupa pasos del trazado en piezas: largas en rectas, cortas en curvas y cambios de forma.
local function segments(frames)
	local list = {}
	local i = 1
	while i < #frames do
		local a = frames[i]
		local j = i + 1
		local slope = (frames[j].pos.Y - a.pos.Y) / math.max(frames[j].s - a.s, 1e-3)
		while j < #frames do
			local n = frames[j + 1]
			local nSlope = (n.pos.Y - frames[j].pos.Y) / math.max(n.s - frames[j].s, 1e-3)
			if
				math.abs(n.heading - a.heading) > MAX_TURN_PER_SEGMENT
				or math.abs(nSlope - slope) > 0.01
				or math.abs(n.width - a.width) > 0.5
				or math.abs(n.height - a.height) > 0.5
				or n.s - a.s > MAX_SEGMENT
			then
				break
			end
			j += 1
		end
		table.insert(list, { a, frames[j] })
		i = j
	end
	return list
end

-- Construye el "tubo" a lo largo del trazado: suelo, paredes y (si hay) techo.
-- opts.floor(f) / opts.top(f) = desplazamiento vertical del suelo y del borde superior de las paredes.
local function buildTube(parent: Instance, frames, opts)
	local shell = newFolder(parent, opts.name or "Corridor")
	for _, pair in segments(frames) do
		local a, b = pair[1], pair[2]
		local width = (a.width + b.width) / 2
		local turn = math.abs(b.heading - a.heading)

		-- Losas inclinadas (suelo/techo). En curvas se alargan para cubrir el borde exterior.
		local function slab(name, kind, offsetA, offsetB)
			local pa = a.pos + Vector3.new(0, offsetA, 0)
			local pb = b.pos + Vector3.new(0, offsetB, 0)
			local dir = pb - pa
			local mid = (pa + pb) / 2
			local length = dir.Magnitude + (width / 2 + WALL_T) * turn + 2
			newPart(shell, name, kind, Vector3.new(width + 2 * WALL_T, SLAB_T, length), CFrame.lookAt(mid, mid + dir))
		end
		slab("Floor", "Ground", opts.floor(a) - SLAB_T / 2, opts.floor(b) - SLAB_T / 2)
		if opts.ceiling then
			slab("Ceiling", "Ceiling", a.height / 2 + SLAB_T / 2, b.height / 2 + SLAB_T / 2)
		end

		-- Paredes verticales a cada lado (siguen curvas y estrechamientos).
		for _, side in { -1, 1 } do
			local wa = a.pos + rightOf(a.heading) * (side * (a.width / 2 + WALL_T / 2))
			local wb = b.pos + rightOf(b.heading) * (side * (b.width / 2 + WALL_T / 2))
			local flatA, flatB = Vector3.new(wa.X, 0, wa.Z), Vector3.new(wb.X, 0, wb.Z)
			local bottom = math.min(a.pos.Y + opts.floor(a), b.pos.Y + opts.floor(b)) - 30
			local top = math.max(a.pos.Y + opts.top(a), b.pos.Y + opts.top(b))
			local dir = flatB - flatA
			local mid = (flatA + flatB) / 2 + Vector3.new(0, (bottom + top) / 2, 0)
			newPart(shell, if side < 0 then "WallLeft" else "WallRight", "Cliff", Vector3.new(WALL_T, top - bottom, dir.Magnitude + 6), CFrame.lookAt(mid, mid + dir))
		end
	end
	return shell
end

local CORRIDOR = {
	ceiling = true,
	floor = function(f)
		return -f.height / 2
	end,
	top = function(f)
		return f.height / 2 + RIM
	end,
}

local VALLEY_TUBE = {
	name = "Valley",
	ceiling = false,
	floor = function()
		return -VALLEY.floorDepth
	end,
	top = function()
		return VALLEY.wallTop
	end,
}

local VALLEY_EXTENTS = { halfW = VALLEY.width / 2 + WALL_T, bottom = -VALLEY.floorDepth - 30, top = VALLEY.wallTop }

-- Cara de acantilado perpendicular al recorrido, con la boca del corredor (o cerrada si opening = nil).
local function cliffFace(parent, name, f, opening, extents)
	local cf = frameCFrame(f)
	local model = Instance.new("Model")
	model.Name = name
	local function block(blockName, u0, u1, v0, v1)
		if u1 - u0 < 0.5 or v1 - v0 < 0.5 then
			return
		end
		newPart(model, blockName, "Cliff", Vector3.new(u1 - u0, v1 - v0, 30), cf * CFrame.new((u0 + u1) / 2, (v0 + v1) / 2, 0))
	end
	if opening then
		local hw, hh = opening.w / 2, opening.h / 2
		block("Left", -extents.halfW, -hw, extents.bottom, extents.top)
		block("Right", hw, extents.halfW, extents.bottom, extents.top)
		block("Top", -hw, hw, hh, extents.top)
		block("Bottom", -hw, hw, extents.bottom, -hh)
	else
		block("Solid", -extents.halfW, extents.halfW, extents.bottom, extents.top)
	end
	model.Parent = parent
	return model
end

-- Isla flotante: plataforma + roca + faro lateral. Deja marcadores para checkpoints/spawns futuros.
local function island(model: Model, top: Vector3, heading: number, sizeAlong, sizeAcross, beaconColor: Color3, flightY: number)
	local orient = CFrame.lookAt(top, top + forwardOf(heading))
	newPart(model, "Platform", "Grass", Vector3.new(sizeAcross, 10, sizeAlong), orient * CFrame.new(0, -5, 0))
	local depth = 10
	for index, layer in { { 0.82, 26 }, { 0.55, 30 }, { 0.28, 34 } } do
		newPart(model, "Rock" .. index, "Rock", Vector3.new(sizeAcross * layer[1], layer[2], sizeAlong * layer[1]), orient * CFrame.new(0, -depth - layer[2] / 2, 0))
		depth += layer[2]
	end
	local beaconBase = orient * CFrame.new(sizeAcross / 2 - 16, 0, 0)
	local beaconHeight = flightY + 40 - top.Y
	local mast = newPart(model, "BeaconMast", "Rock", Vector3.new(beaconHeight, 6, 6), beaconBase * CFrame.new(0, beaconHeight / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.PartType.Cylinder)
	mast.Color = Color3.fromRGB(235, 235, 235)
	local light = newPart(model, "BeaconLight", "Beacon", Vector3.new(22, 22, 22), beaconBase * CFrame.new(0, beaconHeight, 0), Enum.PartType.Ball)
	light.Color = beaconColor
	marker(model, "SpawnPoint", orient * CFrame.new(0, 4, 0))
	marker(model, "CheckpointZone", CFrame.lookAt(Vector3.new(top.X, flightY, top.Z), Vector3.new(top.X, flightY, top.Z) + forwardOf(heading)), Vector3.new(VALLEY.width - 60, 300, 40))
end

-- ── Obstáculos y guías dentro de un corredor ─────────────────────────

local function makeContext(level: Model, frames, marks)
	local ctx = { points = {} }
	function ctx.mark(name: string): number
		return assert(marks[name], "marca desconocida: " .. name)
	end
	local features = newFolder(level, "Features")
	local guides = newFolder(level, "Guides")
	local count = 0
	local function nextName(prefix)
		count += 1
		return string.format("%s%02d", prefix, count)
	end
	local function at(s)
		return frameAt(frames, s)
	end

	-- Punto de la línea ideal (s = distancia desde la entrada, u lateral, v vertical respecto al centro).
	function ctx.point(s, u, v)
		table.insert(ctx.points, { s = s, u = u, v = v, feature = true })
	end

	-- Anillo guía amarillo (visual, se atraviesa).
	function ctx.guide(s, u, v, w, h)
		local f = at(s)
		ring(guides, nextName("Ring"), "Guide", frameCFrame(f) * CFrame.new(u, v, 0), w or 120, h or 85, 5, 4)
	end

	-- COLINA en el suelo (cuña de subida + cuña de bajada): hay que pasar por ENCIMA.
	-- s = posición de la cima · reach = cuánto sobrepasa la cima la línea central (obliga a subir eso)
	-- upSlope/downSlope en grados: por debajo de 23° (subida máxima del ala) se puede "seguir el terreno".
	-- Debe caer en un tramo recto: las cuñas son rectas.
	function ctx.ridge(s, reach, upSlope, downSlope)
		local f = at(s)
		local height = f.height / 2 + reach
		local upLength = height / math.tan(math.rad(upSlope or 15))
		local downLength = height / math.tan(math.rad(downSlope or 25))
		local base = Vector3.new(f.pos.X, f.pos.Y - f.height / 2, f.pos.Z)
		local frame = CFrame.lookAt(base, base + forwardOf(f.heading))
		local width = f.width + 2 * WALL_T
		local name = nextName("Ridge")
		-- En el marco del recorrido, -Z es "adelante": la subida queda antes de la cima y la bajada después.
		newPart(features, name .. "Up", "Obstacle", Vector3.new(width, height, upLength), frame * CFrame.new(0, height / 2, upLength / 2) * CFrame.Angles(0, math.pi, 0), "Wedge")
		newPart(features, name .. "Down", "Obstacle", Vector3.new(width, height, downLength), frame * CFrame.new(0, height / 2, -downLength / 2), "Wedge")
		ctx.point(s - upLength / 2, 0, -f.height / 2 + height / 2 + 35) -- a media subida
		ctx.point(s, 0, reach + 35) -- sobre la cima
		ctx.guide(s, 0, reach + 35)
	end

	-- VIGA colgada del techo (cara frontal vertical): hay que pasar por DEBAJO.
	-- reach = cuánto baja por debajo de la línea central (obliga a bajar al menos eso).
	function ctx.lintel(s, reach)
		local f = at(s)
		local depth = f.height / 2 + reach
		local ceilingY = f.pos.Y + f.height / 2
		local bottom = ceilingY - depth
		local top = ceilingY + RIM
		local center = Vector3.new(f.pos.X, (top + bottom) / 2, f.pos.Z)
		newPart(features, nextName("Lintel"), "Obstacle", Vector3.new(f.width + 2 * WALL_T, top - bottom, 40), CFrame.lookAt(center, center + forwardOf(f.heading)))
		local v = -(reach + 35)
		ctx.point(s, 0, v)
		ctx.guide(s, 0, v)
	end

	-- SALIENTE de una pared (side -1 izquierda, +1 derecha; prisma a 45°): hay que apartarse al otro lado.
	function ctx.promontory(s, side, depth)
		local f = at(s)
		local bottom, top = -f.height / 2 - 30, f.height / 2 + RIM
		local center = f.pos + rightOf(f.heading) * (side * f.width / 2) + Vector3.new(0, (bottom + top) / 2, 0)
		local size = depth * math.sqrt(2)
		local part = newPart(features, nextName("Promontory"), "Obstacle", Vector3.new(size, top - bottom, size), CFrame.lookAt(center, center + forwardOf(f.heading)) * CFrame.Angles(0, math.rad(45), 0))
		part:SetAttribute("Side", side) -- el vestido marca la arista que apunta al centro del corredor
		local u = -side * depth / 2
		ctx.point(s, u, 0)
		ctx.guide(s, u, 0, 100, 85)
	end

	return ctx
end

-- Línea ideal completa: puntos de los obstáculos + centro del corredor cada ROUTE_SPACING.
local function buildRoute(level: Model, frames, ctx)
	local length = frames[#frames].s
	local points = table.clone(ctx.points)
	local s = ROUTE_SPACING
	while s < length - 60 do
		local nearFeature = false
		for _, p in ctx.points do
			if math.abs(p.s - s) < 120 then
				nearFeature = true
			end
		end
		if not nearFeature then
			table.insert(points, { s = s, u = 0, v = 0 })
		end
		s += ROUTE_SPACING
	end
	table.sort(points, function(a, b)
		return a.s < b.s
	end)
	local folder = newFolder(level, "Route")
	for index, p in points do
		local f = frameAt(frames, p.s)
		local position = f.pos + rightOf(f.heading) * p.u + Vector3.new(0, p.v, 0)
		marker(folder, string.format("P%02d", index), CFrame.lookAt(position, position + forwardOf(f.heading)))
	end
end

-- ── Los 10 niveles base ───────────────────────────────────────────────
-- width/height = sección del corredor (ancho × alto libre). path = trazado. features = obstáculos/guías.
-- Fáciles a propósito: son la BASE de un juego de ~50 niveles. Nada de ventanas ni precisión fuerte.

local LEVELS = {
	{ -- 01: subir y bajar en un corredor recto y muy amplio.
		title = "Up and Down",
		width = 300,
		height = 220,
		path = { { kind = "straight", length = 2300 } },
		features = function(c)
			c.ridge(650, 20)
			c.lintel(1150, 20)
			c.ridge(1650, 20)
			c.lintel(2100, 20)
		end,
	},
	{ -- 02: izquierda / derecha con curvas muy suaves.
		title = "Left and Right",
		width = 300,
		height = 220,
		path = {
			{ kind = "straight", length = 300 },
			{ kind = "arc", angle = 30, radius = 420 },
			{ kind = "straight", length = 200 },
			{ kind = "arc", angle = -60, radius = 420 },
			{ kind = "straight", length = 200 },
			{ kind = "arc", angle = 60, radius = 420 },
			{ kind = "straight", length = 200 },
			{ kind = "arc", angle = -30, radius = 420 },
			{ kind = "straight", length = 300 },
		},
		features = function() end,
	},
	{ -- 03: altura + giro a la vez (curvas que suben o bajan).
		title = "Climb and Turn",
		width = 300,
		height = 220,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "arc", angle = 30, radius = 420, rise = 70 },
			{ kind = "straight", length = 200 },
			{ kind = "arc", angle = -60, radius = 420, rise = -100 },
			{ kind = "straight", length = 200 },
			{ kind = "arc", angle = 30, radius = 420, rise = 30 },
			{ kind = "straight", length = 300 },
		},
		features = function() end,
	},
	{ -- 04: primer corredor con curvas continuas (serpentina).
		title = "Winding Curves",
		width = 270,
		height = 200,
		path = {
			{ kind = "straight", length = 200 },
			{ kind = "arc", angle = 35, radius = 340 },
			{ kind = "arc", angle = -70, radius = 340 },
			{ kind = "arc", angle = 70, radius = 340 },
			{ kind = "arc", angle = -70, radius = 340 },
			{ kind = "arc", angle = 35, radius = 340 },
			{ kind = "straight", length = 250 },
		},
		features = function() end,
	},
	{ -- 05: subida sostenida (~11°, ~12 studs/s durante ~20 s: mantenerse separados).
		title = "Long Climb",
		width = 280,
		height = 210,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "straight", length = 1300, rise = 260 },
			{ kind = "arc", angle = 20, radius = 500 },
			{ kind = "arc", angle = -20, radius = 500 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			c.guide(900, 0, 0)
		end,
	},
	{ -- 06: descenso sostenido (~11°: mantenerse cerca del centro).
		title = "Long Descent",
		width = 280,
		height = 210,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "straight", length = 1300, rise = -260 },
			{ kind = "arc", angle = -20, radius = 500 },
			{ kind = "arc", angle = 20, radius = 500 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			c.guide(900, 0, 0)
		end,
	},
	{ -- 07: primer estrechamiento real (embudo a 190 × 150), curvas suaves y vuelta a abrirse.
		title = "Narrow Pass",
		width = 280,
		height = 210,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "straight", length = 300, width = 190, height = 150 },
			{ kind = "straight", length = 350 },
			{ kind = "arc", angle = 20, radius = 480 },
			{ kind = "arc", angle = -20, radius = 480 },
			{ kind = "straight", length = 300 },
			{ kind = "straight", length = 250, width = 260, height = 200 },
			{ kind = "straight", length = 150 },
		},
		features = function() end,
	},
	{ -- 08: primer slalom suave: salientes alternados de 100, uno cada 500.
		title = "Gentle Slalom",
		width = 300,
		height = 210,
		path = { { kind = "straight", length = 2500 } },
		features = function(c)
			c.promontory(500, -1, 100)
			c.promontory(1000, 1, 100)
			c.promontory(1500, -1, 100)
			c.promontory(2000, 1, 100)
		end,
	},
	{ -- 09: varias correcciones seguidas en un corredor más justo (240 × 180), sin ventanas.
		title = "Quick Corrections",
		width = 240,
		height = 180,
		path = {
			{ kind = "straight", length = 200 },
			{ kind = "arc", angle = 30, radius = 300, rise = 40 },
			{ kind = "arc", angle = -30, radius = 300 },
			{ kind = "mark", name = "salientes" },
			{ kind = "straight", length = 460 },
			{ kind = "arc", angle = -35, radius = 300, rise = -60 },
			{ kind = "arc", angle = 35, radius = 300 },
			{ kind = "mark", name = "lomaViga" },
			{ kind = "straight", length = 620 },
			{ kind = "arc", angle = 25, radius = 260 },
			{ kind = "arc", angle = -25, radius = 260 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			-- Ajustado a la regla de dificultad (FlightTester.checkRules): el primer saliente deja 160 de
			-- reacción tras la curva, salientes de 50 y la loma sube a 20° (por debajo de los 23° que sube el ala).
			local a = c.mark("salientes")
			c.promontory(a + 200, 1, 50)
			c.promontory(a + 430, -1, 50)
			local b = c.mark("lomaViga")
			c.ridge(b + 200, 15, 20, 25)
			c.lintel(b + 500, 15)
		end,
	},
	{ -- 10: prueba combinada de todo lo básico.
		title = "Final Test",
		width = 250,
		height = 200,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "straight", length = 600, rise = 120 }, -- subida
			{ kind = "arc", angle = -40, radius = 360 }, -- giro a la derecha
			{ kind = "straight", length = 600, rise = -160 }, -- descenso
			{ kind = "mark", name = "slalom" },
			{ kind = "straight", length = 1000 }, -- slalom
			{ kind = "arc", angle = 40, radius = 360, rise = 40 }, -- giro a la izquierda subiendo
			{ kind = "straight", length = 300, width = 210, height = 170 }, -- embudo (210 por la regla de dificultad)
			{ kind = "mark", name = "final" },
			{ kind = "straight", length = 620 }, -- colina + viga
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			-- Ajustado a la regla de dificultad: slalom de 65 con el primero a 240 del descenso, loma a 20°.
			local a = c.mark("slalom")
			c.promontory(a + 240, -1, 65)
			c.promontory(a + 540, 1, 65)
			c.promontory(a + 840, -1, 65)
			local b = c.mark("final")
			c.ridge(b + 230, 10, 20, 25)
			c.lintel(b + 560, 15)
		end,
	},
}

-- ── Construcción ──────────────────────────────────────────────────────

local function buildValley(map, name, frames)
	local model = newModel(map, name)
	buildTube(model, frames, VALLEY_TUBE)
	return model
end

function MapBuilder.build(options): string
	local dress = not (options and options.dress == false)
	local dressed = {}
	-- Viste un nivel/valle con el bioma del nivel biomeLevel (el de su capítulo o el forzado en LEVELS).
	-- index = posición en el recorrido (0 = StartIsland): decide si ya toca vestirlo y fija la semilla.
	-- Los valles usan el bioma del nivel SIGUIENTE: el valle de cambio de capítulo ya anuncia el bioma nuevo.
	local function dressModel(model: Model, index: number, biomeLevel: number)
		local spec = LEVELS[biomeLevel]
		local biome = Biomes.get(spec and spec.biome) or Biomes.chapter(biomeLevel)
		if not biome then
			return
		end
		model:SetAttribute("Biome", biome.name)
		-- Para la pantalla de checkpoint (Checkpoints.luau): nombre visible y color de acento del bioma.
		model:SetAttribute("BiomeTitle", biome.title or biome.name)
		model:SetAttribute("BiomeColor", biome.accent)
		if dress and index <= DRESS_LEVELS then
			local added = MapDresser.dress(model, biome, { wallT = WALL_T, rim = RIM, seed =20260922 + index * 7919 + #model.Name, index = index })
			table.insert(dressed, string.format("%s +%d", model.Name, added))
		end
	end

	local old = workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	local map = Instance.new("Folder")
	map.Name = "Map"
	map:SetAttribute("DevStartLevel", 0) -- 1-10 = despegar directamente en ese nivel (pruebas)
	map.Parent = workspace
	local devSpawns = newFolder(map, "DevSpawns")
	local summary = {}

	-- Valle inicial: acantilado cerrado detrás, StartIsland y despegue en su borde.
	local startFrames = tracePath(START, 0, VALLEY.width, 0, { { kind = "straight", length = VALLEY.length } })
	local start = buildValley(map, "StartIsland", startFrames)
	cliffFace(start, "BackWall", startFrames[1], nil, VALLEY_EXTENTS)
	local launch = frameAt(startFrames, LAUNCH_S)
	island(start, launch.pos - Vector3.new(0, 14, 0) - forwardOf(0) * 115, 0, 230, 280, BEACON_COLORS[1], CRUISE)
	marker(start, "LaunchPoint", frameCFrame(launch))
	marker(devSpawns, "Start", frameCFrame(launch))
	local template = workspace:FindFirstChild("AlaDelta")
	local bar = template and template:FindFirstChild("Agarre")
	if template and bar then
		template:PivotTo(template:GetPivot() + (launch.pos - bar.Position))
	end
	dressModel(start, 0, 1)

	local cursor = startFrames[#startFrames]
	local total = VALLEY.length
	for index, spec in LEVELS do
		local levelName = string.format("Level%02d", index)
		local frames, marks = tracePath(cursor.pos, cursor.heading, spec.width, spec.height, spec.path)
		local first, last = frames[1], frames[#frames]
		local level = newModel(map, levelName)
		level:SetAttribute("Title", spec.title)
		level:SetAttribute("Length", math.floor(last.s))
		level:SetAttribute("Width", spec.width)
		level:SetAttribute("Height", spec.height)

		buildTube(level, frames, CORRIDOR)
		cliffFace(level, "EntranceFace", first, { w = first.width, h = first.height }, VALLEY_EXTENTS)
		cliffFace(level, "ExitFace", last, { w = last.width, h = last.height }, VALLEY_EXTENTS)
		ring(level, "EntryPortal", "Portal", frameCFrame(first) * CFrame.new(0, 0, -18), first.width - 16, first.height - 16, 6, 4)
		marker(level, "Entry", frameCFrame(first))
		marker(level, "Exit", frameCFrame(last))

		local ctx = makeContext(level, frames, marks)
		spec.features(ctx)
		buildRoute(level, frames, ctx)
		dressModel(level, index, index)

		local spawnPos = first.pos - forwardOf(first.heading) * 150
		marker(devSpawns, levelName, CFrame.lookAt(spawnPos, spawnPos + forwardOf(first.heading)))
		table.insert(summary, string.format("%s %-22s %5.0f studs (~%2.0fs) · sección %d×%d · altitud %.0f → %.0f", levelName, spec.title, last.s, last.s / 60, spec.width, spec.height, first.pos.Y, last.pos.Y))
		total += last.s

		-- Pausa: valle abierto con isla (o la meta tras el último nivel).
		if index < #LEVELS then
			local valleyFrames = tracePath(last.pos, last.heading, VALLEY.width, 0, { { kind = "straight", length = VALLEY.length } })
			local rest = buildValley(map, string.format("RestIsland%02d", index), valleyFrames)
			rest:SetAttribute("Index", index)
			local middle = frameAt(valleyFrames, VALLEY.length / 2)
			island(rest, middle.pos - Vector3.new(0, 60, 0), middle.heading, 200, 220, BEACON_COLORS[(index - 1) % #BEACON_COLORS + 1], middle.pos.Y)
			dressModel(rest, index, index + 1)
			cursor = valleyFrames[#valleyFrames]
			total += VALLEY.length
		else
			local finishFrames = tracePath(last.pos, last.heading, VALLEY.width, 0, { { kind = "straight", length = 900 } })
			local finish = buildValley(map, "FinishIsland", finishFrames)
			local gate = frameAt(finishFrames, 150)
			ring(finish, "FinishGate", "Finish", frameCFrame(gate), 170, 120, 10, 10)
			marker(finish, "FinishLine", frameCFrame(gate), Vector3.new(170, 120, 4))
			local landing = frameAt(finishFrames, 480)
			island(finish, landing.pos - Vector3.new(0, 70, 0), landing.heading, 420, 360, COLORS.Finish, landing.pos.Y)
			-- Techo de aterrizaje: baja hasta la isla (tocar la isla termina el recorrido).
			local a = frameAt(finishFrames, 170).pos + Vector3.new(0, 60, 0)
			local b = frameAt(finishFrames, 460).pos + Vector3.new(0, -58, 0)
			newPart(finish, "LandingCeiling", "Cliff", Vector3.new(360, SLAB_T, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b))
			cliffFace(finish, "EndWall", finishFrames[#finishFrames], nil, VALLEY_EXTENTS)
			dressModel(finish, index, index)
			marker(devSpawns, "Finish", CFrame.lookAt(gate.pos - forwardOf(gate.heading) * 150, gate.pos))
			total += 900
		end
	end

	local parts = 0
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	table.insert(summary, string.format("Total ~%.0f studs (~%.1f min a 60 studs/s) · %d piezas", total, total / 60 / 60, parts))
	if #dressed > 0 then
		table.insert(summary, "Vestido: " .. table.concat(dressed, " · "))
	end
	return table.concat(summary, "\n")
end

return MapBuilder
