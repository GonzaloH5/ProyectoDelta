--!nonstrict
-- MapDresser: "viste" un modelo del blockout (nivel, valle o isla) con un bioma de Biomes. Solo modo edición.
-- MapBuilder lo llama al generar; no se usa a mano. Todo lo que añade va a la carpeta "Dressing" del modelo
-- y lleva el atributo Dressing = true.
--
-- Lee las piezas del blockout por su atributo Kind (Cliff, Ground, Ceiling, Obstacle, Guide…), así que no
-- depende de cómo se construyó el tubo. El trazado, los anchos y los obstáculos NO cambian.
--
-- REGLA DE ORO: lo que se ve sólido, choca (y al revés). El ala choca con toda pieza con CanQuery.
--   · Piel sólida (collidable): estratos y facetas pegados a paredes y obstáculos, sobresalen ≤ SKIN_MAX.
--     Rocas y arbustos del suelo del corredor: solo junto a las paredes, ≤ FLOOR_PROP_MAX de alto.
--   · Solo visual (sin colisión ni consultas): nubes del techo, manchas del suelo, agua, líneas de peligro.
--   · Fuera del volumen de vuelo (encima de los muros, fondo de los valles): sin límites.
-- MapDresser.audit(level) mide cuánto invade el vestido sólido respecto al blockout.

local LowPoly = require(game:GetService("ServerScriptService").Glider.DevTools.LowPoly:Clone())

local MapDresser = {}

MapDresser.SKIN_MAX = 4 -- studs que la piel sólida puede sobresalir de paredes y obstáculos
MapDresser.FLOOR_PROP_MAX = 12 -- alto máximo de rocas/arbustos en el suelo de los corredores

local SKIN = MapDresser.SKIN_MAX
local BAND = 28 -- alto de cada estrato. Van por Y del MUNDO: son horizontales y siguen de pieza en pieza.
local WALL_STRIP = 20 -- franja del suelo junto a cada pared donde puede haber rocas y arbustos
local ISLAND_MAX_DEPTH = 160 -- la isla grande de la meta no llega al fondo del valle: sigue flotando
local PROMONTORY_GROW = 0.7 -- ver obstacle(): la arista del saliente avanza ≤ 3 × 0.7 × √2 ≈ 3 studs
local WALL_FOOT = 30 -- buildTube baja las paredes 30 studs por debajo del suelo
-- Caras de acantilado: qué lado (+Z / -Z local) se ve. La entrada se ve desde el valle anterior (+Z).
local FACE_SIDES = { EntranceFace = { 1 }, ExitFace = { -1 }, BackWall = { 1, -1 }, EndWall = { 1 } }

local rgb = Color3.fromRGB
local STYLE = {
	Cloud = { visual = true, noShadow = true },
	Flower = { visual = true },
	Patch = { visual = true, noShadow = true },
	Hazard = { neon = true, visual = true },
	GuideGem = { neon = true, visual = true },
	ArchGem = { neon = true, visual = true },
	Water = { neon = true, transparency = 0.35, visual = true },
	Foam = { transparency = 0.3, visual = true },
	Lamp = { neon = true },
	CrystalTip = { neon = true },
	Ember = { neon = true },
}

local function palette(biome)
	return {
		Grass = biome.cap,
		Cap = biome.cap,
		Rock = biome.rock[2],
		RockDark = biome.rockDark,
		Strata = biome.rock[2],
		Facet = biome.rockDark,
		Patch = biome.patches[1],
		Trunk = biome.trunk,
		Leaf = biome.leaves[1],
		Cactus = biome.cactus,
		Bush = biome.bush,
		Flower = biome.flowers[1],
		WoodDark = biome.stoneDark,
		Lamp = rgb(255, 205, 120),
		Cloud = biome.cloud,
		Stone = biome.stone,
		Sign = biome.stoneDark,
		Hazard = biome.hazardEdge,
		GuideGem = biome.guide,
		ArchGem = biome.accent,
		Water = biome.water,
		Foam = rgb(230, 248, 255),
		Tower = rgb(248, 245, 238),
		Stripe = biome.accent,
		Crystal = biome.leaves[1],
		CrystalTip = biome.blossoms[1],
		Ember = biome.water,
	}
end

-- Colores de los arbustos (bolas): los del bioma o, si no tiene, los de las hojas.
local function bushColors(biome): { Color3 }
	return biome.bushes or biome.leaves
end

