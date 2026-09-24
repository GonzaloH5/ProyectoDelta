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
--     salientes de pared (apartarse), pilares exentos (rodear). Anillos amarillos = guía visual, se atraviesan.
--   · Entre niveles: valle abierto con isla de descanso; cada corredor empieza en la boca de un acantilado.
--
-- Escala del ala (GliderConfig actual): avance 60 studs/s · radio de giro mínimo ~51, medio ~82 ·
-- subida máx 26 studs/s (23°) · caída máx 30 (27°) · envergadura 32, alto ~10 con los jugadores.
-- Rumbo: 0 = +X; ángulos positivos giran a la IZQUIERDA (-Z). "u" = lateral (+ derecha), "v" = vertical.
--
-- Vestido visual: tras generar cada nivel/valle, MapDresser lo "viste" con el bioma de su capítulo (Biomes).
-- .build({ dress = false }) genera el blockout puro (para depurar la jugabilidad). DRESS_LEVELS limita
-- hasta qué nivel se viste mientras el pase visual está a medias.
--
-- Trazado en filas (para que 50 niveles no se alejen del origen ni se crucen): 1-10 van hacia +X y cada
-- pareja 11-12, 21-22, 31-32 y 41-42 gira 90° + 90° (180°), así que las filas se alternan +X / -X, separadas
-- ~4.000 studs. Los demás niveles deben acabar con el mismo rumbo con el que empiezan (curvas que se compensan).
-- tools/sim (fuera de Studio) comprueba la separación, la regla de dificultad y la regla de oro.

local DevTools = game:GetService("ServerScriptService").Glider.DevTools
local Biomes = require(DevTools.Biomes:Clone())
local MapDresser = require(DevTools.MapDresser:Clone())

local MapBuilder = {}

