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
local LAUNCH_S = 250 -- el despegue de los veteranos está a esta distancia del comienzo del valle inicial
local START_LENGTH = 450 -- valle inicial (StartIsland): ahí desemboca Flight School y despegan los veteranos
local VALLEY = { length = 600, width = 700, floorDepth = 320, wallTop = 420 } -- pausas entre corredores
-- Ritmo: dentro de un capítulo el valle es corto (~6 s: pantalla de checkpoint y respiro); al cambiar de capítulo,
-- largo (10 s: respiro grande y bioma nuevo).
local SHORT_VALLEY = 360
local WALL_T = 24 -- grosor de paredes
local SLAB_T = 8 -- grosor de suelo y techo
local RIM = 60 -- las paredes sobresalen por encima del techo: se lee como cañón
local STEP = 20 -- resolución del trazado
local CORRIDOR_SCALE = 0.75 -- capítulo 5: sección del corredor al 75 % (más sensación de velocidad)
-- Capítulos 6-10: elementos nuevos que MapBuilder reparte solo en cada nivel (ctx.autoExtras), además de los
-- obstáculos escritos a mano. Un nivel puede cambiar cuántos (extraCount) o saltarse alguno (skipExtras).
local CHAPTER_EXTRAS: { [number]: { string } } = {
	[6] = { "swingLog", "crosswind", "gate" }, -- Acantilados
	[7] = { "gate", "updraft", "swingLog" }, -- Selva
	[8] = { "downdraft", "spinner", "gate" }, -- Volcán
	[9] = { "spinner", "crosswind", "swingLog" }, -- Cristal
	[10] = { "updraft", "spinner", "gate", "swingLog" }, -- Cielo final
}
local MAX_SEGMENT = 300 -- largo máximo de cada pieza de pared/suelo en rectas
local MAX_TURN_PER_SEGMENT = math.rad(4) -- en curvas, una pieza cada 4° de giro
local ROUTE_SPACING = 150
local SLOT = { width = 56, narrow = 50, height = 44 } -- la ranura de Slot Canyon (el ala mide 32 de punta a punta) -- puntos de la línea ideal en los tramos sin obstáculos