-- Planta grande del bioma, según biome.flora: árbol (hojas o, con blossomChance, flor), cactus, pino,
-- palmera, cristales o árbol calcinado.
local function plant(ctx, parent, base: CFrame, scale: number, blossomChance: number)
	local rng, biome = ctx.rng, ctx.biome
	local flora = biome.flora or { "tree" }
	local kind = if #flora > 1 then flora[rng:NextInteger(1, #flora)] else flora[1]
	-- Ojo: árbol y cactus sacan del rng exactamente lo mismo que antes (el vestido de los biomas que ya
	-- existían no cambia); los tipos nuevos sacan su color aquí.
	if kind == "cactus" then
		local bloom = if rng:NextNumber() < 0.35 then biome.blossoms[rng:NextInteger(1, #biome.blossoms)] else nil
		return ctx.kit.cactus(parent, base, scale * 0.9, bloom)
	elseif kind == "pine" then
		return ctx.kit.pine(parent, base, scale, biome.leaves[rng:NextInteger(1, #biome.leaves)], biome.snow)
	elseif kind == "palm" then
		return ctx.kit.palm(parent, base, scale, biome.leaves[rng:NextInteger(1, #biome.leaves)])
	elseif kind == "crystal" then
		local color = biome.leaves[rng:NextInteger(1, #biome.leaves)]
		return ctx.kit.crystal(parent, base, scale, color, biome.blossoms[rng:NextInteger(1, #biome.blossoms)])
	elseif kind == "deadtree" then
		return ctx.kit.deadTree(parent, base, scale, if rng:NextNumber() < 0.6 then biome.water else nil)
	end
	local color = if blossomChance > 0 and rng:NextNumber() < blossomChance
		then biome.blossoms[rng:NextInteger(1, #biome.blossoms)]
		else biome.leaves[rng:NextInteger(1, #biome.leaves)]
	return ctx.kit.tree(parent, base, scale, color)
end

-- ── Piel de roca ──────────────────────────────────────────────────────

-- Recorre la pieza en tramos horizontales de BAND studs (en Y del mundo); los tramos pares son estrato
-- y sobresalen 1-3 studs. visit(y0, y1, out) recibe cada tramo en coordenadas locales (out = 0 si no hay estrato).
-- trimBottom/trimTop recortan la zona recorrida (studs desde abajo/arriba) cuando parte de la pieza no se ve.
local function eachBand(part: BasePart, visit: (number, number, number, number) -> (), trimBottom: number?, trimTop: number?)
	local centerY = part.Position.Y
	local bottom = centerY - part.Size.Y / 2 + (trimBottom or 0)
	local top = centerY + part.Size.Y / 2 - (trimTop or 0)
	for k = math.floor(bottom / BAND), math.floor(top / BAND) do
		local y0, y1 = math.max(k * BAND, bottom), math.min((k + 1) * BAND, top)
		if y1 - y0 < 0.5 then
			continue
		end
		local out = if k % 2 == 0 then 1 + (k // 2) % 3 else 0
		visit(y0 - centerY, y1 - centerY, out, k // 2)
	end
end

-- Estratos sobre una cara vertical de la pieza: axis "X" o "Z", side = +1 / -1 (qué cara).
local function strata(ctx, parent, part: BasePart, axis: string, side: number, trimBottom: number?, trimTop: number?)
	local cf, size = part.CFrame, part.Size
	local face = if axis == "X" then size.X / 2 else size.Z / 2
	local colors = { ctx.biome.rock[2], ctx.biome.rock[3] }
	eachBand(part, function(y0, y1, out, index)
		if out == 0 or y1 - y0 < 2 then
			return
		end
		local offset = side * (face + (out - 1) / 2) -- 1 stud hundido en la pared, `out` fuera
		local band = if axis == "X"
			then ctx.kit.part(parent, "Strata", "Strata", Vector3.new(out + 1, y1 - y0, size.Z), cf * CFrame.new(offset, (y0 + y1) / 2, 0))
			else ctx.kit.part(parent, "Strata", "Strata", Vector3.new(size.X, y1 - y0, out + 1), cf * CFrame.new(0, (y0 + y1) / 2, offset))
		band.Color = colors[index % #colors + 1]
	end, trimBottom, trimTop)
end

-- Losas facetadas inclinadas sobre la cara ±X (sobresalen exactamente SKIN; giran sobre la normal de la pared).
local function facets(ctx, parent, wall: BasePart, side: number, yMin: number, yMax: number)
	local size, rng = wall.Size, ctx.rng
	local count = if size.Z >= 80 then math.max(1, math.floor(size.Z / 120)) else 0
	if yMin >= yMax then
		return
	end
	for _ = 1, count do
		local length, height = rng:NextNumber(30, 70), rng:NextNumber(18, 40)
		local z = rng:NextNumber(-1, 1) * math.max(size.Z / 2 - length / 2, 0)
		local y = rng:NextNumber(yMin, yMax)
		local facet = ctx.kit.part(parent, "Facet", "Facet", Vector3.new(SKIN + 6, height, length), wall.CFrame * CFrame.new(side * (size.X / 2 + (SKIN - 6) / 2), y, z) * CFrame.Angles(rng:NextNumber(-0.6, 0.6), 0, 0))
		if rng:NextNumber() < 0.5 then
			facet.Color = ctx.biome.rock[3]
		end
	end
end

-- Remate del borde superior (césped, nieve…) y, si se pide, árboles grandes encima.
local function cap(ctx, parent, part: BasePart, treeSpacing: number?)
	local cf, size, rng = part.CFrame, part.Size, ctx.rng
	ctx.kit.part(parent, "Cap", "Cap", Vector3.new(size.X + 2, 3, size.Z + 2), cf * CFrame.new(0, size.Y / 2 + 1.5, 0))
	if not treeSpacing then
		return
	end
	local length = math.max(size.X, size.Z)
	local alongZ = size.Z >= size.X
	local s = -length / 2 + rng:NextNumber(20, treeSpacing)
	while s < length / 2 - 20 do
		local offset = if alongZ then CFrame.new(0, size.Y / 2 + 3, s) else CFrame.new(s, size.Y / 2 + 3, 0)
		plant(ctx, parent, cf * offset * CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0), rng:NextNumber(2.4, 3.2), 0)
		s += rng:NextNumber(treeSpacing * 0.7, treeSpacing * 1.3)
	end
end

-- Pared de corredor o de valle: color base + estratos y facetas en la cara interior.
local function wall(ctx, parent, part: BasePart, side: number, isValley: boolean)
	if isValley then
		strata(ctx, parent, part, "X", side)
	else
		-- Corredor: solo entre el suelo (pie + 30) y el techo (borde - rim); lo demás queda oculto.
		strata(ctx, parent, part, "X", side, WALL_FOOT - 2, ctx.rim - 2)
	end
	-- Las facetas quedan entre el suelo (pie + 30) y algo por debajo del borde superior.
	facets(ctx, parent, part, side, -part.Size.Y / 2 + 40, part.Size.Y / 2 - 70)
	if isValley then
		cap(ctx, parent, part, 160)
	end
end

local function cliffFace(ctx, parent, part: BasePart, sides)
	for _, side in sides do
		strata(ctx, parent, part, "Z", side)
	end
	local boxCFrame, box = (part.Parent :: Model):GetBoundingBox()
	local modelTop = boxCFrame.Position.Y + box.Y / 2
	if part.Position.Y + part.Size.Y / 2 >= modelTop - 1 then
		cap(ctx, parent, part, nil)
	end
end

-- ── Suelo ─────────────────────────────────────────────────────────────

local function patch(ctx, parent, base: CFrame, minSize: number, maxSize: number)
	local rng = ctx.rng
	local height = rng:NextNumber(0.2, 0.4)
	local piece = ctx.kit.part(parent, "Patch", "Patch", Vector3.new(rng:NextNumber(minSize, maxSize), height, rng:NextNumber(minSize, maxSize)), base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0))
	piece.Color = ctx.biome.patches[rng:NextInteger(1, #ctx.biome.patches)]
end

-- Suelo del corredor (mortal): rocas y arbustos bajos SOLO junto a las paredes + manchas visuales.
local function corridorFloor(ctx, parent, part: BasePart)
	local cf, size, rng = part.CFrame, part.Size, ctx.rng
	local top = size.Y / 2
	local inner = size.X / 2 - ctx.wallT
	local half = size.Z / 2 - 8
	local z = -half + rng:NextNumber(0, 30)
	while z < half do
		for _, side in { -1, 1 } do
			if rng:NextNumber() < 0.8 then
				-- Centro a ≤ 10 de la pared: con su medio tamaño (≤ 8) la pieza entera queda dentro de la franja.
				local base = cf * CFrame.new(side * (inner - rng:NextNumber(4, WALL_STRIP - 10)), top, z) * CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0)
				local prop = if rng:NextNumber() < 0.55
					then ctx.kit.rock(parent, base, rng:NextNumber(6, 11))
					else ctx.kit.bush(parent, base, rng:NextNumber(6, 10), bushColors(ctx.biome))
				prop:SetAttribute("SkinLimit", WALL_STRIP) -- ocupan la franja: ≤ 20 hacia dentro, ≤ 12 de alto
			end
		end
		z += rng:NextNumber(35, 60)
	end
	z = -half + rng:NextNumber(0, 40)
	while z < half do
		patch(ctx, parent, cf * CFrame.new(rng:NextNumber(-1, 1) * (inner - 25), top, z), 18, 40)
		z += rng:NextNumber(50, 90)
	end
end

-- Fondo del valle (muy por debajo del vuelo): árboles grandes, rocas, arbustos y manchas.
local function valleyFloor(ctx, parent, part: BasePart)
	local cf, size, rng = part.CFrame, part.Size, ctx.rng
	local top = size.Y / 2
	local ix, iz = size.X / 2 - ctx.wallT - 25, size.Z / 2 - 25
	local function spot()
		return cf * CFrame.new(rng:NextNumber(-ix, ix), top, rng:NextNumber(-iz, iz)) * CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0)
	end
	-- Cantidades para un valle entero (~600 de largo), repartidas según el largo de este tramo de suelo.
	local function share(count: number): number
		return math.max(1, math.floor(count * size.Z / 600 + 0.5))
	end
	for _ = 1, share(14) do
		patch(ctx, parent, spot(), 40, 90)
	end
	for _ = 1, share(12) do
		plant(ctx, parent, spot(), rng:NextNumber(2, 3.2), 0.25)
	end
	for _ = 1, share(10) do
		ctx.kit.rock(parent, spot(), rng:NextNumber(12, 24))
	end
	for _ = 1, share(12) do
		ctx.kit.bush(parent, spot(), rng:NextNumber(8, 14), bushColors(ctx.biome))
	end
end

-- ── Techo: capa de nubes ──────────────────────────────────────────────

local CLOUD_SPACING = { 130, 180 } -- studs entre nubes, medidos a lo largo del recorrido
local CLOUD_TIER = 3 -- grosor de cada piso de nube: cuelgan como mucho 2 × CLOUD_TIER bajo el techo
local CLOUD_SHADE = rgb(160, 182, 230) -- panza azulada: más marcada cuanto más abajo
-- Vista desde abajo, la losa solo recibe luz ambiente y el blanco sale gris apagado. Con Neon al 50 % del color
-- de nube brilla como una capa cubierta (sin llegar al umbral del Bloom), y las nubes sombreadas resaltan.
local CEILING_GLOW = 0.5

-- La losa sigue siendo la colisión (se roza) y se ve como la base luminosa de un mar de nubes. Debajo cuelgan
-- pocas nubes grandes low-poly, repartidas por DISTANCIA (el reparto sigue de losa en losa: las curvas, con
-- muchas losas cortas, no acumulan nubes) y alternando lado. Cada nube = 3 placas giradas (como el truco del
-- hexágono, pero irregular) en dos pisos: el de abajo, más pequeño y más azulado, da volumen visto desde abajo.
-- Son visuales: el ala las atraviesa al rozar el techo.
local function ceiling(ctx, parent, part: BasePart)
	local cf, size, rng = part.CFrame, part.Size, ctx.rng
	local cloud = ctx.biome.cloud
	part.Color = Color3.new(cloud.R * CEILING_GLOW, cloud.G * CEILING_GLOW, cloud.B * CEILING_GLOW)
	part.Material = Enum.Material.Neon
	part.Transparency = 0 -- opaca: se lee como techo continuo, no como cielo abierto
	part.CastShadow = false
	local bottom = -size.Y / 2
	local halfX = size.X / 2 - ctx.wallT
	local length = size.Z
	local t = ctx.cloudGap or rng:NextNumber(20, 80) -- distancia dentro de esta losa hasta la siguiente nube
	while t < length do
		ctx.cloudSide = -(ctx.cloudSide or 1)
		local x = ctx.cloudSide * rng:NextNumber(10, math.max(halfX - 50, 20))
		local base = cf * CFrame.new(x, bottom, length / 2 - t) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
		local upper = cloud:Lerp(CLOUD_SHADE, 0.1)
		local plates = {
			{ Vector3.new(rng:NextNumber(110, 160), CLOUD_TIER, rng:NextNumber(60, 90)), 0, 1, upper },
			{ Vector3.new(rng:NextNumber(80, 120), CLOUD_TIER, rng:NextNumber(70, 100)), rng:NextNumber(50, 70), 1, upper },
			{ Vector3.new(rng:NextNumber(60, 90), CLOUD_TIER, rng:NextNumber(40, 60)), rng:NextNumber(20, 40), 2, cloud:Lerp(CLOUD_SHADE, 0.25) },
		}
		for _, plate in plates do
			local tier = plate[3]
			local offset = if tier == 2 then CFrame.new(rng:NextNumber(-12, 12), 0, rng:NextNumber(-8, 8)) else CFrame.identity
			local piece = ctx.kit.part(parent, "Cloud", "Cloud", plate[1], base * offset * CFrame.new(0, -(tier - 0.5) * CLOUD_TIER, 0) * CFrame.Angles(0, math.rad(plate[2]), 0))
			piece.Color = plate[4]
		end
		t += rng:NextNumber(CLOUD_SPACING[1], CLOUD_SPACING[2])
	end
	ctx.cloudGap = t - length
end

-- ── Obstáculos y guías ────────────────────────────────────────────────

-- Estratos alrededor de un obstáculo vertical: copias engrosadas en los tramos pares.
-- growX/growZ = fracción del relieve del tramo que crece cada cara en X/Z (0 = no crece en ese eje).
local function obstacleBands(ctx, parent, part: BasePart, growX: number, growZ: number, edge: ((number, number, number) -> ())?)
	local cf, size = part.CFrame, part.Size
	eachBand(part, function(y0, y1, out, index)
		if out > 0 and y1 - y0 >= 2 then
			local grown = Vector3.new(size.X + 2 * out * growX, y1 - y0, size.Z + 2 * out * growZ)
			local band = ctx.kit.part(parent, "Strata", "Strata", grown, cf * CFrame.new(0, (y0 + y1) / 2, 0))
			band.Color = ctx.biome.obstacle:Lerp(if index % 2 == 0 then Color3.new(0, 0, 0) else Color3.new(1, 1, 1), 0.14)
		end
		if edge then
			edge(y0, y1, if y1 - y0 >= 2 then out else 0)
		end
	end)
end

local function obstacle(ctx, parent, part: BasePart)
	local kit, size = ctx.kit, part.Size
	part.Color = ctx.biome.obstacle
	if part:IsA("WedgePart") then
		-- Loma: la cuña de subida tiene su cara alta (+Z local) en la cima → línea de peligro en la cresta.
		if part.Name:sub(-2) == "Up" then
			kit.part(parent, "HazardEdge", "Hazard", Vector3.new(size.X, 1.5, 1.5), part.CFrame * CFrame.new(0, size.Y / 2, size.Z / 2))
		end
	elseif part.Name:find("^Lintel") then
		-- Viga: el ala llega por su +Z; la línea marca el borde inferior de esa cara.
		local bottomOut = 0
		obstacleBands(ctx, parent, part, 0, 1, function(y0, _, out)
			if y0 <= -size.Y / 2 + 0.01 then
				bottomOut = out
			end
		end)
		kit.part(parent, "HazardEdge", "Hazard", Vector3.new(size.X, 1.5, 1.5), part.CFrame * CFrame.new(0, -size.Y / 2, size.Z / 2 + bottomOut))
	elseif part.Name:find("^Promontory") then
		-- Saliente: prisma girado 45°; la arista que apunta al centro del corredor lleva la línea de peligro.
		-- Al engrosar las caras la arista avanza √2 veces más: se engrosa al 70 % para que avance ≤ 3 studs.
		local side = part:GetAttribute("Side")
		local frame = part.CFrame * CFrame.Angles(0, -math.rad(45), 0)
		obstacleBands(ctx, parent, part, PROMONTORY_GROW, PROMONTORY_GROW, function(y0, y1, out)
			if not side then
				return
			end
			local apex = part.Position - frame.RightVector * side * ((size.X + 2 * out * PROMONTORY_GROW) / math.sqrt(2))
			kit.part(parent, "HazardEdge", "Hazard", Vector3.new(1.5, y1 - y0, 1.5), CFrame.new(apex + Vector3.new(0, (y0 + y1) / 2, 0)) * frame.Rotation)
		end)
	elseif part.Name:find("^Pillar") then
		-- Pilar: prisma girado 45° como el saliente (se engrosa igual: ≤ 3 studs en las aristas); la línea de
		-- peligro va en la arista que mira al ala que llega (hacia atrás del recorrido).
		local frame = part.CFrame * CFrame.Angles(0, -math.rad(45), 0)
		obstacleBands(ctx, parent, part, PROMONTORY_GROW, PROMONTORY_GROW, function(y0, y1, out)
			local apex = part.Position - frame.LookVector * ((size.X + 2 * out * PROMONTORY_GROW) / math.sqrt(2))
			kit.part(parent, "HazardEdge", "Hazard", Vector3.new(1.5, y1 - y0, 1.5), CFrame.new(apex + Vector3.new(0, (y0 + y1) / 2, 0)) * frame.Rotation)
		end)
	end
end

-- Anillo guía: barras más finas (siguen siendo el mismo hueco) y una gema en cada esquina.
local function guideRing(ctx, parent, ring: Instance)
	local top, bottom, left, right = ring:FindFirstChild("Top"), ring:FindFirstChild("Bottom"), ring:FindFirstChild("Left"), ring:FindFirstChild("Right")
	if not (top and bottom and left and right) then
		return
	end
	local bar, thin = top.Size.Y, 2.5
	if bar > thin then
		local d = (bar - thin) / 2
		for _, piece in { top, bottom } do
			piece.Size = Vector3.new(piece.Size.X - 2 * (bar - thin), thin, piece.Size.Z)
		end
		top.CFrame *= CFrame.new(0, -d, 0)
		bottom.CFrame *= CFrame.new(0, d, 0)
		for _, piece in { left, right } do
			piece.Size = Vector3.new(thin, piece.Size.Y, piece.Size.Z)
		end
		left.CFrame *= CFrame.new(d, 0, 0)
		right.CFrame *= CFrame.new(-d, 0, 0)
	end
	for _, piece in { top, bottom, left, right } do
		piece.Color = ctx.biome.guide
	end
	for _, piece in { top, bottom } do
		for _, s in { -1, 1 } do
			ctx.kit.gem(parent, "GuideGem", "GuideGem", 5, piece.CFrame * CFrame.new(s * (piece.Size.X / 2 - thin / 2), 0, 0))
		end
	end
end

-- ── Entrada del nivel: arco de piedra + cartel ────────────────────────

local function entrance(ctx, parent, face: Instance, level: Instance)
	local top, bottom = face:FindFirstChild("Top"), face:FindFirstChild("Bottom")
	if not (top and bottom) then
		return
	end
	local kit = ctx.kit
	local frame = top.CFrame -- cara del acantilado; +Z mira al valle anterior
	local hw, z = top.Size.X / 2, top.Size.Z / 2
	local openTop = -top.Size.Y / 2
	local openBottom = bottom.Position.Y + bottom.Size.Y / 2 - top.Position.Y
	local height = openTop - openBottom
	-- Arco pegado a la cara, por FUERA del hueco (no invade el paso).
	for _, s in { -1, 1 } do
		kit.part(parent, "ArchPillar", "Stone", Vector3.new(14, height + 14, 8), frame * CFrame.new(s * (hw + 7), (openBottom + openTop + 14) / 2, z + 4))
		kit.gem(parent, "ArchGem", "ArchGem", 8, frame * CFrame.new(s * (hw + 7), openTop + 20, z + 4))
	end
	kit.part(parent, "ArchLintel", "Stone", Vector3.new(2 * hw + 28, 14, 8), frame * CFrame.new(0, openTop + 7, z + 4))

	local sign = kit.part(parent, "Sign", "Sign", Vector3.new(math.min(2 * hw - 20, 200), 36, 3), frame * CFrame.new(0, openTop + 14 + 4 + 18, z + 1.5))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- +Z: hacia el valle
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 8
	gui.LightInfluence = 0
	gui.Parent = sign
	local function label(text: string, y: number, h: number, font: Enum.Font, color: Color3)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.04, y)
		l.Size = UDim2.fromScale(0.92, h)
		l.Font = font
		l.TextScaled = true
		l.TextColor3 = color
		l.Text = text
		l.Parent = gui
	end
	label("LEVEL " .. (level.Name:match("%d+") or "?"), 0.06, 0.52, Enum.Font.GothamBlack, Color3.new(1, 1, 1))
	label(level:GetAttribute("Title") or "", 0.6, 0.32, Enum.Font.GothamBold, ctx.biome.guide)
end

-- ── Valles ────────────────────────────────────────────────────────────

-- Cascada visual por la cara interior de una pared del valle, con charca y espuma abajo.
local function waterfall(ctx, parent, wallPart: BasePart, side: number)
	local cf, size, rng, kit = wallPart.CFrame, wallPart.Size, ctx.rng, ctx.kit
	local face = size.X / 2
	local topY = size.Y / 2
	local floorY = -size.Y / 2 + WALL_FOOT
	local count = math.max(3, math.ceil((topY - floorY) / 90))
	local piece = (topY - floorY) / count
	kit.part(parent, "Lip", "Water", Vector3.new(8, 1, 44), cf * CFrame.new(side * (face - 3), topY + 3.5, 0))
	for k = 1, count do
		local fall = kit.part(parent, "Fall", "Water", Vector3.new(2, piece + 2, 44 + 3 * k), cf * CFrame.new(side * (face + 1 + 0.5 * k), topY - piece * (k - 0.5), 0) * CFrame.Angles(if k % 2 == 0 then 0.03 else -0.03, 0, 0))
		fall.Transparency = 0.25 + 0.03 * k
	end
	for k = 1, 2 do
		kit.part(parent, "Foam", "Foam", Vector3.one * rng:NextNumber(6, 9), cf * CFrame.new(side * (face + 2), topY + 1, (k - 1.5) * 10), Enum.PartType.Ball)
	end
	kit.hex(parent, "Pond", "Water", 45, 0.6, cf * CFrame.new(side * (face + 45), floorY + 0.3, 0))
	for k = 1, 3 do
		kit.part(parent, "Mist", "Cloud", Vector3.one * rng:NextNumber(28, 44), cf * CFrame.new(side * (face + 12 + 6 * k), floorY + 10, (k - 2) * 18), Enum.PartType.Ball).Transparency = 0.2
	end
end

-- Formaciones del fondo del valle: prismas hexagonales apilados que se estrechan + losa de remate. Lejos de
-- la isla (avoid = centro de la isla) y muy por debajo de ella y del vuelo. Cada estilo cambia cuántas hay
-- por valle (~600 de largo), su radio, su alto, cuánto se estrechan y la distancia mínima a la isla.
local FORMATIONS = {
	hoodoos = { count = 7, radius = { 12, 18 }, height = { 50, 110 }, taper = 0.85, clearance = 160 }, -- agujas (cañón)
	mesas = { count = 3, radius = { 30, 44 }, height = { 45, 85 }, taper = 0.97, clearance = 210 }, -- cima plana
	spires = { count = 8, radius = { 10, 15 }, height = { 70, 130 }, taper = 0.72, clearance = 160 }, -- seracs de hielo
	stacks = { count = 5, radius = { 16, 24 }, height = { 60, 120 }, taper = 0.92, clearance = 180, grassCap = true }, -- farallones
}

local function formations(ctx, parent, floorPart: BasePart, avoid: Vector3?, style)
	local cf, size, rng, kit = floorPart.CFrame, floorPart.Size, ctx.rng, ctx.kit
	local top = size.Y / 2
	local ix, iz = size.X / 2 - ctx.wallT - 40, size.Z / 2 - 30
	local placed, wanted = 0, math.max(1, math.floor(style.count * size.Z / 600 + 0.5))
	for _ = 1, 40 do
		if placed >= wanted then
			break
		end
		local base = cf * CFrame.new(rng:NextNumber(-ix, ix), top, rng:NextNumber(-iz, iz)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
		if avoid and (Vector3.new(base.X, 0, base.Z) - Vector3.new(avoid.X, 0, avoid.Z)).Magnitude < style.clearance then
			continue
		end
		local radius, y = rng:NextNumber(style.radius[1], style.radius[2]), 0
		local height = rng:NextNumber(style.height[1], style.height[2])
		local count = math.max(3, math.floor(height / 24))
		for k = 1, count do
			local h = height / count
			kit.hex(parent, "Hoodoo", "Strata", radius, h, base * CFrame.new(0, y + h / 2, 0) * CFrame.Angles(0, rng:NextNumber(0, 1), 0), ctx.biome.rock[if k % 2 == 1 then 2 else 3])
			y += h
			radius *= style.taper
		end
		kit.part(parent, "HoodooCap", if style.grassCap then "Cap" else "Facet", Vector3.new(radius * 2.8, 6, radius * 2.5), base * CFrame.new(0, y + 3, 0) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), rng:NextNumber(0, math.pi), rng:NextNumber(-0.15, 0.15)))
		placed += 1
	end
end

-- Cristales gigantes en el fondo del valle (mismo reparto que las formaciones).
local function crystalField(ctx, parent, floorPart: BasePart, avoid: Vector3?)
	local cf, size, rng, biome = floorPart.CFrame, floorPart.Size, ctx.rng, ctx.biome
	local top = size.Y / 2
	local ix, iz = size.X / 2 - ctx.wallT - 40, size.Z / 2 - 30
	local placed, wanted = 0, math.max(1, math.floor(6 * size.Z / 600 + 0.5))
	for _ = 1, 40 do
		if placed >= wanted then
			break
		end
		local base = cf * CFrame.new(rng:NextNumber(-ix, ix), top, rng:NextNumber(-iz, iz)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
		if avoid and (Vector3.new(base.X, 0, base.Z) - Vector3.new(avoid.X, 0, avoid.Z)).Magnitude < 170 then
			continue
		end
		ctx.kit.crystal(parent, base, rng:NextNumber(4, 7), biome.leaves[rng:NextInteger(1, #biome.leaves)], biome.blossoms[rng:NextInteger(1, #biome.blossoms)])
		placed += 1
	end
end

-- Mar de nubes: nubes bajas (solo visuales) flotando en el valle, por debajo de la isla y del vuelo.
local function cloudSea(ctx, parent, floorPart: BasePart)
	local cf, size, rng = floorPart.CFrame, floorPart.Size, ctx.rng
	local top = size.Y / 2
	local ix, iz = size.X / 2 - ctx.wallT - 30, size.Z / 2 - 20
	for _ = 1, math.max(1, math.floor(10 * size.Z / 600 + 0.5)) do
		ctx.kit.cloud(parent, cf * CFrame.new(rng:NextNumber(-ix, ix), top + rng:NextNumber(20, 120), rng:NextNumber(-iz, iz)), rng:NextNumber(1.6, 2.6))
	end
end

local function lighthouse(ctx, parent, base: CFrame, height: number)
	local count = math.max(2, math.floor(height / 16 + 0.5))
	local segment = height / count
	for k = 1, count do
		local radius = 6.5 - 2 * (k - 1) / count
		ctx.kit.hex(parent, "Lighthouse", if k % 2 == 1 then "Tower" else "Stripe", radius, segment, base * CFrame.new(0, segment * (k - 0.5), 0))
	end
	ctx.kit.hex(parent, "Gallery", "Stone", 8.5, 2, base * CFrame.new(0, height - 1, 0))
end

-- Isla de descanso/salida: el bloque del blockout pasa a isla flotante hexagonal con faro y vegetación.
-- El lado plano delantero queda donde estaba el borde del rectángulo (el despegue no cambia).
local function island(ctx, parent, model: Instance)
	local platform = model:FindFirstChild("Platform")
	if not (platform and platform:IsA("BasePart")) then
		return
	end
	local kit, rng, biome = ctx.kit, ctx.rng, ctx.biome
	local top = platform.CFrame * CFrame.new(0, platform.Size.Y / 2, 0)
	local radius = platform.Size.Z / LowPoly.SQRT3 -- apotema = medio largo del rectángulo
	local mast, light = model:FindFirstChild("BeaconMast"), model:FindFirstChild("BeaconLight")
	for _, name in { "Platform", "Rock1", "Rock2", "Rock3" } do
		local old = model:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	kit.floatingIsland(parent, top, radius, ISLAND_MAX_DEPTH)

	local avoid = {}
	if mast and light then
		local base = mast.Position - Vector3.new(0, mast.Size.X / 2, 0)
		lighthouse(ctx, parent, CFrame.new(base) * top.Rotation, light.Position.Y - light.Size.Y / 2 - base.Y)
		local localBase = top:PointToObjectSpace(base)
		table.insert(avoid, { x = localBase.X, z = localBase.Z, r = 22 })
		mast:Destroy()
	end
	-- Vegetación baja: nada en el centro (spawn) ni en la franja delantera (despegue / paso del ala).
	local apothem = radius * LowPoly.SQRT3 / 2
	local function spot(size)
		for _ = 1, 30 do
			local phi = rng:NextNumber(0, 2 * math.pi)
			local r = rng:NextNumber(25, LowPoly.hexEdge(radius, phi) - 10)
			local x, z = r * math.sin(phi), -r * math.cos(phi)
			local free = not (z < -apothem * 0.2 and math.abs(x) < 45)
			for _, a in avoid do
				if (x - a.x) ^ 2 + (z - a.z) ^ 2 < (a.r + size) ^ 2 then
					free = false
				end
			end
			if free then
				table.insert(avoid, { x = x, z = z, r = size })
				return top * CFrame.new(x, 0, z) * CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0)
			end
		end
		return nil
	end
	for _ = 1, 5 do
		local base = spot(8)
		if base then
			plant(ctx, parent, base, rng:NextNumber(0.8, 1.1), 0.3)
		end
	end
	for _ = 1, 6 do
		local base = spot(4)
		if base then
			kit.bush(parent, base, rng:NextNumber(4, 8), bushColors(biome))
		end
	end
	for _ = 1, 4 do
		local base = spot(4)
		if base then
			kit.rock(parent, base, rng:NextNumber(4, 9))
		end
	end
	for _ = 1, 8 do
		local base = spot(2)
		if base then
			kit.flowers(parent, base, biome.flowers)
		end
	end
end

-- ── Entrada principal ─────────────────────────────────────────────────

-- options: wallT (grosor de pared de MapBuilder), rim (cuánto sobresalen las paredes sobre el techo), seed,
-- index (alterna el lado de la cascada del valle).
-- Devuelve el número de piezas añadidas.
function MapDresser.dress(model: Instance, biome, options): number
	options = options or {}
	local rng = Random.new(options.seed or 1)
	local kit = LowPoly.kit({ colors = palette(biome), style = STYLE, rng = rng, attributes = { Dressing = true } })
	local ctx = { kit = kit, rng = rng, biome = biome, wallT = options.wallT or 24, rim = options.rim or 60 }
	local root = LowPoly.folder(model, "Dressing")
	local folders = {}
	local function folder(name: string): Folder
		folders[name] = folders[name] or LowPoly.folder(root, name)
		return folders[name]
	end

	if model:FindFirstChild("Platform") then
		island(ctx, folder("Island"), model)
	end

	-- Foto de las piezas del blockout antes de añadir nada.
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Kind") and not d:GetAttribute("Dressing") then
			table.insert(parts, d)
		end
	end
	local rings, valleyWalls, valleyFloors = {}, {}, {}
	for _, part in parts do
		local kind, parentName = part:GetAttribute("Kind"), part.Parent.Name
		if kind == "Cliff" then
			part.Color = biome.rock[1]
			if part.Name == "WallLeft" or part.Name == "WallRight" then
				-- buildTube: la cara interior de WallLeft es su +X local; la de WallRight, su -X.
				local side = if part.Name == "WallLeft" then 1 else -1
				local isValley = parentName == "Valley"
				wall(ctx, folder(if isValley then "Valley" else "Walls"), part, side, isValley)
				if isValley then
					table.insert(valleyWalls, { part = part, side = side })
				end
			elseif FACE_SIDES[parentName] then
				cliffFace(ctx, folder("Faces"), part, FACE_SIDES[parentName])
			end
		elseif kind == "Ground" then
			part.Color = biome.ground
			if parentName == "Valley" then
				valleyFloor(ctx, folder("Valley"), part)
				table.insert(valleyFloors, part)
			else
				corridorFloor(ctx, folder("Floor"), part)
			end
		elseif kind == "Ceiling" then
			ceiling(ctx, folder("Ceiling"), part)
		elseif kind == "Obstacle" then
			obstacle(ctx, folder("Obstacles"), part)
		elseif kind == "Guide" then
			rings[part.Parent] = true
		end
	end
	for ring in rings do
		guideRing(ctx, folder("Guides"), ring)
	end
	local entranceFace = model:FindFirstChild("EntranceFace")
	if entranceFace then
		entrance(ctx, folder("Entrance"), entranceFace, model)
	end
	if biome.valleyFeature == "waterfall" and #valleyWalls > 0 then
		local wantLeft = (options.index or 0) % 2 == 0
		for _, w in valleyWalls do
			if (w.part.Name == "WallLeft") == wantLeft then
				waterfall(ctx, folder("Valley"), w.part, w.side)
				break
			end
		end
	elseif FORMATIONS[biome.valleyFeature] or biome.valleyFeature == "crystals" then
		local spawnPoint = model:FindFirstChild("SpawnPoint")
		local avoid = spawnPoint and spawnPoint.Position
		for _, floorPart in valleyFloors do
			if biome.valleyFeature == "crystals" then
				crystalField(ctx, folder("Valley"), floorPart, avoid)
			else
				formations(ctx, folder("Valley"), floorPart, avoid, FORMATIONS[biome.valleyFeature])
			end
		end
	elseif biome.valleyFeature == "clouds" then
		for _, floorPart in valleyFloors do
			cloudSea(ctx, folder("Valley"), floorPart)
		end
	end
	model:SetAttribute("Biome", biome.name)

	local count = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

-- ── Auditoría de la regla de oro ──────────────────────────────────────

-- Desde cada punto de la línea ideal (Route) lanza rayos a los lados, en diagonal y hacia abajo, una vez
-- contra el blockout y otra contra todo lo sólido. La diferencia (medida perpendicular a la superficie)
-- es lo que el vestido invade; no puede pasar del SkinLimit de la pieza (SKIN_MAX por defecto).
-- Devuelve la peor invasión, cuántos rayos se pasaron del límite y una descripción del peor caso.
function MapDresser.audit(level: Instance): (number, number, string)
	local route = level:FindFirstChild("Route")
	if not route then
		return 0, 0, "sin Route"
	end
	local blockout, solid = {}, {}
	for _, d in level:GetDescendants() do
		if d:IsA("BasePart") and d.CanQuery then
			table.insert(solid, d)
			if not d:GetAttribute("Dressing") then
				table.insert(blockout, d)
			end
		end
	end
	local onlyBlockout = RaycastParams.new()
	onlyBlockout.FilterType = Enum.RaycastFilterType.Include
	onlyBlockout.FilterDescendantsInstances = blockout
	local everything = RaycastParams.new()
	everything.FilterType = Enum.RaycastFilterType.Include
	everything.FilterDescendantsInstances = solid

	local worst, violations, detail = 0, 0, "sin invasiones"
	for _, point in route:GetChildren() do
		local cf = point.CFrame
		local rays = {}
		for _, v in { -40, 0, 40 } do
			for _, dir in { cf.RightVector, -cf.RightVector } do
				table.insert(rays, { cf.Position + cf.UpVector * v, dir })
			end
		end
		for _, dir in { -cf.UpVector, (cf.RightVector - cf.UpVector).Unit, (-cf.RightVector - cf.UpVector).Unit } do
			table.insert(rays, { cf.Position, dir })
		end
		for _, ray in rays do
			local origin, dir = ray[1], ray[2] * 800
			local a = workspace:Raycast(origin, dir, onlyBlockout)
			local b = workspace:Raycast(origin, dir, everything)
			if a and b and b.Instance:GetAttribute("Dressing") then
				local intrusion = ((a.Position - origin).Magnitude - (b.Position - origin).Magnitude) * math.abs(ray[2]:Dot(a.Normal))
				local limit = b.Instance:GetAttribute("SkinLimit") or MapDresser.SKIN_MAX
				if intrusion > limit + 0.5 then
					violations += 1
				end
				if intrusion > worst then
					worst = intrusion
					detail = string.format("%s en %s (límite %d)", b.Instance.Name, point.Name, limit)
				end
			end
		end
	end
	return worst, violations, detail
end

return MapDresser