local DRESS_LEVELS = 50 -- se visten los niveles hasta este (y sus valles); más allá queda el blockout

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
	Chevron = Color3.fromRGB(255, 255, 255), -- flechas que anuncian la maniobra antes de cada obstáculo (visual)
	ExitGlow = Color3.fromRGB(255, 225, 150), -- marco luminoso de la salida del corredor (visual)
	Grass = Color3.fromRGB(95, 165, 80),
	Rock = Color3.fromRGB(115, 100, 88),
	Beacon = Color3.fromRGB(255, 200, 90),
	Finish = Color3.fromRGB(120, 255, 140),
}
local STYLE = {
	Ceiling = { transparency = 0.65, noShadow = true },
	Guide = { neon = true, visual = true },
	Portal = { neon = true, visual = true },
	Chevron = { neon = true, visual = true, transparency = 0.1 },
	ExitGlow = { neon = true, visual = true, transparency = 0.2 },
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
	-- Streaming por distancia, pieza a pieza (LevelStreaming): un nivel entero de golpe provoca tirones.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Default
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
	-- below = studs por debajo de la viga a los que pasa la línea ideal (35 por defecto).
	function ctx.lintel(s, reach, below)
		local f = at(s)
		local depth = f.height / 2 + reach
		local ceilingY = f.pos.Y + f.height / 2
		local bottom = ceilingY - depth
		local top = ceilingY + RIM
		local center = Vector3.new(f.pos.X, (top + bottom) / 2, f.pos.Z)
		newPart(features, nextName("Lintel"), "Obstacle", Vector3.new(f.width + 2 * WALL_T, top - bottom, 40), CFrame.lookAt(center, center + forwardOf(f.heading)))
		local v = -(reach + (below or 35))
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

	-- PILAR exento (planta de rombo, del suelo a por encima del techo): hay que rodearlo por un lado.
	-- u = centro lateral (+ derecha) · width = ancho que tapa (diagonal del rombo) · pass = lado del paso
	-- (-1 izquierda, +1 derecha): la línea ideal va por el centro del hueco entre el pilar y esa pared.
	function ctx.pillar(s, u, width, pass)
		local f = at(s)
		local bottom, top = -f.height / 2 - 30, f.height / 2 + RIM
		local center = f.pos + rightOf(f.heading) * u + Vector3.new(0, (bottom + top) / 2, 0)
		local side = width / math.sqrt(2)
		local part = newPart(features, nextName("Pillar"), "Obstacle", Vector3.new(side, top - bottom, side), CFrame.lookAt(center, center + forwardOf(f.heading)) * CFrame.Angles(0, math.rad(45), 0))
		part:SetAttribute("Pass", pass)
		local edge = u + pass * width / 2 -- borde del pilar del lado del paso
		local wall = pass * f.width / 2
		local lane = (edge + wall) / 2
		ctx.point(s, lane, 0)
		ctx.guide(s, lane, 0, math.clamp(math.abs(wall - edge) - 24, 40, 100), 85)
	end

	-- AVISOS: antes de cada obstáculo, dos flechas (chevrones) que apuntan hacia donde hay que ir (arriba,
	-- abajo o a un lado) a 200 y 130 studs, a medio camino del paso. Solo el primer punto de cada obstáculo y si
	-- no hay otro obstáculo justo antes (sin amontonar). Visuales: no chocan ni cuentan en las pruebas.
	function ctx.telegraphs()
		local telegraphs = newFolder(level, "Telegraphs")
		local lastS = -math.huge
		local features = {}
		for _, p in ctx.points do
			if p.feature then
				table.insert(features, p)
			end
		end
		table.sort(features, function(a, b)
			return a.s < b.s
		end)
		for _, p in features do
			local previous = lastS
			lastS = p.s
			local du, dv = p.u or 0, p.v or 0
			if p.s - previous < 260 or math.max(math.abs(du), math.abs(dv)) < 15 then
				continue
			end
			local angle = if math.abs(dv) >= math.abs(du) then (if dv > 0 then math.pi / 2 else -math.pi / 2) else (if du > 0 then 0 else math.pi)
			for index, lead in { { 200, 0.45 }, { 130, 0.8 } } do
				local s = p.s - lead[1]
				if s < 60 then
					continue
				end
				local f = at(s)
				local tip = frameCFrame(f) * CFrame.new(du * lead[2], dv * lead[2], 0) * CFrame.Angles(0, 0, angle)
				local length, spread = 18, math.rad(38)
				for _, sign in { -1, 1 } do
					local offset = CFrame.new(-math.cos(spread) * length / 2, sign * math.sin(spread) * length / 2, 0)
					newPart(telegraphs, string.format("Chevron%02d", index), "Chevron", Vector3.new(length, 2.6, 1), tip * offset * CFrame.Angles(0, 0, -sign * spread))
				end
			end
		end
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

-- ── Los 50 niveles ────────────────────────────────────────────────────
-- width/height = sección del corredor (ancho × alto libre). path = trazado. features = obstáculos/guías.
-- 10 capítulos de 5 niveles (un bioma cada uno): como mucho una idea nueva por nivel y el último de cada
-- capítulo combina las del capítulo. Dificultad (FlightTester.RULES): 1-10 aprender, 11-25 practicar,
-- 26-50 dominar. Los capítulos 1-2 son fáciles a propósito: nada de ventanas ni precisión fuerte.

local LEVELS = {
	-- ── Capítulo 1 · Pradera (1-5): lo básico ───────────────────────────────
	{ -- 01: subir y bajar en un corredor recto y muy amplio.
		title = "Up and Down",
		width = 300,
		height = 220,
		path = { { kind = "straight", length = 2300 } },
		features = function(c)
			c.ridge(650, 20)
			c.lintel(1150, 20)
			c.ridge(1650, 15)
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

	-- ── Capítulo 2 · Cañón rojo (6-10): estrechamientos y correcciones ────────
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
	{ -- 09: varias correcciones seguidas en un corredor más justo (260 × 180), sin ventanas.
		title = "Quick Corrections",
		width = 260,
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
			c.promontory(a + 200, 1, 42)
			c.promontory(a + 430, -1, 42)
			local b = c.mark("lomaViga")
			c.ridge(b + 200, 10, 17, 25)
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
			{ kind = "straight", length = 300, width = 240, height = 170 }, -- embudo (240 por la regla de dificultad)
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
			c.ridge(b + 230, 5, 17, 25)
			c.lintel(b + 560, 15)
		end,
	},

	-- ── Capítulo 3 · Bosque otoñal (11-15): giros largos y colinas ─────────
	-- 11 y 12 dan la vuelta al recorrido (90° + 90° a la izquierda): la fila siguiente vuelve hacia -X.
	{ -- 11: primer giro largo: 90° a la izquierda en dos curvas amplias, con una colina entre ellas.
		title = "Autumn Bend",
		width = 280,
		height = 210,
		path = {
			{ kind = "straight", length = 300 },
			{ kind = "arc", angle = 45, radius = 520 },
			{ kind = "mark", name = "hill" },
			{ kind = "straight", length = 720 },
			{ kind = "arc", angle = 45, radius = 520 },
			{ kind = "straight", length = 300 },
		},
		features = function(c)
			c.guide(300 + 204, 0, 0)
			c.ridge(c.mark("hill") + 400, 15, 18, 25)
			c.guide(300 + 408 + 720 + 204, 0, 0)
		end,
	},
	{ -- 12: colinas seguidas (una detrás de otra) y el segundo giro de 90°.
		title = "Rolling Hills",
		width = 280,
		height = 210,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "arc", angle = 45, radius = 560 },
			{ kind = "mark", name = "hills" },
			{ kind = "straight", length = 1900 },
			{ kind = "arc", angle = 45, radius = 560 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			local a = c.mark("hills")
			c.ridge(a + 420, 10, 18, 22)
			c.ridge(a + 1000, 12, 18, 22)
			c.ridge(a + 1580, 15, 18, 22)
		end,
	},
	{ -- 13: túnel bajo (techo a 150) con curvas suaves: poco margen para subir o bajar.
		title = "Canopy Tunnel",
		width = 260,
		height = 210,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "straight", length = 250, height = 150 },
			{ kind = "arc", angle = 30, radius = 420 },
			{ kind = "arc", angle = -30, radius = 420 },
			{ kind = "mark", name = "low" },
			{ kind = "straight", length = 500 },
			{ kind = "arc", angle = -30, radius = 420 },
			{ kind = "arc", angle = 30, radius = 420 },
			{ kind = "straight", length = 250, height = 210 },
			{ kind = "straight", length = 200 },
		},
		features = function(c)
			c.lintel(c.mark("low") + 250, 8)
		end,
	},
	{ -- 14: slalom más rápido y más justo: salientes de 100 cada 330 en 250 de ancho, curva suave al final.
		title = "Leaf Slalom",
		width = 250,
		height = 210,
		path = {
			{ kind = "straight", length = 300 },
			{ kind = "mark", name = "slalom" },
			{ kind = "straight", length = 1600 },
			{ kind = "arc", angle = 25, radius = 450 },
			{ kind = "arc", angle = -25, radius = 450 },
			{ kind = "straight", length = 300 },
		},
		features = function(c)
			local a = c.mark("slalom")
			c.promontory(a + 250, -1, 100)
			c.promontory(a + 580, 1, 100)
			c.promontory(a + 910, -1, 100)
			c.promontory(a + 1240, 1, 100)
		end,
	},
	{ -- 15: prueba del capítulo: giro largo, colinas, túnel bajo y slalom.
		title = "Autumn Trial",
		width = 260,
		height = 200,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "arc", angle = -50, radius = 500 },
			{ kind = "mark", name = "hills" },
			{ kind = "straight", length = 1250 },
			{ kind = "arc", angle = 50, radius = 500 },
			{ kind = "straight", length = 250, height = 150 },
			{ kind = "mark", name = "low" },
			{ kind = "straight", length = 400 },
			{ kind = "straight", length = 250, height = 200 },
			{ kind = "mark", name = "slalom" },
			{ kind = "straight", length = 1100 },
			{ kind = "straight", length = 200 },
		},
		features = function(c)
			local a = c.mark("hills")
			c.ridge(a + 380, 10, 18, 22)
			c.ridge(a + 900, 12, 18, 22)
			c.lintel(c.mark("low") + 200, 8)
			local b = c.mark("slalom")
			c.promontory(b + 250, -1, 80)
			c.promontory(b + 580, 1, 80)
			c.promontory(b + 910, -1, 80)
		end,
	},

	-- ── Capítulo 4 · Mesetas del desierto (16-20): subir y bajar con obstáculos ─
	{ -- 16: subida en escalones: tramos de subida (~13°) separados por rellanos; un saliente en el segundo.
		title = "Mesa Steps",
		width = 240,
		height = 200,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "straight", length = 450, rise = 80 },
			{ kind = "straight", length = 350 },
			{ kind = "straight", length = 450, rise = 110 },
			{ kind = "mark", name = "landing" },
			{ kind = "straight", length = 350 },
			{ kind = "straight", length = 450, rise = 110 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			c.guide(250 + 450 + 175, 0, 0)
			c.promontory(c.mark("landing") + 175, -1, 80)
		end,
	},
	{ -- 17: bajada larga con vigas colgadas: agacharse mientras se desciende.
		title = "Canyon Drop",
		width = 270,
		height = 210,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "mark", name = "drop" },
			{ kind = "straight", length = 1500, rise = -300 },
			{ kind = "straight", length = 250 },
			{ kind = "arc", angle = -20, radius = 500 },
			{ kind = "arc", angle = 20, radius = 500 },
			{ kind = "straight", length = 200 },
		},
		features = function(c)
			local a = c.mark("drop")
			c.lintel(a + 450, 12)
			c.lintel(a + 1050, 12)
		end,
	},
	{ -- 18: curvas en zigzag que suben y bajan (más cerradas y largas que en el nivel 3).
		title = "Switchbacks",
		width = 240,
		height = 200,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "arc", angle = -45, radius = 320, rise = 60 },
			{ kind = "straight", length = 180 },
			{ kind = "arc", angle = 90, radius = 320, rise = -100 },
			{ kind = "straight", length = 180 },
			{ kind = "arc", angle = -90, radius = 320, rise = 80 },
			{ kind = "straight", length = 180 },
			{ kind = "arc", angle = 45, radius = 320, rise = -40 },
			{ kind = "straight", length = 250 },
		},
		features = function() end,
	},
	{ -- 19: un saliente te aparta justo antes de un paso estrecho (170 × 150): hay que volver al centro.
		title = "Mesa Gap",
		width = 270,
		height = 210,
		path = {
			{ kind = "straight", length = 300 },
			{ kind = "mark", name = "gate" },
			{ kind = "straight", length = 400 },
			{ kind = "straight", length = 250, width = 170, height = 150 },
			{ kind = "straight", length = 450 },
			{ kind = "straight", length = 250, width = 270, height = 210 },
			{ kind = "straight", length = 300 },
			{ kind = "arc", angle = 25, radius = 450 },
			{ kind = "arc", angle = -25, radius = 450 },
			{ kind = "straight", length = 200 },
		},
		features = function(c)
			c.promontory(c.mark("gate") + 200, 1, 95)
		end,
	},
	{ -- 20: prueba del capítulo: escalones, zigzag bajando, bajada con viga y paso estrecho.
		title = "Mesa Run",
		width = 260,
		height = 200,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "straight", length = 400, rise = 70 },
			{ kind = "straight", length = 200 },
			{ kind = "straight", length = 400, rise = 70 },
			{ kind = "mark", name = "top" },
			{ kind = "straight", length = 300 },
			{ kind = "arc", angle = -40, radius = 380, rise = -40 },
			{ kind = "arc", angle = 40, radius = 380, rise = -40 },
			{ kind = "mark", name = "drop" },
			{ kind = "straight", length = 800, rise = -60 },
			{ kind = "straight", length = 200 },
			{ kind = "straight", length = 200, width = 190, height = 160 },
			{ kind = "straight", length = 300 },
			{ kind = "straight", length = 200, width = 260, height = 200 },
			{ kind = "straight", length = 200 },
		},
		features = function(c)
			c.guide(c.mark("top") + 150, 0, 0)
			local a = c.mark("drop")
			c.lintel(a + 400, 12)
			c.promontory(a + 900, 1, 70)
		end,
	},

	-- ── Capítulo 5 · Glaciar (21-25): precisión en pasillos de hielo ────────
	-- 21 y 22 dan la segunda vuelta (90° + 90° a la derecha): la fila siguiente vuelve hacia +X.
	{ -- 21: giro de 90° a la derecha con el corredor estrechado a 220 en las curvas.
		title = "Glacier Bend",
		width = 260,
		height = 210,
		path = {
			{ kind = "straight", length = 300 },
			{ kind = "straight", length = 150, width = 220 },
			{ kind = "arc", angle = -45, radius = 480 },
			{ kind = "mark", name = "mid" },
			{ kind = "straight", length = 700, rise = 60 },
			{ kind = "arc", angle = -45, radius = 480 },
			{ kind = "straight", length = 150, width = 260 },
			{ kind = "straight", length = 300 },
		},
		features = function(c)
			c.guide(300 + 150 + 188, 0, 0)
			c.lintel(c.mark("mid") + 350, 12)
			c.guide(300 + 150 + 377 + 700 + 188, 0, 0)
		end,
	},
	{ -- 22: grieta: corredor estrecho y alto (170 × 240) con dos salientes pequeños, y el segundo giro de 90°.
		title = "Crevasse",
		width = 240,
		height = 220,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "straight", length = 200, width = 170, height = 240 },
			{ kind = "arc", angle = -45, radius = 520 },
			{ kind = "mark", name = "deep" },
			{ kind = "straight", length = 900, rise = 100 },
			{ kind = "arc", angle = -45, radius = 520 },
			{ kind = "straight", length = 200, width = 240, height = 220 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			local a = c.mark("deep")
			c.promontory(a + 250, 1, 45)
			c.promontory(a + 650, -1, 45)
		end,
	},
	{ -- 23: carámbanos: vigas seguidas de distinto largo (arriba-abajo a ritmo).
		title = "Icicles",
		width = 250,
		height = 210,
		path = {
			{ kind = "straight", length = 300 },
			{ kind = "mark", name = "ice" },
			{ kind = "straight", length = 1600, rise = 60 },
			{ kind = "arc", angle = 25, radius = 450 },
			{ kind = "arc", angle = -25, radius = 450 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			local a = c.mark("ice")
			c.lintel(a + 250, 10)
			c.lintel(a + 600, 18)
			c.lintel(a + 950, 12)
			c.lintel(a + 1300, 20)
		end,
	},
	{ -- 24: salientes en las curvas, en la pared de dentro: hay que abrirse para pasar.
		title = "Frozen Slalom",
		width = 240,
		height = 210,
		path = {
			{ kind = "straight", length = 300 },
			{ kind = "arc", angle = 35, radius = 420 },
			{ kind = "straight", length = 150 },
			{ kind = "arc", angle = -70, radius = 420 },
			{ kind = "straight", length = 150 },
			{ kind = "arc", angle = 70, radius = 420 },
			{ kind = "straight", length = 150 },
			{ kind = "arc", angle = -35, radius = 420 },
			{ kind = "straight", length = 300 },
		},
		features = function(c)
			local q = 420 * math.rad(35) -- largo de un arco de 35°
			c.promontory(300 + q / 2, -1, 85)
			c.promontory(300 + q + 150 + q, 1, 95)
			c.promontory(300 + q + 150 + 2 * q + 150 + q, -1, 95)
			c.promontory(300 + q + 150 + 2 * q + 150 + 2 * q + 150 + q / 2, 1, 85)
		end,
	},
	{ -- 25: prueba del capítulo: curva estrecha, carámbanos, grieta y salientes en curva.
		title = "Glacier Trial",
		width = 240,
		height = 210,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "straight", length = 150, width = 200 },
			{ kind = "arc", angle = 40, radius = 420 },
			{ kind = "arc", angle = -40, radius = 420 },
			{ kind = "straight", length = 150, width = 240 },
			{ kind = "mark", name = "ice" },
			{ kind = "straight", length = 900, rise = 60 },
			{ kind = "straight", length = 200, width = 190, height = 230 },
			{ kind = "straight", length = 500 },
			{ kind = "straight", length = 200, width = 240, height = 210 },
			{ kind = "mark", name = "curves" },
			{ kind = "arc", angle = -35, radius = 420 },
			{ kind = "arc", angle = 35, radius = 420 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			local a = c.mark("ice")
			c.lintel(a + 200, 12)
			c.lintel(a + 500, 18)
			c.lintel(a + 800, 12)
			local b = c.mark("curves")
			local q = 420 * math.rad(35)
			c.promontory(b + q / 2, 1, 60)
			c.promontory(b + q + q / 2, -1, 60)
		end,
	},

	-- ── Capítulo 6 · Acantilados (26-30): maniobras fuertes (desde aquí basta con el piloto completo) ─
	{ -- 26: picado largo (18°) y, al salir, una colina alta: hay que recuperar altura rápido.
		title = "Cliff Dive",
		width = 280,
		height = 220,
		path = {
			{ kind = "straight", length = 300 },
			{ kind = "straight", length = 800, rise = -250 },
			{ kind = "straight", length = 300 },
			{ kind = "mark", name = "pull" },
			{ kind = "straight", length = 800 },
			{ kind = "straight", length = 400 },
			{ kind = "arc", angle = 30, radius = 400 },
			{ kind = "arc", angle = -30, radius = 400 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			c.ridge(c.mark("pull") + 400, 25, 21, 25)
		end,
	},
	{ -- 27: farallones: pilares exentos en mitad del corredor; se rodean por el lado del anillo.
		title = "Sea Stacks",
		width = 270,
		height = 210,
		path = {
			{ kind = "straight", length = 300 },
			{ kind = "mark", name = "stacks" },
			{ kind = "straight", length = 1900 },
			{ kind = "arc", angle = -30, radius = 450 },
			{ kind = "arc", angle = 30, radius = 450 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			local a = c.mark("stacks")
			c.pillar(a + 300, -35, 100, 1)
			c.pillar(a + 700, 35, 100, -1)
			c.pillar(a + 1100, -25, 110, 1)
			c.pillar(a + 1500, 25, 110, -1)
		end,
	},
	{ -- 28: rompientes: colina y viga casi seguidas (subir y enseguida bajar), tres veces.
		title = "Breakers",
		width = 270,
		height = 220,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "mark", name = "waves" },
			{ kind = "straight", length = 2300 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			local a = c.mark("waves")
			c.ridge(a + 400, 20, 22, 30)
			c.lintel(a + 700, 20)
			c.ridge(a + 1150, 25, 22, 30)
			c.lintel(a + 1450, 22)
			c.ridge(a + 1900, 25, 22, 30)
			c.lintel(a + 2200, 25)
		end,
	},
	{ -- 29: horquillas: curvas de radio 180 encadenadas en 200 de ancho, subiendo y bajando.
		title = "Hairpins",
		width = 200,
		height = 200,
		path = {
			{ kind = "straight", length = 300 },
			{ kind = "arc", angle = 60, radius = 180, rise = 40 },
			{ kind = "straight", length = 120 },
			{ kind = "arc", angle = -120, radius = 180, rise = -60 },
			{ kind = "straight", length = 120 },
			{ kind = "arc", angle = 120, radius = 180, rise = 60 },
			{ kind = "straight", length = 120 },
			{ kind = "arc", angle = -60, radius = 180, rise = 20 },
			{ kind = "straight", length = 300 },
		},
		features = function() end,
	},
	{ -- 30: prueba del capítulo: picado y colina, farallones, horquillas y rompiente.
		title = "Cliff Trial",
		width = 260,
		height = 210,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "straight", length = 600, rise = -140 },
			{ kind = "straight", length = 200 },
			{ kind = "mark", name = "pull" },
			{ kind = "straight", length = 700 },
			{ kind = "straight", length = 150 },
			{ kind = "mark", name = "stacks" },
			{ kind = "straight", length = 950, rise = 80 },
			{ kind = "arc", angle = 60, radius = 240 },
			{ kind = "arc", angle = -60, radius = 240 },
			{ kind = "mark", name = "waves" },
			{ kind = "straight", length = 1000, rise = 60 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			c.ridge(c.mark("pull") + 380, 20, 21, 25)
			local a = c.mark("stacks")
			c.pillar(a + 250, -35, 90, 1)
			c.pillar(a + 650, 35, 90, -1)
			local b = c.mark("waves")
			c.ridge(b + 380, 20, 22, 30)
			c.lintel(b + 700, 20)
		end,
	},

	-- ── Capítulo 7 · Selva (31-35): dos ejes a la vez ────────────────────────
	-- 31 y 32 dan la tercera vuelta (90° + 90° a la izquierda): la fila siguiente vuelve hacia -X.
	{ -- 31: giro de 90° a la izquierda con una arboleda de pilares entre las dos curvas.
		title = "Jungle Bend",
		width = 260,
		height = 210,
		path = {
			{ kind = "straight", length = 300 },
			{ kind = "arc", angle = 45, radius = 500 },
			{ kind = "mark", name = "grove" },
			{ kind = "straight", length = 1100 },
			{ kind = "arc", angle = 45, radius = 500 },
			{ kind = "straight", length = 300 },
		},
		features = function(c)
			local a = c.mark("grove")
			c.pillar(a + 300, 35, 110, -1)
			c.pillar(a + 650, -35, 110, 1)
		end,
	},
	{ -- 32: cortina de lianas: vigas colgadas en mitad de las curvas, y el segundo giro de 90°.
		title = "Vine Curtain",
		width = 270,
		height = 210,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "arc", angle = 45, radius = 520 },
			{ kind = "mark", name = "a" },
			{ kind = "straight", length = 700 },
			{ kind = "arc", angle = 45, radius = 520 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			local q = 520 * math.rad(45)
			c.lintel(250 + q / 2, 15)
			c.lintel(c.mark("a") + 350, 22)
			c.lintel(c.mark("a") + 700 + q / 2, 15)
		end,
	},
	{ -- 33: por encima y por un lado: colina y enseguida un saliente; viga y enseguida un pilar.
		title = "Over and Around",
		width = 270,
		height = 220,
		path = {
			{ kind = "straight", length = 300 },
			{ kind = "mark", name = "d" },
			{ kind = "straight", length = 2300 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			local a = c.mark("d")
			c.ridge(a + 400, 20, 22, 28)
			c.promontory(a + 620, 1, 90)
			c.lintel(a + 1100, 20)
			c.pillar(a + 1350, -30, 100, 1)
			c.ridge(a + 1800, 25, 22, 28)
			c.promontory(a + 2030, -1, 95)
		end,
	},
	{ -- 34: laberinto de árboles: pilares alternados cada 320, subiendo.
		title = "Tree Maze",
		width = 270,
		height = 210,
		path = {
			{ kind = "straight", length = 300 },
			{ kind = "mark", name = "maze" },
			{ kind = "straight", length = 2000, rise = 80 },
			{ kind = "arc", angle = 30, radius = 400 },
			{ kind = "arc", angle = -30, radius = 400 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			local a = c.mark("maze")
			c.pillar(a + 250, -30, 110, 1)
			c.pillar(a + 570, 30, 110, -1)
			c.pillar(a + 890, -35, 110, 1)
			c.pillar(a + 1210, 35, 110, -1)
			c.pillar(a + 1530, -30, 110, 1)
			c.pillar(a + 1850, 30, 110, -1)
		end,
	},
	{ -- 35: prueba del capítulo: viga en curva, colina y saliente, y laberinto bajando.
		title = "Jungle Trial",
		width = 260,
		height = 210,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "arc", angle = 40, radius = 450 },
			{ kind = "arc", angle = -40, radius = 450 },
			{ kind = "mark", name = "combo" },
			{ kind = "straight", length = 900 },
			{ kind = "mark", name = "maze" },
			{ kind = "straight", length = 1000, rise = -80 },
			{ kind = "arc", angle = -40, radius = 450 },
			{ kind = "arc", angle = 40, radius = 450 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			c.lintel(250 + 450 * math.rad(40) / 2, 15)
			local a = c.mark("combo")
			c.ridge(a + 380, 20, 22, 28)
			c.promontory(a + 600, -1, 90)
			local b = c.mark("maze")
			c.pillar(b + 200, -30, 100, 1)
			c.pillar(b + 500, 30, 100, -1)
			c.pillar(b + 800, -30, 100, 1)
		end,
	},

	-- ── Capítulo 8 · Volcán (36-40): más rápido y más justo ──────────────────
	{ -- 36: tubo de lava: bajo (140) y estrecho (210) a la vez, con curvas y una viga.
		title = "Lava Tube",
		width = 250,
		height = 200,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "straight", length = 200, width = 210, height = 140 },
			{ kind = "arc", angle = 35, radius = 380 },
			{ kind = "arc", angle = -35, radius = 380 },
			{ kind = "mark", name = "tube" },
			{ kind = "straight", length = 600, rise = 60 },
			{ kind = "arc", angle = -35, radius = 380 },
			{ kind = "arc", angle = 35, radius = 380 },
			{ kind = "straight", length = 200, width = 250, height = 200 },
			{ kind = "straight", length = 200 },
		},
		features = function(c)
			c.lintel(c.mark("tube") + 300, 5)
		end,
	},
	{ -- 37: corriente ascendente: subida larga (14°) esquivando salientes.
		title = "Updraft",
		width = 240,
		height = 210,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "mark", name = "climb" },
			{ kind = "straight", length = 1800, rise = 450 },
			{ kind = "straight", length = 250 },
			{ kind = "arc", angle = 30, radius = 420 },
			{ kind = "arc", angle = -30, radius = 420 },
			{ kind = "straight", length = 200 },
		},
		features = function(c)
			local a = c.mark("climb")
			c.promontory(a + 350, -1, 105)
			c.promontory(a + 700, 1, 105)
			c.promontory(a + 1050, -1, 105)
			c.promontory(a + 1400, 1, 105)
		end,
	},
	{ -- 38: slalom de magma: salientes de 105 cada 240 en 240 de ancho.
		title = "Magma Slalom",
		width = 240,
		height = 210,
		path = {
			{ kind = "straight", length = 300 },
			{ kind = "mark", name = "slalom" },
			{ kind = "straight", length = 1900 },
			{ kind = "arc", angle = -25, radius = 450 },
			{ kind = "arc", angle = 25, radius = 450 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			local a = c.mark("slalom")
			for k = 0, 6 do
				c.promontory(a + 250 + 240 * k, if k % 2 == 0 then -1 else 1, 105)
			end
		end,
	},
	{ -- 39: espiral de ceniza: dos giros de 100° bajando, con salientes en la pared de fuera.
		title = "Ash Spiral",
		width = 250,
		height = 210,
		path = {
			{ kind = "straight", length = 300 },
			{ kind = "arc", angle = 100, radius = 330, rise = -185 },
			{ kind = "straight", length = 200 },
			{ kind = "arc", angle = -100, radius = 330, rise = -185 },
			{ kind = "mark", name = "exit" },
			{ kind = "straight", length = 500 },
			{ kind = "straight", length = 200 },
		},
		features = function(c)
			local q = 330 * math.rad(100)
			c.promontory(300 + q / 2, 1, 80)
			c.promontory(300 + q + 200 + q / 2, -1, 80)
			c.lintel(c.mark("exit") + 250, 18)
		end,
	},
	{ -- 40: prueba del capítulo: tubo de lava, subida con salientes, espiral y slalom.
		title = "Volcano Trial",
		width = 240,
		height = 200,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "straight", length = 200, width = 200, height = 145 },
			{ kind = "mark", name = "tube" },
			{ kind = "straight", length = 500 },
			{ kind = "straight", length = 200, width = 240, height = 200 },
			{ kind = "mark", name = "climb" },
			{ kind = "straight", length = 1200, rise = 250 },
			{ kind = "arc", angle = 90, radius = 340, rise = -120 },
			{ kind = "arc", angle = -90, radius = 340, rise = -120 },
			{ kind = "mark", name = "slalom" },
			{ kind = "straight", length = 1100 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			c.lintel(c.mark("tube") + 250, 5)
			local a = c.mark("climb")
			c.promontory(a + 350, -1, 100)
			c.promontory(a + 700, 1, 100)
			local b = c.mark("slalom")
			c.promontory(b + 250, 1, 105)
			c.promontory(b + 490, -1, 105)
			c.promontory(b + 730, 1, 105)
		end,
	},

	-- ── Capítulo 9 · Cristal (41-45): pilares y combinaciones justas ────────
	-- 41 y 42 dan la cuarta vuelta (90° + 90° a la derecha): la última fila vuelve hacia +X.
	{ -- 41: giro de 90° a la derecha con pilares al salir de las curvas.
		title = "Crystal Bend",
		width = 270,
		height = 210,
		path = {
			{ kind = "straight", length = 300 },
			{ kind = "arc", angle = -45, radius = 480 },
			{ kind = "mark", name = "a" },
			{ kind = "straight", length = 900 },
			{ kind = "arc", angle = -45, radius = 480 },
			{ kind = "mark", name = "b" },
			{ kind = "straight", length = 500 },
			{ kind = "straight", length = 100 },
		},
		features = function(c)
			local a = c.mark("a")
			c.pillar(a + 250, 30, 100, -1)
			c.pillar(a + 650, -30, 100, 1)
			c.pillar(c.mark("b") + 250, 0, 90, 1)
		end,
	},
	{ -- 42: sala de prismas: pilares en un corredor de 230 y el segundo giro de 90°.
		title = "Prism Hall",
		width = 230,
		height = 210,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "arc", angle = -45, radius = 500 },
			{ kind = "mark", name = "hall" },
			{ kind = "straight", length = 1200 },
			{ kind = "arc", angle = -45, radius = 500 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			local a = c.mark("hall")
			c.pillar(a + 250, -25, 75, 1)
			c.pillar(a + 550, 25, 75, -1)
			c.pillar(a + 850, -25, 75, 1)
		end,
	},
	{ -- 43: olas de esquirlas: colinas y vigas con un pilar entre cada una.
		title = "Shard Waves",
		width = 260,
		height = 220,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "mark", name = "w" },
			{ kind = "straight", length = 2400 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			local a = c.mark("w")
			c.ridge(a + 400, 25, 22, 30)
			c.pillar(a + 800, 0, 80, -1)
			c.lintel(a + 1150, 25)
			c.pillar(a + 1450, 0, 80, 1)
			c.ridge(a + 1900, 25, 22, 30)
			c.lintel(a + 2300, 20)
		end,
	},
	{ -- 44: laberinto de cristal: saliente, pilar, saliente… cada 250.
		title = "Crystal Maze",
		width = 240,
		height = 210,
		path = {
			{ kind = "straight", length = 300 },
			{ kind = "mark", name = "m" },
			{ kind = "straight", length = 2000 },
			{ kind = "arc", angle = 30, radius = 400 },
			{ kind = "arc", angle = -30, radius = 400 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			local a = c.mark("m")
			c.promontory(a + 250, -1, 100)
			c.pillar(a + 500, 30, 90, -1)
			c.promontory(a + 750, 1, 100)
			c.pillar(a + 1000, -30, 90, 1)
			c.promontory(a + 1250, -1, 100)
			c.pillar(a + 1500, 30, 90, -1)
			c.promontory(a + 1750, 1, 100)
		end,
	},
	{ -- 45: prueba del capítulo: curvas, sala de prismas, ola con pilar y laberinto.
		title = "Crystal Trial",
		width = 240,
		height = 210,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "arc", angle = 40, radius = 420 },
			{ kind = "arc", angle = -40, radius = 420 },
			{ kind = "mark", name = "hall" },
			{ kind = "straight", length = 800 },
			{ kind = "mark", name = "wave" },
			{ kind = "straight", length = 1100, rise = 80 },
			{ kind = "mark", name = "maze" },
			{ kind = "straight", length = 900 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			local a = c.mark("hall")
			c.pillar(a + 200, -25, 75, 1)
			c.pillar(a + 500, 25, 75, -1)
			local b = c.mark("wave")
			c.ridge(b + 380, 22, 22, 30)
			c.pillar(b + 750, 0, 80, 1)
			c.lintel(b + 1000, 22)
			local m = c.mark("maze")
			c.promontory(m + 200, -1, 90)
			c.pillar(m + 480, 30, 90, -1)
			c.promontory(m + 760, 1, 90)
		end,
	},

	-- ── Capítulo 10 · Cielo final (46-50): el examen, a gran altura ─────────
	{ -- 46: ascenso al cielo: subida larga (11°) con vigas por el camino.
		title = "Sky Ascent",
		width = 260,
		height = 220,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "mark", name = "up" },
			{ kind = "straight", length = 1800, rise = 350 },
			{ kind = "straight", length = 300 },
			{ kind = "arc", angle = -30, radius = 420 },
			{ kind = "arc", angle = 30, radius = 420 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			local a = c.mark("up")
			c.lintel(a + 400, 15)
			c.lintel(a + 900, 20)
			c.lintel(a + 1400, 22)
		end,
	},
	{ -- 47: surf entre nubes: colina y viga cada ~260 (subir y bajar sin respiro), tres veces.
		title = "Cloud Surf",
		width = 260,
		height = 220,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "mark", name = "surf" },
			{ kind = "straight", length = 2500 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			local a = c.mark("surf")
			c.ridge(a + 400, 22, 22, 30)
			c.lintel(a + 660, 22)
			c.ridge(a + 1100, 25, 22, 30)
			c.lintel(a + 1370, 25)
			c.ridge(a + 1800, 25, 22, 30)
			c.lintel(a + 2080, 25)
		end,
	},
	{ -- 48: slalom de tormenta: salientes y pilares en mitad de curvas encadenadas.
		title = "Storm Slalom",
		width = 230,
		height = 210,
		path = {
			{ kind = "straight", length = 300 },
			{ kind = "arc", angle = 40, radius = 400 },
			{ kind = "straight", length = 150 },
			{ kind = "arc", angle = -80, radius = 400 },
			{ kind = "straight", length = 150 },
			{ kind = "arc", angle = 80, radius = 400 },
			{ kind = "straight", length = 150 },
			{ kind = "arc", angle = -40, radius = 400 },
			{ kind = "straight", length = 300 },
		},
		features = function(c)
			local q = 400 * math.rad(40)
			c.promontory(300 + q / 2, -1, 85)
			c.pillar(300 + q + 150 + q, 30, 80, -1)
			c.promontory(300 + q + 150 + 2 * q + 150 + q, -1, 90)
			c.pillar(300 + q + 150 + 2 * q + 150 + 2 * q + 150 + q / 2, 25, 80, -1)
		end,
	},
	{ -- 49: el guantelete: ola, pilar en curva, laberinto y vigas en subida, sin descanso.
		title = "Heaven's Gauntlet",
		width = 250,
		height = 210,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "mark", name = "surf" },
			{ kind = "straight", length = 1000 },
			{ kind = "arc", angle = 45, radius = 420 },
			{ kind = "arc", angle = -45, radius = 420 },
			{ kind = "mark", name = "maze" },
			{ kind = "straight", length = 1000 },
			{ kind = "mark", name = "climb" },
			{ kind = "straight", length = 900, rise = 150 },
			{ kind = "arc", angle = -45, radius = 420, rise = -60 },
			{ kind = "arc", angle = 45, radius = 420, rise = -60 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			local a = c.mark("surf")
			c.ridge(a + 380, 22, 22, 30)
			c.lintel(a + 650, 22)
			c.pillar(a + 1000 + 420 * math.rad(45), -25, 80, 1)
			local m = c.mark("maze")
			c.promontory(m + 200, 1, 90)
			c.pillar(m + 480, -30, 90, 1)
			c.promontory(m + 760, -1, 90)
			local b = c.mark("climb")
			c.lintel(b + 300, 15)
			c.lintel(b + 650, 20)
		end,
	},
	{ -- 50: vuelo final: todo lo aprendido y un último picado hacia la meta.
		title = "Final Flight",
		width = 250,
		height = 210,
		path = {
			{ kind = "straight", length = 300 },
			{ kind = "mark", name = "a" },
			{ kind = "straight", length = 900 },
			{ kind = "arc", angle = 40, radius = 400 },
			{ kind = "arc", angle = -40, radius = 400 },
			{ kind = "mark", name = "b" },
			{ kind = "straight", length = 1100 },
			{ kind = "straight", length = 200, width = 190, height = 170 },
			{ kind = "straight", length = 300 },
			{ kind = "straight", length = 200, width = 250, height = 210 },
			{ kind = "mark", name = "c" },
			{ kind = "straight", length = 1000 },
			{ kind = "mark", name = "d" },
			{ kind = "straight", length = 1200, rise = -300 },
			{ kind = "straight", length = 400 },
		},
		features = function(c)
			local a = c.mark("a")
			c.ridge(a + 380, 20, 22, 28)
			c.promontory(a + 600, 1, 90)
			c.lintel(a + 900 + 400 * math.rad(40) / 2, 18)
			local b = c.mark("b")
			c.pillar(b + 200, -30, 100, 1)
			c.pillar(b + 500, 30, 100, -1)
			c.pillar(b + 800, -30, 100, 1)
			local d = c.mark("c")
			c.ridge(d + 380, 22, 22, 30)
			c.lintel(d + 660, 22)
			local e = c.mark("d")
			c.promontory(e + 300, -1, 85)
			c.promontory(e + 600, 1, 85)
			c.promontory(e + 900, -1, 85)
		end,
	},
}

-- ── Construcción ──────────────────────────────────────────────────────

local function buildValley(map, name, frames)
	local model = newModel(map, name)
	buildTube(model, frames, VALLEY_TUBE)
	return model
end

-- ── Tutorial: recorrido corto junto al mundo principal ───────────────────
-- Tres tramos muy fáciles con un bot de compañero (TutorialBot): subir, bajar y girar. Va en Map.Tutorial,
-- lejos del lobby y de las filas del recorrido. El bot pilota el rumbo por la línea ideal y el jugador decide
-- subir o bajar. coach = indicaciones de texto por tramo, en fracciones de la Route: { from, to, hint }.
local TUTORIAL_START = Vector3.new(0, CRUISE, 4000)
local TUTORIAL_LEVELS = {
	{ -- T1: subir por encima de una loma baja.
		title = "Climb",
		biome = "Pradera",
		width = 320,
		height = 230,
		path = { { kind = "straight", length = 1000 } },
		features = function(c)
			c.ridge(560, 10, 14, 20)
		end,
		coach = {
			{ 0, 0.62, "Both move OUT to climb over the hill!" },
			{ 0.62, 1, "Back to the CENTER to glide down" },
		},
	},
	{ -- T2: bajar por debajo de una viga.
		title = "Dive",
		biome = "Pradera",
		width = 320,
		height = 230,
		path = { { kind = "straight", length = 900 } },
		features = function(c)
			c.lintel(470, 9, 50)
		end,
		coach = {
			{ 0, 0.55, "Both move IN to the center to dive under the beam!" },
			{ 0.55, 1, "Move OUT again to climb back up" },
		},
	},
	{ -- T3: girar a la izquierda y a la derecha inclinándose los dos hacia el mismo lado.
		title = "Turn",
		biome = "Pradera",
		width = 320,
		height = 230,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "arc", angle = 35, radius = 450 },
			{ kind = "straight", length = 250 },
			{ kind = "arc", angle = -35, radius = 450 },
			{ kind = "straight", length = 250 },
		},
		features = function(c)
			c.guide(250 + 450 * math.rad(35) / 2, 0, 0)
			c.guide(250 + 450 * math.rad(35) + 250 + 450 * math.rad(35) / 2, 0, 0)
		end,
		coach = {
			{ 0.1, 0.42, "Lean LEFT with the Coach to turn left!" },
			{ 0.42, 0.52, "Back to the center" },
			{ 0.52, 0.84, "Lean RIGHT with the Coach to turn right!" },
			{ 0.84, 1, "Nice! Keep it straight to the finish" },
		},
	},
}
MapBuilder.TUTORIAL_LEVELS = TUTORIAL_LEVELS

-- Genera un recorrido completo dentro de `root`: StartIsland → LevelNN → RestIslandNN … → FinishIsland, con
-- DevSpawns. options: dress (vestir), seedBase (semilla del vestido), moveTemplate (llevar la AlaDelta al
-- despegue: solo el recorrido principal), dressUpTo (vestir hasta ese nivel). Devuelve el resumen y el total.
local function buildCourse(root: Instance, levels, startPos: Vector3, options): ({ string }, number, { string })
	local dressed = {}
	-- Viste un nivel/valle con el bioma del nivel biomeLevel (el de su capítulo o el forzado en la tabla).
	-- index = posición en el recorrido (0 = StartIsland): decide si ya toca vestirlo y fija la semilla.
	-- Los valles usan el bioma del nivel SIGUIENTE: el valle de cambio de capítulo ya anuncia el bioma nuevo.
	local function dressModel(model: Model, index: number, biomeLevel: number)
		local spec = levels[biomeLevel]
		local biome = Biomes.get(spec and spec.biome) or Biomes.chapter(biomeLevel)
		if not biome then
			return
		end
		model:SetAttribute("Biome", biome.name)
		-- Para la pantalla de checkpoint (Checkpoints.luau): nombre visible y color de acento del bioma.
		model:SetAttribute("BiomeTitle", biome.title or biome.name)
		model:SetAttribute("BiomeColor", biome.accent)
		if options.dress and index <= options.dressUpTo then
			local added = MapDresser.dress(model, biome, { wallT = WALL_T, rim = RIM, seed = options.seedBase + index * 7919 + #model.Name, index = index })
			table.insert(dressed, string.format("%s +%d", model.Name, added))
		end
	end

	local devSpawns = newFolder(root, "DevSpawns")
	local summary = {}

	-- Valle inicial: acantilado cerrado detrás, StartIsland y despegue en su borde.
	local startFrames = tracePath(startPos, 0, VALLEY.width, 0, { { kind = "straight", length = VALLEY.length } })
	local start = buildValley(root, "StartIsland", startFrames)
	cliffFace(start, "BackWall", startFrames[1], nil, VALLEY_EXTENTS)
	local launch = frameAt(startFrames, LAUNCH_S)
	island(start, launch.pos - Vector3.new(0, 14, 0) - forwardOf(0) * 115, 0, 230, 280, BEACON_COLORS[1], startPos.Y)
	marker(start, "LaunchPoint", frameCFrame(launch))
	marker(devSpawns, "Start", frameCFrame(launch))
	if options.moveTemplate then
		local template = workspace:FindFirstChild("AlaDelta")
		local bar = template and template:FindFirstChild("Agarre")
		if template and bar then
			template:PivotTo(template:GetPivot() + (launch.pos - bar.Position))
		end
	end
	dressModel(start, 0, 1)

	local cursor = startFrames[#startFrames]
	local total = VALLEY.length
	for index, spec in levels do
		local levelName = string.format("Level%02d", index)
		local frames, marks = tracePath(cursor.pos, cursor.heading, spec.width, spec.height, spec.path)
		local first, last = frames[1], frames[#frames]
		local level = newModel(root, levelName)
		level:SetAttribute("Title", spec.title)
		level:SetAttribute("Length", math.floor(last.s))
		level:SetAttribute("Width", spec.width)
		level:SetAttribute("Height", spec.height)
		if spec.coach then
			-- Indicaciones del tutorial para TutorialBot: "desde|hasta|lado|texto;…" (fracciones de la Route).
			local cues = {}
			for _, cue in spec.coach do
				table.insert(cues, string.format("%g|%g|%d|%s", cue[1], cue[2], cue[4] or 0, cue[3]))
			end
			level:SetAttribute("Coach", table.concat(cues, ";"))
		end

		buildTube(level, frames, CORRIDOR)
		cliffFace(level, "EntranceFace", first, { w = first.width, h = first.height }, VALLEY_EXTENTS)
		cliffFace(level, "ExitFace", last, { w = last.width, h = last.height }, VALLEY_EXTENTS)
		ring(level, "EntryPortal", "Portal", frameCFrame(first) * CFrame.new(0, 0, -18), first.width - 16, first.height - 16, 6, 4)
		marker(level, "Entry", frameCFrame(first))
		marker(level, "Exit", frameCFrame(last))

		local ctx = makeContext(level, frames, marks)
		spec.features(ctx)
		ctx.telegraphs()
		buildRoute(level, frames, ctx)
		-- Salida: marco luminoso (se ve desde lejos: "ahí termina el corredor").
		ring(level, "ExitGlow", "ExitGlow", frameCFrame(last) * CFrame.new(0, 0, 14), last.width - 12, last.height - 12, 4, 3)
		dressModel(level, index, index)

		local spawnPos = first.pos - forwardOf(first.heading) * 150
		marker(devSpawns, levelName, CFrame.lookAt(spawnPos, spawnPos + forwardOf(first.heading)))
		table.insert(summary, string.format("%s %-22s %5.0f studs (~%2.0fs) · sección %d×%d · altitud %.0f → %.0f", levelName, spec.title, last.s, last.s / 60, spec.width, spec.height, first.pos.Y, last.pos.Y))
		total += last.s

		-- Pausa: valle abierto con isla (o la meta tras el último nivel).
		if index < #levels then
			local valleyFrames = tracePath(last.pos, last.heading, VALLEY.width, 0, { { kind = "straight", length = VALLEY.length } })
			local rest = buildValley(root, string.format("RestIsland%02d", index), valleyFrames)
			rest:SetAttribute("Index", index)
			local middle = frameAt(valleyFrames, VALLEY.length / 2)
			island(rest, middle.pos - Vector3.new(0, 60, 0), middle.heading, 200, 220, BEACON_COLORS[(index - 1) % #BEACON_COLORS + 1], middle.pos.Y)
			dressModel(rest, index, index + 1)
			cursor = valleyFrames[#valleyFrames]
			total += VALLEY.length
		else
			local finishFrames = tracePath(last.pos, last.heading, VALLEY.width, 0, { { kind = "straight", length = 900 } })
			local finish = buildValley(root, "FinishIsland", finishFrames)
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
	return summary, total, dressed
end

-- Genera Workspace.Map: el recorrido principal (50 niveles) y, dentro, Map.Tutorial.
-- options.dress = false → blockout puro.
function MapBuilder.build(options): string
	local dress = not (options and options.dress == false)
	local old = workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	local map = Instance.new("Folder")
	map.Name = "Map"
	map:SetAttribute("DevStartLevel", 0) -- 1-50 = despegar directamente en ese nivel (pruebas)
	map.Parent = workspace

	local summary, total, dressed = buildCourse(map, LEVELS, START, { dress = dress, dressUpTo = DRESS_LEVELS, seedBase = 20260922, moveTemplate = true })

	local tutorial = Instance.new("Folder")
	tutorial.Name = "Tutorial"
	tutorial.Parent = map
	local tutorialSummary, tutorialTotal = buildCourse(tutorial, TUTORIAL_LEVELS, TUTORIAL_START, { dress = dress, dressUpTo = math.huge, seedBase = 7310, moveTemplate = false })

	local parts = 0
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	table.insert(summary, string.format("Total ~%.0f studs (~%.1f min a 60 studs/s) · %d piezas", total, total / 60 / 60, parts))
	table.insert(summary, string.format("Tutorial: %s · ~%.0f studs", (table.concat(tutorialSummary, " | "):gsub("%s+", " ")), tutorialTotal))
	if #dressed > 0 then
		table.insert(summary, "Vestido: " .. table.concat(dressed, " · "))
	end
	return table.concat(summary, "\n")
end

return MapBuilder