local COLORS = {
	Cliff = Color3.fromRGB(128, 116, 104), -- paredes del corredor y acantilados
	Sandstone = Color3.fromRGB(214, 128, 78), -- paredes de la ranura (rebotan: GliderPhysics.rebound)
	Ground = Color3.fromRGB(92, 116, 76), -- suelo (mortal)
	Ceiling = Color3.fromRGB(175, 215, 255), -- techo semitransparente (se roza)
	Obstacle = Color3.fromRGB(215, 80, 60), -- lomas, vigas y salientes
	Guide = Color3.fromRGB(255, 205, 40), -- anillos guía (visuales)
	Portal = Color3.fromRGB(235, 240, 255), -- boca de entrada de cada nivel (visual)
	Chevron = Color3.fromRGB(255, 255, 255), -- flechas que anuncian la maniobra antes de cada obstáculo (visual)
	BoostRing = Color3.fromRGB(90, 210, 255), -- anillos de impulso (visual: dan energía al cruzarlos)
	Feather = Color3.fromRGB(255, 225, 90), -- plumas recolectables (visual)
	Mover = Color3.fromRGB(150, 96, 60), -- obstáculos móviles (Movers.luau: tronco, compuertas, aspas)
	ExitGlow = Color3.fromRGB(255, 225, 150), -- marco luminoso de la salida del corredor (visual)
	Grass = Color3.fromRGB(95, 165, 80),
	Rock = Color3.fromRGB(115, 100, 88),
	Beacon = Color3.fromRGB(255, 200, 90),
	Finish = Color3.fromRGB(120, 255, 140),
	Sign = Color3.fromRGB(34, 28, 24), -- carteles (visual): fondo oscuro, texto claro
}
local STYLE = {
	Ceiling = { transparency = 0.65, noShadow = true },
	Guide = { neon = true, visual = true },
	Portal = { neon = true, visual = true },
	Chevron = { neon = true, visual = true, transparency = 0.1 },
	BoostRing = { neon = true, visual = true },
	Feather = { neon = true, visual = true },
	ExitGlow = { neon = true, visual = true, transparency = 0.2 },
	Finish = { neon = true, visual = true },
	Beacon = { neon = true },
	Sign = { visual = true },
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

-- Aro circular (visual): `segments` bloques rectos repartidos en círculo en el plano XY de cf (mira hacia -Z).
-- Con 16 segmentos se lee redondo a la distancia de vuelo; cada bloque es un poco más largo para tapar juntas.
local function circleRing(parent, name, kind, cf: CFrame, radius: number, thickness: number, segments: number?)
	local count = segments or 16
	local model = Instance.new("Model")
	model.Name = name
	local length = 2 * (radius + thickness / 2) * math.tan(math.pi / count) + 0.2
	for k = 0, count - 1 do
		local angle = 2 * math.pi * k / count
		newPart(model, "Segment", kind, Vector3.new(length, thickness, thickness), cf * CFrame.Angles(0, 0, angle) * CFrame.new(0, radius, 0))
	end
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
-- Cualquier orden acepta rise (subida total), width y height (cambian de forma progresiva) y wall = "Sandstone"
-- (paredes de arenisca de ese tramo: rebotan, GliderPhysics.rebound; la ranura de Slot Canyon).
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
			table.insert(frames, { s = s, pos = pos, heading = h, width = w0 + (w1 - w0) * k, height = h0 + (h1 - h0) * k, wall = command.wall })
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
				or n.wall ~= frames[j].wall
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
			local part = newPart(shell, name, kind, Vector3.new(width + 2 * WALL_T, SLAB_T, length), CFrame.lookAt(mid, mid + dir))
			if opts.ceiling then
				part:SetAttribute("Clearance", math.min(a.height, b.height)) -- alto libre del tramo (vestido)
			end
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
			local wall = newPart(shell, if side < 0 then "WallLeft" else "WallRight", b.wall or "Cliff", Vector3.new(WALL_T, top - bottom, dir.Magnitude + 6), CFrame.lookAt(mid, mid + dir))
			if b.wall then
				wall:SetAttribute("Clearance", math.min(a.width, b.width)) -- ranura: el vestido no sobresale
			end
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

local function makeContext(level: Model, frames, marks, scale: number?)
	-- scale: el corredor se estrechó (capítulos 3-5); los obstáculos laterales se estrechan igual.
	local ctx = { points = {}, forks = {}, scale = scale or 1 }
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
	-- route = "A" / "B": solo para la línea de ese carril de una bifurcación (Route / RouteB).
	-- telegraph = false: sin chevrones de aviso.
	function ctx.point(s, u, v, route, telegraph)
		table.insert(ctx.points, { s = s, u = u, v = v, feature = true, route = route, telegraph = telegraph })
	end

	-- Carril (de ctx.divider) o todo el corredor: ancho y desplazamiento lateral de un obstáculo de lado a lado.
	local function span(f, lane)
		if lane then
			return lane.w, lane.u
		end
		return f.width + 2 * WALL_T, 0
	end

	-- Anillo guía amarillo (visual, se atraviesa): aro circular que cabe en el hueco w × h.
	function ctx.guide(s, u, v, w, h)
		local f = at(s)
		circleRing(guides, nextName("Ring"), "Guide", frameCFrame(f) * CFrame.new(u, v, 0), math.min(w or 120, h or 85) / 2, 4, 20)
	end

	-- CARTEL (visual) de w × h en (s, u, v), mirando al ala que llega: texto grande (en inglés) con borde de color.
	function ctx.sign(s, u, v, w, h, text, color)
		local board = newPart(features, nextName("Sign"), "Sign", Vector3.new(w, h, 1), frameCFrame(at(s)) * CFrame.new(u, v, 0))
		for _, edge in { { 0, h / 2 }, { 0, -h / 2 } } do
			local stripe = newPart(features, nextName("SignEdge"), "Chevron", Vector3.new(w + 2, 1.6, 1.4), frameCFrame(at(s)) * CFrame.new(u + edge[1], v + edge[2], 0))
			stripe.Color = color or COLORS.Guide
		end
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Back -- mira hacia el ala que llega
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 8
		gui.LightInfluence = 0
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = color or COLORS.Guide
		label.Text = text
		label.Parent = gui
		return board
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
	-- lane (opcional) = carril de una bifurcación (ctx.divider): la viga solo tapa ese carril.
	function ctx.lintel(s, reach, below, lane)
		local f = at(s)
		local depth = f.height / 2 + reach
		local ceilingY = f.pos.Y + f.height / 2
		local bottom = ceilingY - depth
		local top = ceilingY + RIM
		local width, u = span(f, lane)
		local center = Vector3.new(f.pos.X, (top + bottom) / 2, f.pos.Z) + rightOf(f.heading) * u
		newPart(features, nextName("Lintel"), "Obstacle", Vector3.new(width, top - bottom, 40), CFrame.lookAt(center, center + forwardOf(f.heading)))
		local v = -(reach + (below or 35))
		ctx.point(s, u, v, lane and lane.route, if lane then false else nil)
		ctx.guide(s, u, v, if lane then lane.w - 20 else nil)
	end

	-- MURO que sube del suelo (cara frontal vertical): hay que pasar por ENCIMA. Es el espejo de la viga: obliga a
	-- SUBIR (las lomas no obligan: son suelo y el ala resbala por encima). reach = cuánto sobrepasa la línea central;
	-- above = studs por encima del muro a los que pasa la línea ideal (35 por defecto); lane = solo ese carril.
	function ctx.barrier(s, reach, above, lane)
		local f = at(s)
		local bottom = f.pos.Y - f.height / 2 - 30
		local top = f.pos.Y + reach
		local width, u = span(f, lane)
		local center = Vector3.new(f.pos.X, (top + bottom) / 2, f.pos.Z) + rightOf(f.heading) * u
		newPart(features, nextName("Barrier"), "Obstacle", Vector3.new(width, top - bottom, 40), CFrame.lookAt(center, center + forwardOf(f.heading)))
		local v = reach + (above or 35)
		ctx.point(s, u, v, lane and lane.route, if lane then false else nil)
		ctx.guide(s, u, v, if lane then lane.w - 20 else nil)
	end

	-- VENTANA: pared de lado a lado con un hueco de w × h centrado en (u, v). Un hueco en diagonal lo resuelve UN
	-- solo jugador (arriba-izquierda: el izquierdo fuera · abajo-izquierda: el derecho dentro · arriba-derecha: el
	-- derecho fuera · abajo-derecha: el izquierdo dentro). Piezas WindowNNLeft/Right/Top/Bottom.
	-- extent (opcional) = { halfW, bottom, top }: tamaño de la pared si tiene que tapar algo mayor que el corredor en s
	-- (la boca de un túnel al final de una sala grande).
	function ctx.window(s, u, v, w, h, extent)
		u *= ctx.scale
		local f = at(s)
		local cf = frameCFrame(f)
		local halfW = if extent then extent.halfW else f.width / 2 + WALL_T
		local bottom = if extent then extent.bottom else -f.height / 2 - 30
		local top = if extent then extent.top else f.height / 2 + RIM
		local name = nextName("Window")
		local function block(suffix, u0, u1, v0, v1)
			if u1 - u0 < 0.5 or v1 - v0 < 0.5 then
				return
			end
			local part = newPart(features, name .. suffix, "Obstacle", Vector3.new(u1 - u0, v1 - v0, 16), cf * CFrame.new((u0 + u1) / 2, (v0 + v1) / 2, 0))
			-- Para el vestido: qué borde da al hueco y, en los laterales, su tramo vertical (en Y local de la pieza).
			part:SetAttribute("Edge", suffix)
			part:SetAttribute("EdgeSpan", Vector2.new(v - h / 2 - (v0 + v1) / 2, v + h / 2 - (v0 + v1) / 2))
		end
		block("Left", -halfW, u - w / 2, bottom, top)
		block("Right", u + w / 2, halfW, bottom, top)
		block("Top", u - w / 2, u + w / 2, v + h / 2, top)
		block("Bottom", u - w / 2, u + w / 2, bottom, v - h / 2)
		ctx.point(s, u, v)
		ctx.guide(s, u, v, w - 16, h - 16)
	end

	-- BIFURCACIÓN: muro largo de s0 a s1 (centro lateral u, ancho width, con morro de pilar en cada punta) que parte
	-- el corredor en dos carriles; los dos valen. La línea ideal (Route) va por el carril `pass` (-1 izquierda,
	-- +1 derecha) y RouteB por el otro. Devuelve los carriles { A = { u, w, route }, B = … } para ctx.lintel /
	-- ctx.barrier. Tramos rectos o curvas suaves.
	function ctx.divider(s0, s1, u, width, pass)
		u *= ctx.scale
		width *= ctx.scale
		local s = s0
		while s < s1 - 1 do
			local e = math.min(s + 100, s1)
			local fa, fb = at(s), at(e)
			local pa = fa.pos + rightOf(fa.heading) * u
			local pb = fb.pos + rightOf(fb.heading) * u
			local bottom = math.min(fa.pos.Y, fb.pos.Y) - math.max(fa.height, fb.height) / 2 - 30
			local top = math.max(fa.pos.Y, fb.pos.Y) + math.max(fa.height, fb.height) / 2 + RIM
			local flatA, flatB = Vector3.new(pa.X, 0, pa.Z), Vector3.new(pb.X, 0, pb.Z)
			local dir = flatB - flatA
			local mid = (flatA + flatB) / 2 + Vector3.new(0, (bottom + top) / 2, 0)
			newPart(features, nextName("Divider"), "Obstacle", Vector3.new(width, top - bottom, dir.Magnitude + 2), CFrame.lookAt(mid, mid + dir))
			s = e
		end
		for _, sn in { s0, s1 } do
			local f = at(sn)
			local bottom, top = -f.height / 2 - 30, f.height / 2 + RIM
			local center = f.pos + rightOf(f.heading) * u + Vector3.new(0, (bottom + top) / 2, 0)
			local side = width / math.sqrt(2)
			newPart(features, nextName("Pillar"), "Obstacle", Vector3.new(side, top - bottom, side), CFrame.lookAt(center, center + forwardOf(f.heading)) * CFrame.Angles(0, math.rad(45), 0))
		end
		local f = at(s0)
		local leftEdge, rightEdge = u - width / 2, u + width / 2
		local lanes = {
			[-1] = { u = (-f.width / 2 + leftEdge) / 2, w = leftEdge + f.width / 2 },
			[1] = { u = (rightEdge + f.width / 2) / 2, w = f.width / 2 - rightEdge },
		}
		local laneA, laneB = lanes[pass], lanes[-pass]
		laneA.route, laneB.route = "A", "B"
		table.insert(ctx.forks, { s0 = s0, s1 = s1, A = laneA.u, B = laneB.u }) -- la línea de relleno va por el carril
		for _, lane in { laneA, laneB } do
			ctx.point(s0 - 40, lane.u, 0, lane.route, false)
			ctx.point(s1 + 30, lane.u, 0, lane.route, false)
		end
		return { A = laneA, B = laneB }
	end

	-- SALIENTE de una pared (side -1 izquierda, +1 derecha; prisma a 45°): hay que apartarse al otro lado.
	function ctx.promontory(s, side, depth)
		depth *= ctx.scale
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
		u *= ctx.scale
		width *= ctx.scale
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

	-- CORRIENTES: zonas de viento (marcadores invisibles en LevelNN.Wind con atributo WindVelocity). El servidor
	-- y el FlightTester las leen con GliderPhysics.windZones; MapDresser las hace visibles (partículas y velo).
	-- Van en tramos rectos (la caja sigue el rumbo del centro del tramo).
	local windFolder: Folder? = nil
	-- u / width (opcionales) = centro lateral y ancho de la zona (por defecto, todo el corredor).
	local function windZone(kind: string, s0: number, length: number, velocity: Vector3, u: number?, width: number?)
		windFolder = windFolder or newFolder(level, "Wind")
		local f = at(s0 + length / 2)
		local size = Vector3.new(width or f.width, f.height, length)
		local zone = marker(windFolder :: Folder, nextName(kind), frameCFrame(f) * CFrame.new(u or 0, 0, 0), size)
		zone:SetAttribute("WindVelocity", velocity)
		zone:SetAttribute("WindKind", kind)
		return zone, f
	end

	-- CORRIENTE ASCENDENTE: sube `strength` studs/s mientras se está dentro (s0 … s0+length). Con ella se pasan
	-- lomas más altas y empinadas de lo que el ala sube sola (ridge con upSlope > 23°).
	-- u / width (opcionales): una columna a un lado del corredor en vez de todo el ancho.
	function ctx.updraft(s0, length, strength, u, width)
		windZone("Updraft", s0, length, Vector3.new(0, strength, 0), u, width)
	end

	-- CORRIENTE DESCENDENTE: hunde `strength` studs/s (p. ej. antes de una loma: hay que subir antes o impulsarse).
	function ctx.downdraft(s0, length, strength, u, width)
		windZone("Downdraft", s0, length, Vector3.new(0, -strength, 0), u, width)
	end

	-- VIENTO LATERAL: empuja hacia `side` (-1 izquierda, +1 derecha) `strength` studs/s: hay que inclinarse contra él.
	function ctx.crosswind(s0, length, side, strength, u, width)
		local f = at(s0 + length / 2)
		windZone("Crosswind", s0, length, rightOf(f.heading) * side * strength, u, width)
	end

	-- RÁFAGAS (turbulencia): `count` zonas cortas de viento lateral alternas desde s0, cada `spacing` studs y de
	-- `length` de largo, la primera hacia `side`. Hay que ir corrigiendo a un lado y a otro.
	function ctx.gusts(s0, count, spacing, length, strength, side)
		for i = 0, count - 1 do
			ctx.crosswind(s0 + i * spacing, length, (side or 1) * (if i % 2 == 0 then 1 else -1), strength)
		end
	end

	-- ── Obstáculos móviles (Movers.luau): la pieza queda en su posición de t = 0 con atributos de movimiento;
	-- MoverService la mueve en el servidor y MoverVisuals la dibuja en el cliente. Todos dejan un paso seguro
	-- siempre abierto (por él va la línea ideal) y otro más corto que hay que cronometrar.
	local moversFolder: Folder? = nil
	local function mover(name: string, size: Vector3, pivot: CFrame, attributes: { [string]: any })
		moversFolder = moversFolder or newFolder(level, "Movers")
		local part = newPart(moversFolder :: Folder, nextName(name), "Mover", size, pivot)
		for key, value in attributes do
			part:SetAttribute(key, value)
		end
		part:SetAttribute("Pivot", pivot)
		local Movers = require(game:GetService("ReplicatedStorage").Glider.Movers)
		part.CFrame = Movers.cframeAt(Movers.read(part) :: any, 0)
		return part
	end

	-- TRONCO que cuelga del techo y se balancea de lado a lado. reach = cuánto baja por debajo del centro al estar
	-- vertical (como una viga): por debajo siempre se pasa; a los lados, cuando se aparta.
	function ctx.swingLog(s, reach, period, phase)
		local f = at(s)
		local length = f.height / 2 + reach
		local amplitude = math.deg(math.asin(math.clamp((f.width / 2 - 20) / length, 0, 0.9)))
		local pivot = frameCFrame(f) * CFrame.new(0, f.height / 2, 0)
		local log = mover("SwingLog", Vector3.new(16, length, 16), pivot, { Motion = "swing", Period = period or 3.6, Phase = phase or 0, Amplitude = math.min(amplitude, 55), Length = length })
		log.Color = Color3.fromRGB(120, 78, 48)
		log.Material = Enum.Material.WoodPlanks
		ctx.point(s, 0, -(reach + 35))
	end

	-- COMPUERTAS: dos puertas salen de las paredes y se abren y cierran; el hueco central nunca baja de minGap.
	function ctx.gate(s, minGap, maxGap, period, phase)
		local f = at(s)
		local height = f.height + 2 * RIM
		for _, side in { -1, 1 } do
			local door = mover("Gate", Vector3.new(f.width / 2, height, 12), frameCFrame(f), { Motion = "gate", Period = period or 4, Phase = phase or 0, Side = side, MinGap = minGap, MaxGap = maxGap or f.width - 20, DoorWidth = f.width / 2 })
			door.Color = Color3.fromRGB(110, 118, 130)
			door.Material = Enum.Material.DiamondPlate
		end
		ctx.point(s, 0, 0)
	end

	-- ASPAS: n aspas giran alrededor del eje del corredor; las esquinas quedan siempre libres (por ahí va la
	-- línea ideal, lado `pass` = -1/+1 y abajo) y el centro hay que cronometrarlo. inset = distancia de la línea
	-- ideal a las paredes (26 por defecto; más, con aspas cortas, para no pasar rozando la pared).
	function ctx.spinner(s, blades, period, pass, phase, size, inset)
		local f = at(s)
		local radius = math.min(f.width, f.height) / 2 * (size or 0.65)
		for i = 1, blades do
			local blade = mover("Spinner", Vector3.new(10, radius, 10), frameCFrame(f), { Motion = "spinner", Period = period or 5, Phase = phase or 0, Radius = radius, Angle = 360 * (i - 1) / blades })
			blade.Color = Color3.fromRGB(220, 70, 60)
			blade.Material = Enum.Material.Metal
		end
		ctx.point(s, (pass or 1) * (f.width / 2 - (inset or 26)), -(f.height / 2 - (inset or 26) + 4))
	end

	-- ANILLO DE IMPULSO en (s, u, v): cruzarlo da energía y un empujón. Aro azul circular de diámetro size
	-- (visual) y un marcador de plano con atributo Radius en LevelNN.Rings (lo lee Checkpoints). Se ponen en
	-- líneas algo más arriesgadas.
	local ringsFolder: Folder? = nil
	function ctx.boostRing(s, u, v, size)
		size = size or 46
		ringsFolder = ringsFolder or newFolder(level, "Rings")
		local cf = frameCFrame(at(s)) * CFrame.new(u, v, 0)
		local hoop = circleRing(guides, nextName("BoostRing"), "BoostRing", cf, size / 2, 3)
		-- Velo interior muy transparente: se lee el hueco por el que hay que pasar.
		local veil = newPart(hoop, "Veil", "BoostRing", Vector3.new(0.4, size - 2, size - 2), cf * CFrame.Angles(0, math.pi / 2, 0), Enum.PartType.Cylinder)
		veil.Transparency = 0.85
		local plane = marker(ringsFolder :: Folder, nextName("RingPlane"), cf, Vector3.new(size + 6, size + 6, 4))
		plane:SetAttribute("Radius", size / 2)
	end

	-- PLUMAS: n gemas recolectables de s0 a s1, de (u0, v0) a (u1, v1) (se recogen pasando a ≤ 12 studs).
	local feathersFolder: Folder? = nil
	local featherCount = 0
	function ctx.feathers(s0, s1, n, u0, v0, u1, v1)
		feathersFolder = feathersFolder or newFolder(level, "Feathers")
		for i = 1, n do
			local k = if n == 1 then 0.5 else (i - 1) / (n - 1)
			local cf = frameCFrame(at(s0 + (s1 - s0) * k)) * CFrame.new(u0 + ((u1 or u0) - u0) * k, v0 + ((v1 or v0) - v0) * k, 0)
			featherCount += 1
			local gem = newPart(feathersFolder :: Folder, "Feather", "Feather", Vector3.new(4, 4, 4), cf * CFrame.Angles(math.rad(45), 0, math.rad(45)))
			gem:SetAttribute("FeatherId", featherCount)
		end
	end

	-- EXTRAS automáticos (capítulos 6-10): coloca los elementos de `kinds` (en orden, repitiendo) en tramos casi
	-- rectos y libres: a ≥ 230 studs de cualquier obstáculo, ≥ 380 entre sí y lejos de la entrada y la salida.
	-- Cada uno lleva además una hilera de plumas o un anillo cerca. skip = índices a saltar (ajustes a mano).
	function ctx.autoExtras(kinds: { string }, count: number, skip: { [number]: boolean }?)
		local length = frames[#frames].s
		local taken = {}
		for _, p in ctx.points do
			if p.feature then
				table.insert(taken, p.s)
			end
		end
		local function free(s: number, gap: number): boolean
			for _, other in taken do
				if math.abs(other - s) < gap then
					return false
				end
			end
			local a, b = at(s - 120), at(s + 120)
			local turn = math.abs((b.heading - a.heading + math.pi) % (2 * math.pi) - math.pi)
			return turn < math.rad(14) and math.abs(b.pos.Y - a.pos.Y) < 50 -- casi recto y sin pendiente fuerte
		end
		local placed, index = 0, 0
		local s = 350
		while s < length - 350 and placed < count do
			if free(s, 230) then
				index += 1
				if not (skip and skip[index]) then
					local kind = kinds[(placed % #kinds) + 1]
					if kind == "swingLog" then
						ctx.swingLog(s, 0, 3.4 + (placed % 3) * 0.3, placed * 0.21)
					elseif kind == "gate" then
						ctx.gate(s, 75, nil, 3.8, placed * 0.17)
					elseif kind == "spinner" then
						ctx.spinner(s, 2, 5, if placed % 2 == 0 then 1 else -1, placed * 0.13)
					elseif kind == "updraft" then
						ctx.updraft(s - 150, 300, 10)
						ctx.point(s, 0, 20)
					elseif kind == "downdraft" then
						ctx.downdraft(s - 150, 300, 8)
						ctx.point(s, 0, -15)
					elseif kind == "crosswind" then
						ctx.crosswind(s - 150, 300, if placed % 2 == 0 then 1 else -1, 9)
						ctx.point(s, 0, 0)
					end
					-- Recompensa cerca: plumas en una línea algo arriesgada o un anillo.
					if placed % 2 == 0 then
						ctx.feathers(s + 130, s + 250, 3, 25, -20, 25, -20)
					else
						ctx.boostRing(s + 190, -25, 10)
					end
					table.insert(taken, s)
					placed += 1
				else
					table.insert(taken, s)
				end
				s += 380
			else
				s += 40
			end
		end
		if placed == 0 then
			-- Nivel muy denso: al menos plumas por la línea ideal (no estorban).
			ctx.feathers(length * 0.3, length * 0.3 + 90, 3, 0, 0, 0, 0)
			ctx.feathers(length * 0.65, length * 0.65 + 90, 3, 0, 0, 0, 0)
		end
	end

	-- AVISOS: antes de cada obstáculo, dos flechas (chevrones) que apuntan hacia donde hay que ir (arriba,
	-- abajo o a un lado) a 200 y 130 studs, a medio camino del paso. Solo el primer punto de cada obstáculo y si
	-- no hay otro obstáculo justo antes (sin amontonar). Visuales: no chocan ni cuentan en las pruebas.
	function ctx.telegraphs()
		local telegraphs = newFolder(level, "Telegraphs")
		local lastS = -math.huge
		local features = {}
		for _, p in ctx.points do
			if p.feature and p.telegraph ~= false then
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
			-- Hacia el paso (también en diagonal: ventanas).
			local angle = if math.abs(du) < 15 then (if dv > 0 then math.pi / 2 else -math.pi / 2) elseif math.abs(dv) < 15 then (if du > 0 then 0 else math.pi) else math.atan2(dv, du)
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
	local hasB = false
	for _, p in ctx.points do
		if p.route == "B" then
			hasB = true
		end
	end
	-- Route = todo menos el carril B; RouteB (solo si hay bifurcación) = todo menos el carril A.
	local variants = if hasB then { "A", "B" } else { "A" }
	for _, variant in variants do
		local skip = if variant == "A" then "B" else "A"
		local points = {}
		for _, p in ctx.points do
			if p.route ~= skip then
				table.insert(points, p)
			end
		end
		local s = ROUTE_SPACING
		while s < length - 60 do
			local nearFeature = false
			for _, p in ctx.points do
				if math.abs(p.s - s) < 120 then
					nearFeature = true
				end
			end
			if not nearFeature then
				-- Dentro de una bifurcación, por el centro de su carril (el centro del corredor es el divisor).
				local u = 0
				for _, fork in ctx.forks do
					if s >= fork.s0 - 60 and s <= fork.s1 + 40 then
						u = fork[variant]
					end
				end
				table.insert(points, { s = s, u = u, v = 0 })
			end
			s += ROUTE_SPACING
		end
		table.sort(points, function(a, b)
			return a.s < b.s
		end)
		local folder = newFolder(level, if variant == "A" then "Route" else "RouteB")
		for index, p in points do
			local f = frameAt(frames, p.s)
			local position = f.pos + rightOf(f.heading) * p.u + Vector3.new(0, p.v, 0)
			marker(folder, string.format("P%02d", index), CFrame.lookAt(position, position + forwardOf(f.heading)))
		end
	end
end

-- ── Los 50 niveles ────────────────────────────────────────────────────
-- width/height = sección del corredor (ancho × alto libre). path = trazado. features = obstáculos/guías.
-- 10 capítulos de 5 niveles (un bioma cada uno): como mucho una idea nueva por nivel y el último de cada
-- capítulo combina las del capítulo. Dificultad (FlightTester.RULES): 1-10 aprender, 11-25 practicar,
-- 26-50 dominar. Los capítulos 1-2 son fáciles a propósito: nada de ventanas ni precisión fuerte.

local LEVELS = {
	-- ── Capítulo 1 · Pradera (1-5): "Juntos" ─────────────────────────────────
	-- Aprender a volar a dúo: los dos igual (1), opuestos y cambio de lado (2), uno solo (3), la primera fuerza y
	-- el primer espacio abierto (4) y elegir juntos (5). Solo la barra: el impulso llega en el nivel 6.
	-- Cada nivel: presentar → practicar → giro → final memorable → respiro. Nunca > 5 s sin nada que hacer.
	{ -- 01 · Up & Under — el sube-y-baja. Vigas (bajar) y muros (subir) alternos, cada vez más juntos
		-- (6 s → 3,7 s). Coordinación: "¡ABAJO!… ¡ARRIBA!" a la vez. Final: "la ola", con plumas en la línea buena.
		title = "Up & Under",
		tagline = "Dive. Climb. Faster.",
		width = 220,
		height = 170,
		path = { { kind = "straight", length = 2330 } },
		features = function(c)
			c.lintel(380, 15, 35) -- presentar: bajar
			c.barrier(720, 15, 35) -- presentar: subir
			c.lintel(1030, 10, 35) -- practicar
			c.barrier(1310, 5, 32)
			c.lintel(1580, 5, 32) -- la ola
			c.feathers(1640, 1730, 3, 0, -20, 0, 18)
			c.barrier(1820, 5, 32)
			c.lintel(2060, 5, 32)
		end,
	},
	{ -- 02 · Swap — izquierda-derecha de verdad. Curvas comprometidas (uno fuera y el otro dentro), pilares a
		-- lados alternos y una chicane: cambiar de lado los dos a la vez. Sin sincronía, bache arriba o abajo.
		-- Final: la chicane (≈ 7 s cambiando sin parar).
		title = "Swap",
		tagline = "Swap sides together",
		width = 200,
		height = 170,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "arc", angle = 60, radius = 170 },
			{ kind = "straight", length = 180 },
			{ kind = "arc", angle = -60, radius = 170 },
			{ kind = "straight", length = 200, width = 280 },
			{ kind = "mark", name = "pillars" },
			{ kind = "straight", length = 500 },
			{ kind = "straight", length = 150, width = 190 },
			{ kind = "mark", name = "chicane" },
			{ kind = "arc", angle = 50, radius = 120 },
			{ kind = "arc", angle = -100, radius = 120 },
			{ kind = "arc", angle = 50, radius = 120 },
			{ kind = "straight", length = 150 },
		},
		features = function(c)
			local p = c.mark("pillars") -- slalom: cada pilar, cambio de lado
			c.pillar(p + 50, 40, 64, -1)
			c.pillar(p + 245, -40, 64, 1)
			c.pillar(p + 440, 40, 64, -1)
			local q = c.mark("chicane")
			c.feathers(q + 105 + 70, q + 105 + 140, 3, 30, 0, 30, 0) -- por dentro de la curva del medio
		end,
	},
	{ -- 03 · Windows — ¿quién se mueve? Paredes con un hueco desplazado: arriba y abajo (conocidos), luego las
		-- diagonales, que empieza a resolver UNO solo (arriba-izquierda: el izquierdo fuera · abajo-derecha: el
		-- izquierdo dentro · arriba-derecha: el derecho fuera). Si se mueve el que no era: BONK con el marco.
		-- Final: abajo-izquierda → arriba-izquierda seguidas (cambia quién se mueve).
		title = "Windows",
		tagline = "Who moves?",
		width = 220,
		height = 170,
		path = { { kind = "straight", length = 2230 } },
		features = function(c)
			c.window(340, 0, 30, 130, 90) -- los dos fuera
			c.window(630, 0, -30, 130, 90) -- los dos dentro
			c.window(940, -45, 30, 120, 90) -- arriba-izquierda
			c.window(1240, 45, -30, 120, 90) -- abajo-derecha
			c.window(1540, 45, 30, 120, 90) -- arriba-derecha
			c.window(1820, -45, -30, 115, 88) -- abajo-izquierda
			c.window(2040, -45, 30, 115, 88) -- arriba-izquierda
		end,
	},
	{ -- 04 · The Chimney — la corriente gigante. El corredor se abre a una sala enorme (el suelo cae) con una
		-- columna ascendente a la derecha; la sala acaba en un muro de +230 que sin la corriente no se sube.
		-- Primera fuerza y primer espacio abierto: respiro y espectáculo tras tres niveles técnicos.
		-- Final: salir disparados por encima del borde y bajar planeando, con una rampa de surf al final.
		title = "The Chimney",
		tagline = "Ride the wind up",
		width = 200,
		height = 170,
		path = {
			{ kind = "straight", length = 380 },
			{ kind = "straight", length = 120, width = 460, height = 560 },
			{ kind = "mark", name = "room" },
			{ kind = "straight", length = 340 },
			{ kind = "straight", length = 150, rise = 250, width = 200, height = 170 },
			{ kind = "straight", length = 200 },
			{ kind = "straight", length = 700, rise = -250 },
			{ kind = "mark", name = "surf" },
			{ kind = "straight", length = 500 },
		},
		features = function(c)
			local room = c.mark("room")
			c.updraft(room - 80, 400, 26, 110, 150) -- la columna (a la derecha de la sala)
			c.guide(room + 20, 110, 20, 140, 140)
			c.point(room - 60, 90, 0)
			c.point(room + 60, 110, 60)
			c.point(room + 200, 110, 170)
			c.point(room + 290, 70, 240)
			c.barrier(room + 330, 230, 30) -- el borde del acantilado
			c.feathers(room + 520, room + 600, 3, 0, 15, 0, 15)
			c.feathers(1290, 1440, 3, -45, 0, -45, 0) -- la bajada, a un lado y a otro
			c.feathers(1560, 1710, 3, 45, 0, 45, 0)
			local surf = c.mark("surf")
			c.ridge(surf + 260, 10, 20, 25) -- rampa: el suelo te sube (inofensiva)
			c.feathers(surf + 240, surf + 280, 2, 0, 45, 0, 45)
		end,
	},
	{ -- 05 · Split Decision (prueba del capítulo) — el camino se divide. Calentamiento (viga + muro), bifurcación
		-- (carril alto: muros y plumas · carril bajo: vigas; los dos valen), S comprometida y dos ventanas en
		-- diagonal. Si dudáis, recto contra el morro del divisor. Final: "¡IZQUIERDA! NO, EL OTRO LADO."
		title = "Split Decision",
		tagline = "High road or low road?",
		width = 220,
		height = 170,
		path = {
			{ kind = "straight", length = 620 },
			{ kind = "straight", length = 150, width = 340 },
			{ kind = "mark", name = "fork" },
			{ kind = "straight", length = 820 },
			{ kind = "straight", length = 150, width = 220 },
			{ kind = "arc", angle = 50, radius = 160 },
			{ kind = "arc", angle = -50, radius = 160 },
			{ kind = "mark", name = "win" },
			{ kind = "straight", length = 700 },
		},
		features = function(c)
			c.lintel(300, 10, 35)
			c.barrier(580, 5, 35)
			local f = c.mark("fork")
			local lanes = c.divider(f + 60, f + 770, 0, 40, -1) -- A = izquierda (alto) · B = derecha (bajo)
			c.barrier(f + 280, 15, 35, lanes.A)
			c.barrier(f + 560, 25, 35, lanes.A)
			c.feathers(f + 330, f + 500, 3, lanes.A.u, 55, lanes.A.u, 62)
			c.lintel(f + 280, 15, 35, lanes.B)
			c.lintel(f + 560, 25, 35, lanes.B)
			local w = c.mark("win")
			c.window(w + 300, -45, 30, 120, 90) -- arriba-izquierda
			c.window(w + 560, 45, -30, 120, 90) -- abajo-derecha
		end,
	},

	-- ── Capítulo 2 · Cañón rojo (6-10): "El cañón empuja" ─────────────────────
	-- Las fuerzas y el tiempo: velocidad y espacio (6), viento lateral (7), troncos (8), corrientes que hunden (9)
	-- y la prueba (10), siempre combinados con lo del capítulo 1. El impulso (Espacio) se presenta en el 6.
	{ -- 06 · The Big Drop — la gran caída. El cañón se abre y la boca del túnel siguiente está 250 más abajo en
		-- una pared: hay que picar a tiempo ("¡TODO AL CENTRO!"). Túnel rasante (alto 64) con dos pilares
		-- ("¡quietos!"), muro para salir ("¡ARRIBA!") y subida con anillos: aquí se presenta el impulso.
		title = "The Big Drop",
		tagline = "Hold on tight",
		intro = "NEW: both hold SPACE = BOOST x2",
		width = 210,
		height = 170,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "straight", length = 100, width = 380, height = 420 },
			{ kind = "mark", name = "drop" },
			{ kind = "straight", length = 640, rise = -250 },
			{ kind = "straight", length = 2, width = 170, height = 64 },
			{ kind = "mark", name = "tunnel" },
			{ kind = "straight", length = 480 },
			{ kind = "straight", length = 60, width = 210, height = 170 },
			{ kind = "mark", name = "out" },
			{ kind = "straight", length = 150 },
			{ kind = "straight", length = 650, rise = 250 },
			{ kind = "straight", length = 200 },
		},
		features = function(c)
			local t = c.mark("tunnel")
			-- La boca del túnel: pared que tapa todo el cañón, con el hueco del túnel.
			c.window(t + 1, 0, 0, 150, 54, { halfW = 214, bottom = -240, top = 270 })
			c.pillar(t + 160, -40, 36, 1)
			c.pillar(t + 340, 40, 36, -1)
			local out = c.mark("out")
			c.barrier(out + 120, 15, 30)
			c.boostRing(out + 380, 0, 20)
			c.boostRing(out + 620, 0, 20)
			c.feathers(out + 700, out + 820, 3, 0, 25, 0, 25)
		end,
	},
	{ -- 07 · Crosswind — el viento empuja contra la pared. Slalom de salientes dentro de un viento lateral (a un
		-- lado cuesta más girar que al otro), viento contrario con una viga dentro (inclinarse y bajar a la vez) y
		-- final: ráfagas alternas ("¡CORRIGE!").
		title = "Crosswind",
		tagline = "Lean into it",
		width = 210,
		height = 170,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "mark", name = "w1" },
			{ kind = "straight", length = 640 },
			{ kind = "arc", angle = -35, radius = 220 },
			{ kind = "arc", angle = 35, radius = 220 },
			{ kind = "mark", name = "w2" },
			{ kind = "straight", length = 520 },
			{ kind = "mark", name = "g" },
			{ kind = "straight", length = 760 },
		},
		features = function(c)
			local w1 = c.mark("w1")
			c.crosswind(w1 - 60, 700, 1, 12) -- empuja a la derecha
			c.promontory(w1 + 130, 1, 80) -- el viento empuja hacia este
			c.promontory(w1 + 310, -1, 70)
			c.promontory(w1 + 490, 1, 80)
			c.feathers(w1 + 210, w1 + 240, 2, 15, 0, 15, 0)
			local w2 = c.mark("w2")
			c.crosswind(w2 + 30, 440, -1, 14) -- ahora a la izquierda, con una viga dentro
			c.lintel(w2 + 200, 12, 35)
			c.promontory(w2 + 400, -1, 60)
			c.gusts(c.mark("g") + 100, 5, 130, 80, 20, 1)
		end,
	},
	{ -- 08 · Swinging Logs — ¡espera… AHORA! Un tronco (por debajo siempre se pasa), tronco + muro (bajar y subir
		-- en seguida), dos troncos en contrafase y un tronco a la salida de una curva.
		title = "Swinging Logs",
		tagline = "Wait... NOW!",
		width = 210,
		height = 180,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "mark", name = "a" },
			{ kind = "straight", length = 1250 },
			{ kind = "arc", angle = 35, radius = 220 },
			{ kind = "arc", angle = -35, radius = 220 },
			{ kind = "mark", name = "b" },
			{ kind = "straight", length = 620 },
		},
		features = function(c)
			local a = c.mark("a")
			c.swingLog(a + 150, 10, 3.6)
			c.swingLog(a + 420, 10, 3.4, 0.3)
			c.barrier(a + 740, 5, 40) -- bajar bajo el tronco y subir: ~300 studs para un dúo nuevo
			c.swingLog(a + 980, 5, 3.6)
			c.swingLog(a + 1210, 5, 3.6, 0.5)
			c.feathers(a + 1070, a + 1110, 2, 0, -40, 0, -40)
			local b = c.mark("b")
			c.swingLog(b + 150, 10, 3.4, 0.2)
			c.barrier(b + 470, 0, 32)
		end,
	},
	{ -- 09 · Heavy Air — corrientes que hunden: hay que subir antes de lo que dice el instinto. Descendente antes
		-- de un muro, ascendente de alivio, descendente que ayuda a pasar bajo una viga y final con dos muros
		-- dentro de una descendente ("¡AGUANTAD FUERA!").
		title = "Heavy Air",
		tagline = "Read the air",
		width = 210,
		height = 180,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "mark", name = "a" },
			{ kind = "straight", length = 1650 },
			{ kind = "straight", length = 200 },
		},
		features = function(c)
			local a = c.mark("a")
			c.downdraft(a + 30, 330, 6)
			c.point(a + 170, 0, 35) -- la buena línea sube antes de lo que pide el muro
			c.barrier(a + 380, 5, 35)
			c.updraft(a + 540, 220, 12)
			c.feathers(a + 580, a + 720, 3, 0, 50, 0, 70)
			c.downdraft(a + 720, 240, 10) -- esta ayuda a meterse bajo la viga
			c.lintel(a + 900, 15, 35)
			c.point(a + 1150, 0, 0)
			c.downdraft(a + 1250, 450, 6) -- final: dos muros dentro de una descendente ("¡AGUANTAD FUERA!")
			c.barrier(a + 1400, 0, 32)
			c.barrier(a + 1640, 10, 40)
		end,
	},
	{ -- 10 · Canyon Trial (prueba del capítulo) — todo el cañón: caída con viga al fondo, viento + ventana,
		-- tronco, bifurcación con fuerzas (derecha: viento hacia el divisor y viga · izquierda: descendente y muro),
		-- ráfagas y ventana final.
		title = "Canyon Trial",
		tagline = "Everything the canyon has",
		width = 210,
		height = 170,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "straight", length = 100, height = 340 },
			{ kind = "mark", name = "drop" },
			{ kind = "straight", length = 380, rise = -170 },
			{ kind = "straight", length = 100, height = 170 },
			{ kind = "mark", name = "w" },
			{ kind = "straight", length = 520 },
			{ kind = "straight", length = 150, width = 330 },
			{ kind = "mark", name = "fork" },
			{ kind = "straight", length = 700 },
			{ kind = "straight", length = 150, width = 210 },
			{ kind = "mark", name = "g" },
			{ kind = "straight", length = 520, rise = 80 },
			{ kind = "mark", name = "fin" },
			{ kind = "straight", length = 380, rise = 90 }, -- recupera la altura de la caída
		},
		features = function(c)
			local w = c.mark("w")
			c.lintel(w + 40, 10, 35) -- al fondo de la caída
			c.crosswind(w + 140, 330, -1, 10)
			c.window(w + 330, 40, 25, 120, 90)
			c.swingLog(w + 430, 10, 3.4)
			local f = c.mark("fork")
			local lanes = c.divider(f + 120, f + 660, 0, 40, 1) -- A = derecha · B = izquierda
			c.crosswind(f + 160, 380, -1, 10, lanes.A.u, lanes.A.w)
			c.lintel(f + 450, 15, 35, lanes.A)
			c.downdraft(f + 160, 330, 6, lanes.B.u, lanes.B.w)
			c.point(f + 260, lanes.B.u, 25, "B", false) -- carril B: subir antes (la descendente hunde)
			c.barrier(f + 450, 5, 38, lanes.B)
			c.gusts(c.mark("g") + 80, 4, 130, 80, 16, -1)
			c.window(c.mark("fin") + 160, -40, -25, 115, 85)
		end,
	},

	-- ── Capítulo 3 · Bosque otoñal (11-15): "Ritmo" ─────────────────────────
	-- Practicar lo del capítulo 1 más rápido y combinado: girar subiendo y bajando (se mueve uno solo, y en cada
	-- nivel le toca a uno), compuertas que abren y cierran (nuevo: el impulso ayuda a llegar a tiempo) y
	-- combinaciones seguidas. 11 y 12 dan la vuelta al recorrido (90° + 90° a la izquierda): la fila siguiente
	-- vuelve hacia -X.
	{ -- 11 · Falling Leaves — la espiral que baja. 90° a la izquierda bajando en tres curvas, con ventanas abajo y
		-- por dentro: bajar girando a la izquierda lo hace el de la DERECHA (se mete al centro), el otro aguanta.
		-- Final: muro para salir de la espiral ("¡ahora los dos fuera!"), anillo y ventana abajo-derecha (le toca al otro).
		title = "Falling Leaves",
		tagline = "Spiral down together",
		width = 200,
		height = 170,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "mark", name = "a1" },
			{ kind = "arc", angle = 30, radius = 260, rise = -50 },
			{ kind = "straight", length = 160, rise = -20 },
			{ kind = "mark", name = "a2" },
			{ kind = "arc", angle = 30, radius = 260, rise = -50 },
			{ kind = "straight", length = 160, rise = -20 },
			{ kind = "mark", name = "a3" },
			{ kind = "arc", angle = 30, radius = 260, rise = -50 },
			{ kind = "mark", name = "out" },
			{ kind = "straight", length = 1070 },
		},
		features = function(c)
			local q = 260 * math.rad(30) / 2 -- media curva
			c.window(c.mark("a1") + q, -40, -25, 120, 90) -- abajo-izquierda: el derecho al centro
			c.feathers(c.mark("a1") + 2 * q + 30, c.mark("a1") + 2 * q + 130, 3, -30, -20, -30, -20)
			c.window(c.mark("a2") + q, -40, -25, 115, 88)
			c.window(c.mark("a3") + q, 0, -30, 120, 90) -- abajo, recto: los dos al centro
			local out = c.mark("out")
			c.barrier(out + 330, 5, 35) -- salir de la espiral
			c.boostRing(out + 580, 0, 25)
			c.window(out + 820, 40, -25, 120, 90) -- abajo-derecha: ahora el IZQUIERDO al centro
		end,
	},
	{ -- 12 · Thermals (RESPIRO) — el Chimney del bosque. Una sala enorme sobre el dosel otoñal: otros 90° a la
		-- izquierda subiendo 190 studs, pero las térmicas (anchas y fuertes) os suben solas. No hay muros: basta con
		-- meterse en la columna y abrirse, mirar el bosque y recoger las plumas que suben en espiral. Final: el anillo
		-- en lo alto de la última térmica.
		title = "Thermals",
		tagline = "Catch the rising air",
		kind = "breather",
		width = 380,
		height = 360,
		path = {
			{ kind = "straight", length = 360 },
			{ kind = "mark", name = "t1" },
			{ kind = "straight", length = 320, rise = 60 },
			{ kind = "arc", angle = 45, radius = 300 },
			{ kind = "mark", name = "t2" },
			{ kind = "straight", length = 320, rise = 60 },
			{ kind = "arc", angle = 45, radius = 300 },
			{ kind = "mark", name = "t3" },
			{ kind = "straight", length = 320, rise = 70 },
			{ kind = "mark", name = "fin" },
			{ kind = "straight", length = 330 },
			{ kind = "straight", length = 120, width = 210, height = 190 },
		},
		features = function(c)
			local t1, t2, t3 = c.mark("t1"), c.mark("t2"), c.mark("t3")
			-- Tres térmicas en la línea (a un lado, al otro y en medio): se entra con un toque y suben solas.
			-- Suben lo mismo que el camino (~11 studs/s): dentro de la columna no hay que hacer nada.
			for _, thermal in { { t1, -20 }, { t2, 20 }, { t3, 0 } } do
				local s0, u = thermal[1], thermal[2]
				c.updraft(s0 - 20, 340, 11, u, 220)
				c.feathers(s0 + 60, s0 + 280, 4, u - 25, 10, u + 25, 30)
			end
			-- Final: gran picado hasta rozar el dosel y subir al anillo ("¡uuuuh!").
			local fin = c.mark("fin")
			c.point(fin + 90, 0, -120, nil, false)
			c.feathers(fin + 70, fin + 130, 3, 0, -110, 0, -120)
			c.boostRing(fin + 260, 0, 0)
		end,
	},
	{ -- 13 · Forest Gates — compuertas (nuevo). Se abren y cierran; en el centro siempre queda hueco, pero más
		-- abierto si se llega a tiempo (el impulso ayuda: "¡a la vez, que se cierra!"). Compuerta + viga, dos
		-- compuertas desfasadas y una compuerta justo al salir de una S. Final: el doble ritmo.
		title = "Forest Gates",
		tagline = "Through the gaps, on time",
		intro = "NEW: gates open and close. Time it (or boost)!",
		width = 210,
		height = 170,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "mark", name = "a" },
			{ kind = "straight", length = 900 },
			{ kind = "arc", angle = 40, radius = 200 },
			{ kind = "arc", angle = -40, radius = 200 },
			{ kind = "mark", name = "b" },
			{ kind = "straight", length = 700 },
		},
		features = function(c)
			local a = c.mark("a")
			c.gate(a + 150, 95, nil, 4) -- presentar: hueco mínimo generoso
			c.gate(a + 430, 82, nil, 3.6, 0.3)
			c.lintel(a + 680, 10, 35)
			c.boostRing(a + 830, 0, 20)
			local b = c.mark("b")
			c.gate(b + 150, 80, nil, 3.6, 0.5) -- justo al salir de la S
			c.feathers(b + 220, b + 300, 3, 0, 0, 0, 0)
			c.gate(b + 380, 80, nil, 3.6, 0)
			c.barrier(b + 620, 5, 35)
		end,
	},
	{ -- 14 · Rollercoaster — todo a la vez. Pilar, viga, pilar, muro, rampa, ventana: cada ~4 s un gesto distinto
		-- (izquierda, abajo, derecha, arriba, surf, abajo-derecha). Final: la ventana tras la rampa y una S
		-- comprometida ("¡CAMBIO!").
		title = "Rollercoaster",
		tagline = "Up, down, left, right!",
		width = 230,
		height = 180,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "mark", name = "a" },
			{ kind = "straight", length = 1540 },
			{ kind = "arc", angle = 50, radius = 120 },
			{ kind = "arc", angle = -50, radius = 120 },
			{ kind = "straight", length = 220 },
		},
		features = function(c)
			local a = c.mark("a")
			c.pillar(a + 100, 40, 60, -1)
			c.lintel(a + 340, 10, 35)
			c.pillar(a + 570, -40, 60, 1)
			c.barrier(a + 860, 5, 35)
			c.ridge(a + 1110, 8, 20, 25) -- rampa: surf
			c.feathers(a + 1090, a + 1130, 2, 0, 45, 0, 45)
			c.window(a + 1360, 40, -25, 120, 90) -- abajo-derecha: el izquierdo al centro
			c.boostRing(a + 1480, 0, 20)
		end,
	},
	{ -- 15 · Autumn Trial (prueba del capítulo) — espiral abajo a la derecha y arriba a la izquierda (ventanas por
		-- dentro: primero trabaja uno y luego el otro), compuerta y pilar, bifurcación (carril alto: muro y viga ·
		-- bajo: viga y muro) y final con compuerta y ventana.
		title = "Autumn Trial",
		tagline = "Everything the forest taught",
		width = 220,
		height = 170,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "mark", name = "s1" },
			{ kind = "arc", angle = -40, radius = 240, rise = -45 },
			{ kind = "mark", name = "s2" },
			{ kind = "arc", angle = 40, radius = 240, rise = 45 },
			{ kind = "mark", name = "g" },
			{ kind = "straight", length = 560 },
			{ kind = "straight", length = 150, width = 340 },
			{ kind = "mark", name = "fork" },
			{ kind = "straight", length = 780 },
			{ kind = "straight", length = 150, width = 220 },
			{ kind = "mark", name = "fin" },
			{ kind = "straight", length = 560 },
		},
		features = function(c)
			local q = 240 * math.rad(40) / 2
			c.window(c.mark("s1") + q, 40, -25, 120, 90) -- abajo-derecha (girando a la derecha): el izquierdo al centro
			c.window(c.mark("s2") + q, -40, 25, 120, 90) -- arriba-izquierda: el izquierdo fuera
			local g = c.mark("g")
			c.gate(g + 170, 85, nil, 3.8, 0.2)
			c.pillar(g + 420, -40, 60, 1)
			local f = c.mark("fork")
			local lanes = c.divider(f + 60, f + 720, 0, 40, -1) -- A = izquierda · B = derecha
			c.barrier(f + 260, 10, 35, lanes.A)
			c.lintel(f + 580, 15, 35, lanes.A)
			c.lintel(f + 260, 15, 35, lanes.B)
			c.barrier(f + 580, 5, 35, lanes.B)
			c.boostRing(f + 420, lanes.B.u, 0)
			local fin = c.mark("fin")
			c.gate(fin + 150, 82, nil, 3.6, 0.4)
			c.window(fin + 390, 40, 25, 115, 88) -- arriba-derecha: el derecho fuera
		end,
	},

	-- ── Capítulo 4 · Mesetas del desierto (16-20): "Aire y espacio" ─────────────
	-- Salas abiertas y mucha altura: columnas ascendentes para subir mesetas, voladizos para volver a bajar, aspas
	-- (nuevo: las esquinas siempre libres), horquillas cerradas en las que cada vez trabaja uno, y la tormenta
	-- (viento y descendentes mientras se apunta a ventanas).
	{ -- 16 · Mesa Hop (RESPIRO) — de meseta en meseta. Una sala enorme con tres mesetas cada vez más altas: cada
		-- columna ascendente (ancha, casi en el centro) os sube sola por encima de la siguiente, y después se planea
		-- bajando hasta la próxima. Sin voladizos ni precisión: mirar el desierto y recoger las plumas de las cimas.
		title = "Mesa Hop",
		tagline = "From mesa to mesa",
		kind = "breather",
		width = 220,
		height = 180,
		path = {
			{ kind = "straight", length = 200 },
			{ kind = "straight", length = 100, width = 380, height = 400 },
			{ kind = "mark", name = "a" },
			{ kind = "straight", length = 1900 },
			{ kind = "straight", length = 120, width = 220, height = 180 },
			{ kind = "straight", length = 230 },
		},
		features = function(c)
			local a = c.mark("a")
			for _, mesa in { { 0, 0, 40 }, { 640, 0, 55 }, { 1280, 0, 70 } } do
				local s0, u, reach = a + mesa[1], mesa[2], mesa[3]
				c.updraft(s0 + 40, 340, 13, u, 220)
				c.barrier(s0 + 420, reach, 40)
				c.feathers(s0 + 400, s0 + 440, 2, 0, reach + 45, 0, reach + 45)
			end
			-- La línea ideal va en escalera por encima de las mesetas (sin bajar entre una y otra): sube dentro de
			-- cada columna y se planea arriba hasta la siguiente. Puntos cada 100 para que no la rellene el centro.
			local tops = { { 0, 0 }, { 420, 80 }, { 680, 80 }, { 1060, 95 }, { 1320, 95 }, { 1700, 110 }, { 1900, 40 } }
			for k = 1, #tops - 1 do
				local s0, v0, s1, v1 = tops[k][1], tops[k][2], tops[k + 1][1], tops[k + 1][2]
				for d = s0 + 100, s1, 100 do
					c.point(a + d, 0, v0 + (v1 - v0) * (d - s0) / (s1 - s0), nil, false)
				end
			end
			c.boostRing(a + 1900, 0, 40) -- la bajada larga hacia la salida
		end,
	},
	{ -- 17 · Dust Devils — aspas (nuevo). Giran alrededor del eje del corredor y las esquinas de abajo siempre
		-- quedan libres: abajo-derecha (el izquierdo al centro) o abajo-izquierda (el derecho al centro); el centro,
		-- solo con el tiempo justo. Entre aspa y aspa, volver arriba por una ventana central. Final: el aspa rápida.
		title = "Dust Devils",
		tagline = "Pick the free corner",
		intro = "NEW: spinning blades. The corners stay clear!",
		width = 220,
		height = 200,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "mark", name = "a" },
			{ kind = "straight", length = 1700 },
			{ kind = "arc", angle = 25, radius = 300 },
			{ kind = "arc", angle = -25, radius = 300 },
			{ kind = "straight", length = 200 },
		},
		features = function(c)
			local a = c.mark("a")
			c.spinner(a + 150, 2, 5, 1) -- esquina abajo-derecha
			c.window(a + 460, 0, 10, 130, 100) -- volver al centro
			c.spinner(a + 820, 2, 5, -1, 0.3, 0.55, 38) -- esquina abajo-izquierda
			c.feathers(a + 950, a + 1000, 2, 0, 0, 0, 0)
			c.window(a + 1060, 0, 10, 130, 100)
			c.spinner(a + 1460, 2, 3.6, 1, 0.1, 0.55, 38) -- final: el aspa rápida
			c.boostRing(a + 1620, 0, 20)
		end,
	},
	{ -- 18 · Slot Canyon — la ranura. La sala de mesetas acaba en una pared gigante con una grieta de 50 × 42 (el ala
		-- mide 32): "¿¿por AHÍ??". Dentro, curvas suaves (un toque), un falso respiro (se ensancha a 120…) y la
		-- segunda ranura, aún más estrecha y con curvas que suben y bajan (cada una la hace uno solo). Las paredes
		-- son de arenisca: un roce rebota ("BOING!") y frena sin daño; un golpe de frente o tres rebotes seguidos
		-- cuestan un corazón. Final: la ranura revienta en un cañón enorme.
		title = "Slot Canyon",
		tagline = "Suck it in!",
		intro = "NEW: it's a tight fit... sandstone walls bounce you!",
		width = 220,
		height = 180,
		path = {
			{ kind = "straight", length = 90 },
			{ kind = "straight", length = 100, width = 360, height = 380 },
			{ kind = "straight", length = 130 },
			{ kind = "straight", length = 2, width = SLOT.width, height = SLOT.height, wall = "Sandstone" },
			{ kind = "mark", name = "slot1" },
			{ kind = "straight", length = 110, wall = "Sandstone" },
			{ kind = "arc", angle = 22, radius = 340, wall = "Sandstone" },
			{ kind = "arc", angle = -44, radius = 340, wall = "Sandstone" },
			{ kind = "arc", angle = 22, radius = 340, wall = "Sandstone" },
			{ kind = "straight", length = 50, wall = "Sandstone" },
			{ kind = "straight", length = 40, width = 120, height = 90, wall = "Sandstone" },
			{ kind = "mark", name = "relief" },
			{ kind = "straight", length = 110, wall = "Sandstone" },
			{ kind = "straight", length = 40, width = SLOT.narrow, height = SLOT.height, wall = "Sandstone" },
			{ kind = "mark", name = "slot2" },
			{ kind = "arc", angle = 30, radius = 250, rise = 22, wall = "Sandstone" },
			{ kind = "arc", angle = -60, radius = 250, wall = "Sandstone" },
			{ kind = "arc", angle = 30, radius = 250, rise = -22, wall = "Sandstone" },
			{ kind = "straight", length = 70, wall = "Sandstone" },
			{ kind = "mark", name = "burst" },
			{ kind = "straight", length = 2, width = 380, height = 400 },
			{ kind = "mark", name = "out" },
			{ kind = "straight", length = 240 },
			{ kind = "straight", length = 120, width = 220, height = 180 },
			{ kind = "straight", length = 100 },
		},
		features = function(c)
			local slot1 = c.mark("slot1")
			-- La pared gigante con la grieta y el cartel.
			c.window(slot1 - 1, 0, 0, SLOT.width, SLOT.height, { halfW = 184, bottom = -200, top = 200 })
			c.sign(slot1 - 3, 0, SLOT.height / 2 + 34, 90, 22, "⚠ 56 STUDS", Color3.fromRGB(255, 200, 60))
			-- Línea ideal densa por el centro de la ranura (sin avisos: la ranura ya es el aviso).
			for s = slot1 + 20, c.mark("burst") - 10, 30 do
				c.point(s, 0, 0, nil, false)
			end
			c.feathers(c.mark("relief") + 20, c.mark("relief") + 90, 3, 0, 0, 0, 0)
			-- La salida: la ranura revienta en el cañón.
			local burst = c.mark("burst")
			c.window(burst + 1, 0, 0, SLOT.narrow, SLOT.height, { halfW = 194, bottom = -210, top = 210 })
			c.boostRing(c.mark("out") + 110, 0, 30)
			c.feathers(c.mark("out") + 170, c.mark("out") + 260, 3, 0, 40, 0, 20)
		end,
	},
	{ -- 19 · Sandstorm — la tormenta. Viento lateral mientras se apunta a ventanas (una contra el viento, otra a
		-- favor: cuidado con pasarse), descendente antes de un muro y ráfagas. Final: ventana abajo tras la curva.
		title = "Sandstorm",
		tagline = "Aim through the storm",
		width = 220,
		height = 180,
		path = {
			{ kind = "straight", length = 250 },
			{ kind = "mark", name = "a" },
			{ kind = "straight", length = 1400 },
			{ kind = "arc", angle = -35, radius = 170 },
			{ kind = "arc", angle = 35, radius = 170 },
			{ kind = "mark", name = "b" },
			{ kind = "straight", length = 520 },
		},
		features = function(c)
			local a = c.mark("a")
			c.crosswind(a - 150, 810, 1, 11) -- empuja a la derecha desde la entrada
			c.window(a + 120, -40, 25, 120, 90) -- arriba-izquierda, contra el viento
			c.window(a + 470, 40, -25, 120, 90) -- abajo-derecha, a favor (no pasarse)
			c.downdraft(a + 720, 380, 7)
			c.point(a + 820, 0, 25) -- subir antes: la descendente hunde
			c.barrier(a + 1000, 5, 35)
			c.gusts(a + 1130, 4, 110, 80, 18, -1)
			c.window(c.mark("b") + 200, 0, -30, 120, 90)
			c.boostRing(c.mark("b") + 380, 0, 15)
		end,
	},
	{ -- 20 · Mesa Run (prueba del capítulo) — meseta con columna y voladizo, dos horquillas, aspa, bifurcación
		-- (izquierda: viga y muro · derecha: viento hacia el divisor y muro) y final con compuerta y ventana.
		title = "Mesa Run",
		tagline = "The whole desert",
		width = 220,
		height = 180,
		path = {
			{ kind = "straight", length = 200 },
			{ kind = "straight", length = 100, width = 360, height = 380 },
			{ kind = "mark", name = "m" },
			{ kind = "straight", length = 820 },
			{ kind = "straight", length = 120, width = 220, height = 180 },
			{ kind = "straight", length = 150 },
			{ kind = "arc", angle = 60, radius = 170 },
			{ kind = "arc", angle = -60, radius = 170 },
			{ kind = "mark", name = "s" },
			{ kind = "straight", length = 450 },
			{ kind = "straight", length = 150, width = 370 },
			{ kind = "mark", name = "fork" },
			{ kind = "straight", length = 720 },
			{ kind = "straight", length = 150, width = 220 },
			{ kind = "mark", name = "fin" },
			{ kind = "straight", length = 700 },
		},
		features = function(c)
			local m = c.mark("m")
			c.updraft(m + 40, 290, 20, -50, 130)
			c.point(m + 100, -50, 10)
			c.barrier(m + 380, 70, 35)
			c.lintel(m + 720, -30, 35)
			c.spinner(c.mark("s") + 340, 2, 5, -1, 0.2, 0.55, 40) -- esquina abajo-izquierda (aspas cortas: más margen)
			local f = c.mark("fork")
			local lanes = c.divider(f + 60, f + 660, 0, 40, -1) -- A = izquierda · B = derecha
			c.lintel(f + 250, 15, 35, lanes.A)
			c.barrier(f + 570, 5, 35, lanes.A)
			c.crosswind(f + 100, 380, -1, 10, lanes.B.u, lanes.B.w) -- empuja hacia el divisor
			c.barrier(f + 330, 10, 35, lanes.B)
			local fin = c.mark("fin")
			c.gate(fin + 220, 100, nil, 3.8, 0.1)
			c.window(fin + 570, -40, 25, 115, 88)
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
			c.crosswind(c.mark("mid") + 30, 250, -1, 8)
			c.lintel(c.mark("mid") + 400, 10)
			c.feathers(c.mark("mid") + 480, c.mark("mid") + 640, 3, 30, 0, 30, 0)
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
			c.updraft(a + 350, 250, 10)
			c.feathers(a + 380, a + 560, 4, 0, 40, 0, 60)
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
			-- Aspas (nuevo): las esquinas quedan siempre libres; el centro hay que cronometrarlo.
			c.spinner(a + 1480, 2, 5, 1)
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
			c.promontory(300 + q / 2, -1, 60)
			c.promontory(300 + q + 150 + q, 1, 66)
			c.promontory(300 + q + 150 + 2 * q + 150 + q, -1, 66)
			c.promontory(300 + q + 150 + 2 * q + 150 + 2 * q + 150 + q / 2, 1, 60)
			c.feathers(150, 280, 3, 0, 0, 0, 0)
			c.boostRing(300 + q + 150 + 2 * q + 75, 0, 0)
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
			{ kind = "mark", name = "narrow" },
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
			c.promontory(b + q / 2, 1, 45)
			c.promontory(b + q + q / 2, -1, 45)
			c.spinner(c.mark("narrow") + 250, 2, 5.5, -1, 0.25, 0.5)
			c.feathers(a + 300, a + 420, 3, 0, -40, 0, -40)
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

-- ── Tutorial: FLIGHT SCHOOL (nivel 0, ~40 s) ─────────────────────────────
-- Un solo corredor continuo, sin valles: bajar → subir → izquierda → cambio a la derecha → combo sin ayudas.
-- Cada concepto tiene su situación justo después de presentarlo. Es el principio del recorrido: desemboca en el
-- valle de la StartIsland, justo antes del nivel 1. Los dúos con alguien nuevo despegan aquí; los veteranos, en la
-- StartIsland. Va en Map.Tutorial (su propio recorrido para los checkpoints: la "meta" es la línea de relevo en
-- el despegue de los veteranos, y al cruzarla empieza el recorrido de verdad sin cortes).
-- coach = indicaciones por tramo, en fracciones de la Route: { from, to, texto, acción } (acción 1 = marcas
-- fantasma en la barra del HUD: dónde ponerse cada uno). Texto: una o dos palabras.
local TUTORIAL_LAUNCH_S = 420 -- despegue a 180 studs de la boca: la primera acción llega enseguida
local TUTORIAL_LEVELS = {
	{
		title = "Flight School",
		tagline = "Two riders, one wing",
		biome = "Pradera",
		width = 260,
		height = 180,
		path = {
			{ kind = "straight", length = 480 },
			{ kind = "straight", length = 420 },
			{ kind = "straight", length = 150 },
			{ kind = "arc", angle = 75, radius = 150 },
			{ kind = "straight", length = 60 },
			{ kind = "arc", angle = -75, radius = 150 },
			{ kind = "mark", name = "combo" },
			{ kind = "straight", length = 500 },
			{ kind = "arc", angle = 50, radius = 130 },
			{ kind = "arc", angle = -50, radius = 130 },
			{ kind = "straight", length = 120 },
		},
		features = function(c)
			c.lintel(380, 25, 40) -- BAJAR: puente bajo con el hueco abajo
			c.barrier(800, 20, 40) -- SUBIR: muro justo detrás
			local combo = c.mark("combo")
			c.lintel(combo + 150, 0, 38) -- COMBO: viga, muro y una S, sin ayudas
			c.barrier(combo + 480, -5, 38)
		end,
		coach = {
			{ 0, 0.16, "DIVE!", 1 },
			{ 0.16, 0.34, "CLIMB!", 1 },
			{ 0.34, 0.43, "", 1 },
			{ 0.43, 0.52, "LEFT!", 1 },
			{ 0.52, 0.62, "SWAP RIGHT!", 1 },
			{ 0.62, 0.7, "Your turn!", 0 },
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
			-- Primer nivel de un capítulo (solo en el recorrido principal): puerta de capítulo en la entrada.
			local chapter = if options.chapters and model.Name:match("^Level") and (index - 1) % Biomes.CHAPTER_LENGTH == 0 then (index - 1) // Biomes.CHAPTER_LENGTH + 1 else nil
			local added = MapDresser.dress(model, biome, { wallT = WALL_T, rim = RIM, seed = options.seedBase + index * 7919 + #model.Name, index = index, chapter = chapter })
			table.insert(dressed, string.format("%s +%d", model.Name, added))
		end
	end

	local devSpawns = newFolder(root, "DevSpawns")
	local summary = {}

	-- Valle inicial: acantilado cerrado detrás, StartIsland y despegue en su borde.
	local startLength = options.startLength or VALLEY.length
	local startFrames = tracePath(startPos, 0, VALLEY.width, 0, { { kind = "straight", length = startLength } })
	local start = buildValley(root, "StartIsland", startFrames)
	if not options.noBackWall then
		cliffFace(start, "BackWall", startFrames[1], nil, VALLEY_EXTENTS) -- (sin ella: por detrás llega Flight School)
	end
	local launch = frameAt(startFrames, options.launchS or LAUNCH_S)
	-- En el recorrido principal, los dúos que vienen de Flight School pasan por encima de esta isla: algo más baja.
	local islandDrop = if options.noBackWall then 24 else 14
	island(start, launch.pos - Vector3.new(0, islandDrop, 0) - forwardOf(0) * 115, 0, 230, 280, BEACON_COLORS[1], startPos.Y)
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
	local total = startLength
	for index, spec in levels do
		local levelName = string.format("Level%02d", index)
		-- Corredores más ajustados donde toca (options.scaleFor): ancho y alto de la sección, también en las
		-- órdenes del trazado que los cambian.
		local scale = if options.scaleFor then options.scaleFor(index) else 1
		local path = spec.path
		if scale ~= 1 then
			path = {}
			for _, command in spec.path do
				local copy = table.clone(command)
				copy.width = command.width and command.width * scale
				copy.height = command.height and command.height * scale
				table.insert(path, copy)
			end
		end
		local frames, marks = tracePath(cursor.pos, cursor.heading, spec.width * scale, spec.height * scale, path)
		local first, last = frames[1], frames[#frames]
		local level = newModel(root, levelName)
		level:SetAttribute("Title", spec.title)
		level:SetAttribute("Tagline", spec.tagline) -- frase de identidad (tarjeta de título del HUD)
		level:SetAttribute("Intro", spec.intro) -- aviso de algo nuevo al empezar el nivel (p. ej. el impulso)
		level:SetAttribute("LevelKind", spec.kind or "technical") -- "breather" = nivel de respiro (docs/DISENO_NIVELES.md)
		for _, command in spec.path do
			if command.wall then
				level:SetAttribute("Tight", true) -- ranura (FlightTester.TIGHT_RULE)
			end
		end
		level:SetAttribute("Length", math.floor(last.s))
		level:SetAttribute("Width", spec.width * scale)
		level:SetAttribute("Height", spec.height * scale)
		if spec.coach then
			-- Indicaciones de Flight School (FlightSchool.cuesOf): "desde|hasta|lado|texto;…" (fracciones de la Route).
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

		local ctx = makeContext(level, frames, marks, scale)
		spec.features(ctx)
		local chapterExtras = if options.chapters then CHAPTER_EXTRAS[(index - 1) // 5 + 1] else nil
		if chapterExtras then
			ctx.autoExtras(chapterExtras, spec.extraCount or 3, spec.skipExtras)
		end
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
			-- Corto dentro del capítulo; largo al cambiar de capítulo y en mitad de los giros de 180° entre filas
			-- (11-12, 21-22, 31-32, 41-42: si no, las filas vecinas quedarían demasiado cerca).
			local turnPair = index % 10 == 1 and index > 10
			local valleyLength = if options.chapters and index % Biomes.CHAPTER_LENGTH ~= 0 and not turnPair then SHORT_VALLEY else VALLEY.length
			local valleyFrames = tracePath(last.pos, last.heading, VALLEY.width, 0, { { kind = "straight", length = valleyLength } })
			local rest = buildValley(root, string.format("RestIsland%02d", index), valleyFrames)
			rest:SetAttribute("Index", index)
			local middle = frameAt(valleyFrames, valleyLength / 2)
			island(rest, middle.pos - Vector3.new(0, 60, 0), middle.heading, 200, 220, BEACON_COLORS[(index - 1) % #BEACON_COLORS + 1], middle.pos.Y)
			dressModel(rest, index, index + 1)
			cursor = valleyFrames[#valleyFrames]
			total += valleyLength
		elseif options.handoff then
			-- Relevo (Flight School): la "meta" es una línea en el despegue de los veteranos, dentro del valle de la
			-- StartIsland del recorrido principal. Sin geometría propia: se sigue volando hacia el nivel 1.
			local finish = newModel(root, "FinishIsland")
			marker(finish, "CheckpointZone", options.handoff, Vector3.new(VALLEY.width - 60, 400, 40))
			marker(finish, "FinishLine", options.handoff, Vector3.new(VALLEY.width - 60, 400, 4))
			marker(devSpawns, "Finish", options.handoff * CFrame.new(0, 0, 150))
		else
			local finishFrames = tracePath(last.pos, last.heading, VALLEY.width, 0, { { kind = "straight", length = 900 } })
			local finish = buildValley(root, "FinishIsland", finishFrames)
			local gate = frameAt(finishFrames, 150)
			ring(finish, "FinishGate", "Finish", frameCFrame(gate), 170, 120, 10, 10)
			marker(finish, "FinishLine", frameCFrame(gate), Vector3.new(170, 120, 4))
			-- Cartel FINISH sobre el arco (visual).
			local sign = newPart(finish, "FinishSign", "Finish", Vector3.new(130, 26, 2), frameCFrame(gate) * CFrame.new(0, 60 + 10 + 18, 0))
			sign.Color = Color3.fromRGB(25, 40, 30)
			sign.Material = Enum.Material.SmoothPlastic
			local signGui = Instance.new("SurfaceGui")
			signGui.Face = Enum.NormalId.Back -- mira hacia el ala que llega
			signGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			signGui.PixelsPerStud = 8
			signGui.LightInfluence = 0
			signGui.Parent = sign
			local signText = Instance.new("TextLabel")
			signText.BackgroundTransparency = 1
			signText.Size = UDim2.fromScale(1, 1)
			signText.Font = Enum.Font.GothamBlack
			signText.TextScaled = true
			signText.TextColor3 = COLORS.Finish
			signText.Text = "FINISH"
			signText.Parent = signGui
			local landing = frameAt(finishFrames, 480)
			island(finish, landing.pos - Vector3.new(0, 70, 0), landing.heading, 420, 360, COLORS.Finish, landing.pos.Y)
			-- Techo de aterrizaje: baja hasta la isla y guía el ala hacia ella (tocar la isla termina el recorrido).
			-- Invisible: se roza como un techo, pero lo que se ve es la pista de aterrizaje.
			local a = frameAt(finishFrames, 170).pos + Vector3.new(0, 60, 0)
			local b = frameAt(finishFrames, 460).pos + Vector3.new(0, -58, 0)
			local guide = newPart(finish, "LandingCeiling", "Cliff", Vector3.new(360, SLAB_T, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b))
			guide.Transparency = 1
			guide.CastShadow = false
			cliffFace(finish, "EndWall", finishFrames[#finishFrames], nil, VALLEY_EXTENTS)
			dressModel(finish, index, index)
			-- Pista de aterrizaje sobre la isla (visual): franja clara y chevrones hacia delante.
			local pad = CFrame.lookAt(landing.pos - Vector3.new(0, 70 - 0.3, 0), landing.pos - Vector3.new(0, 70 - 0.3, 0) + forwardOf(landing.heading))
			local strip = newPart(finish, "LandingStrip", "Finish", Vector3.new(70, 0.4, 300), pad)
			strip.Color = Color3.fromRGB(245, 250, 245)
			strip.Transparency = 0.35
			for k = -1, 1 do
				for _, side in { -1, 1 } do
					newPart(finish, "LandingChevron", "Finish", Vector3.new(26, 0.5, 4), pad * CFrame.new(side * 9, 0.2, k * 80) * CFrame.Angles(0, -side * math.rad(35), 0)) -- extremos interiores delante: apunta hacia delante
				end
			end
			marker(devSpawns, "Finish", CFrame.lookAt(gate.pos - forwardOf(gate.heading) * 150, gate.pos))
			total += 900
		end
	end
	return summary, total, dressed
end

-- Genera Workspace.Map: el recorrido principal (50 niveles) y, dentro, Map.Tutorial.
-- options.dress = false → blockout puro.
local buildMap -- más abajo

-- Construye el mapa sin tocar el viejo: el viejo solo se borra si el nuevo termina bien. Si algo falla, se
-- deja el mapa anterior como estaba y se muestra el error.
function MapBuilder.build(options): string
	local old = workspace:FindFirstChild("Map")
	if old then
		old.Name = "MapOld"
	end
	local ok, result = pcall(buildMap, options)
	if not ok then
		local partial = workspace:FindFirstChild("Map")
		if partial and partial ~= old then
			partial:Destroy()
		end
		if old then
			old.Name = "Map"
		end
		error("MapBuilder.build falló; se conserva el mapa anterior: " .. tostring(result), 0)
	end
	if old then
		old:Destroy()
	end
	return result
end

function buildMap(options): string
	local dress = not (options and options.dress == false)
	local map = Instance.new("Folder")
	map.Name = "Map"
	map:SetAttribute("DevStartLevel", 0) -- 1-50 = despegar directamente en ese nivel (pruebas)
	map.Parent = workspace

	local summary, total, dressed = buildCourse(map, LEVELS, START, {
		dress = dress,
		dressUpTo = DRESS_LEVELS,
		seedBase = 20260922,
		moveTemplate = true,
		chapters = true,
		startLength = START_LENGTH,
		noBackWall = true,
		scaleFor = function(index)
			return if index >= 21 and index <= 25 then CORRIDOR_SCALE else 1 -- capítulo 5 (1-20 ya van ajustados)
		end,
	})

	local tutorial = Instance.new("Folder")
	tutorial.Name = "Tutorial"
	tutorial.Parent = map
	-- Flight School va justo detrás del valle inicial: su salida coincide con el comienzo de la StartIsland.
	local school = TUTORIAL_LEVELS[1]
	local schoolFrames = tracePath(Vector3.zero, 0, school.width, school.height, school.path)
	local schoolExit = schoolFrames[#schoolFrames]
	assert(math.abs(schoolExit.heading) < 1e-6, "Flight School tiene que acabar con el mismo rumbo con el que empieza")
	local tutorialStart = START - Vector3.new(VALLEY.length, 0, 0) - schoolExit.pos
	local handoff = CFrame.lookAt(START + Vector3.new(LAUNCH_S, 0, 0), START + Vector3.new(LAUNCH_S + 1, 0, 0))
	local tutorialSummary, tutorialTotal = buildCourse(tutorial, TUTORIAL_LEVELS, tutorialStart, { dress = dress, dressUpTo = math.huge, seedBase = 7310, moveTemplate = false, launchS = TUTORIAL_LAUNCH_S, handoff = handoff })

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
