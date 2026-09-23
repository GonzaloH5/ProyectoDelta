--!nonstrict
-- LowPoly: piezas low-poly compartidas por los constructores (LobbyBuilder, MapDresser). Solo modo edición.
--
-- Uso:
--   local LowPoly = require(game.ServerScriptService.Glider.DevTools.LowPoly:Clone())
--   local kit = LowPoly.kit({ colors = COLORS, style = STYLE, rng = Random.new(1), attributes = { Dressing = true } })
--   kit.tree(parent, base, 1.2, color)
-- colors[kind] = Color3 · style[kind] = { neon, transparency, noShadow, visual } (visual = sin colisión ni consultas).
-- "base" es un CFrame apoyado en el suelo (su +Y = arriba). El rng se recibe de fuera para que cada
-- constructor conserve su semilla: el mismo rng y el mismo orden de llamadas dan siempre el mismo resultado.
-- Tipos (kind) que usan las piezas compuestas: Trunk, Leaf (árbol) · Cactus · Rock, RockDark (roca, isla) · Grass (isla)
-- · Bush · Flower · WoodDark, Lamp (farolillo) · Cloud (nube).

local LowPoly = {}

LowPoly.SQRT3 = math.sqrt(3)

function LowPoly.tint(part: BasePart, color: Color3): BasePart
	part.Color = color
	return part
end

function LowPoly.model(parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- llega entero: siempre legible
	model.Parent = parent
	return model
end

function LowPoly.folder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- Distancia del centro al borde de un hexágono de kit.hex (sin girar) en la dirección φ
-- (φ = 0 hacia su -Z local, positivos hacia su +X). Lados planos en φ = 0, ±60°, 180°.
function LowPoly.hexEdge(radius: number, phi: number): number
	local psi = (math.deg(phi) + 30) % 60 - 30
	return radius * LowPoly.SQRT3 / 2 / math.cos(math.rad(psi))
end

-- Desplazamiento en el plano de "base" para ir r studs en la dirección φ (misma convención que hexEdge).
function LowPoly.offset(r: number, phi: number, y: number?): CFrame
	return CFrame.new(r * math.sin(phi), y or 0, -r * math.cos(phi))
end

function LowPoly.kit(options)
	local colors, style, rng = options.colors, options.style or {}, options.rng
	local attributes = options.attributes or {}
	local kit = {}

	-- shape: Enum.PartType (Ball, Cylinder…) o "Wedge" para una WedgePart (sube hacia su +Z local).
	function kit.part(parent: Instance, name: string, kind: string, size: Vector3, cframe: CFrame, shape: any?)
		local s = style[kind] or {}
		local part = Instance.new(if shape == "Wedge" then "WedgePart" else "Part")
		part.Name = name
		part.Anchored = true
		part.Size = size
		part.CFrame = cframe
		part.Color = colors[kind]
		part.Material = if s.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		part.Transparency = s.transparency or 0
		part.CastShadow = not s.noShadow
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		if typeof(shape) == "EnumItem" then
			(part :: Part).Shape = shape
		end
		if s.visual then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
		end
		part:SetAttribute("Kind", kind)
		for key, value in attributes do
			part:SetAttribute(key, value)
		end
		part.Parent = parent
		return part
	end

	-- Hexágono low-poly: 3 bloques girados 0/60/120°. Lados planos hacia su -Z/+Z (φ = 0, ±60…).
	function kit.hex(parent: Instance, name: string, kind: string, radius: number, height: number, cf: CFrame, color: Color3?)
		local apothem = radius * LowPoly.SQRT3 / 2
		for k = 0, 2 do
			local part = kit.part(parent, name, kind, Vector3.new(radius, height, 2 * apothem), cf * CFrame.Angles(0, math.rad(60 * k), 0))
			if color then
				part.Color = color
			end
		end
	end

	-- "Gema": cubo girado 45° en dos ejes (copas de árbol, rocas, remates).
	function kit.gem(parent: Instance, name: string, kind: string, size: number, cf: CFrame, color: Color3?)
		local part = kit.part(parent, name, kind, Vector3.new(size, size * 0.9, size), cf * CFrame.Angles(math.rad(45), rng:NextNumber(0, math.pi), math.rad(45)))
		if color then
			part.Color = color
		end
		return part
	end

	-- Árbol: tronco hexagonal + copa de 2-3 gemas. Alto total ≈ 20 × scale.
	function kit.tree(parent: Instance, base: CFrame, scale: number, color: Color3): Model
		local model = Instance.new("Model")
		model.Name = "Tree"
		local height = 10 * scale
		kit.hex(model, "Trunk", "Trunk", 1.8 * scale, height, base * CFrame.new(0, height / 2, 0))
		kit.gem(model, "Crown", "Leaf", 12 * scale, base * CFrame.new(0, height + 3 * scale, 0), color)
		kit.gem(model, "Crown", "Leaf", 8 * scale, base * CFrame.new(-1.5 * scale, height + 10 * scale, -2 * scale), color:Lerp(Color3.new(1, 1, 1), 0.12))
		if scale >= 1 then
			kit.gem(model, "Crown", "Leaf", 6 * scale, base * CFrame.new(3 * scale, height + 1 * scale, 3 * scale), color:Lerp(Color3.new(0, 0, 0), 0.1))
		end
		model.Parent = parent
		return model
	end

	-- Cactus (saguaro): tronco hexagonal + dos brazos en codo a distinta altura. Alto ≈ 15 × scale.
	-- bloom = color de una flor en la punta (opcional).
	function kit.cactus(parent: Instance, base: CFrame, scale: number, bloom: Color3?): Model
		local model = Instance.new("Model")
		model.Name = "Cactus"
		local height = 14 * scale
		kit.hex(model, "Trunk", "Cactus", 1.7 * scale, height, base * CFrame.new(0, height / 2, 0))
		kit.part(model, "Top", "Cactus", Vector3.new(2.4, 1.2, 2.4) * scale, base * CFrame.new(0, height + 0.4 * scale, 0) * CFrame.Angles(0, math.rad(45), 0))
		for _, arm in { { -1, 0.45, 0.4 }, { 1, 0.6, 0.3 } } do
			local side, elbow, length = arm[1], arm[2] * height, arm[3] * height
			kit.part(model, "Elbow", "Cactus", Vector3.new(3.6, 2.2, 2.2) * scale, base * CFrame.new(side * 2.6 * scale, elbow, 0))
			kit.part(model, "Arm", "Cactus", Vector3.new(2.2 * scale, length, 2.2 * scale), base * CFrame.new(side * 3.9 * scale, elbow - 1.1 * scale + length / 2, 0))
		end
		if bloom then
			kit.gem(model, "Bloom", "Leaf", 1.6 * scale, base * CFrame.new(0, height + 1.4 * scale, 0), bloom)
		end
		model.Parent = parent
		return model
	end

	-- Roca facetada medio enterrada (sobresale ≈ 0.5 × size).
	function kit.rock(parent: Instance, base: CFrame, size: number)
		local cf = base * CFrame.new(0, size * 0.15, 0) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, math.pi), rng:NextNumber(-0.5, 0.5))
		return kit.part(parent, "Rock", if rng:NextNumber() < 0.5 then "Rock" else "RockDark", Vector3.new(size, size * 0.7, size * 0.9), cf)
	end

	-- Arbusto redondo (sobresale 0.75 × size).
	function kit.bush(parent: Instance, base: CFrame, size: number, palette: { Color3 })
		local part = kit.part(parent, "Bush", "Bush", Vector3.one * size, base * CFrame.new(0, size * 0.25, 0), Enum.PartType.Ball)
		part.Color = palette[rng:NextInteger(1, #palette)]
		return part
	end

	-- Ramillete de 3-4 flores de un mismo color en un radio de 3 studs.
	function kit.flowers(parent: Instance, base: CFrame, palette: { Color3 })
		local color = palette[rng:NextInteger(1, #palette)]
		for _ = 1, rng:NextInteger(3, 4) do
			local r = rng:NextNumber(0, 3)
			local phi = rng:NextNumber(0, 2 * math.pi)
			LowPoly.tint(kit.part(parent, "Flower", "Flower", Vector3.one * 1.4, base * LowPoly.offset(r, phi, 0.5), Enum.PartType.Ball), color)
		end
	end

	function kit.lantern(parent: Instance, base: CFrame): Model
		local model = Instance.new("Model")
		model.Name = "Lantern"
		kit.part(model, "Post", "WoodDark", Vector3.new(1, 9, 1), base * CFrame.new(0, 4.5, 0))
		kit.part(model, "Lamp", "Lamp", Vector3.new(1.8, 1.8, 1.8), base * CFrame.new(0, 9.9, 0) * CFrame.Angles(0, math.rad(45), 0))
		kit.part(model, "Cap", "WoodDark", Vector3.new(2.6, 0.6, 2.6), base * CFrame.new(0, 11.1, 0) * CFrame.Angles(0, math.rad(45), 0))
		model.Parent = parent
		return model
	end

	-- Nube: grupo de 3-5 bolas/bloques en fila (tamaño de cada una entre minSize y maxSize × scale).
	function kit.cloud(parent: Instance, base: CFrame, scale: number, minSize: number?, maxSize: number?): Model
		local group = Instance.new("Model")
		group.Name = "Cloud"
		local cf = base * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
		local count = rng:NextInteger(3, 5)
		for j = 1, count do
			local s = rng:NextNumber(minSize or 18, maxSize or 34) * scale
			local offset = CFrame.new((j - (count + 1) / 2) * s * 0.6, rng:NextNumber(-2, 4) * scale, rng:NextNumber(-6, 6) * scale)
			if rng:NextNumber() < 0.6 then
				kit.part(group, "Puff", "Cloud", Vector3.one * s, cf * offset, Enum.PartType.Ball)
			else
				kit.part(group, "Puff", "Cloud", Vector3.new(s * 1.3, s * 0.55, s), cf * offset * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0))
			end
		end
		group.Parent = parent
		return group
	end

	-- Isla flotante: césped hexagonal (arriba = base) + capas de roca facetada que se estrechan + gemas colgando.
	-- Mide ~1.04 × radius de profundidad (o maxDepth, si se da y es menor). Lados planos hacia el -Z/+Z de base.
	function kit.floatingIsland(model: Instance, base: CFrame, radius: number, maxDepth: number?)
		kit.hex(model, "Platform", "Grass", radius, 6, base * CFrame.new(0, -3, 0))
		local depth = 6
		local layers = { { 0.96, 0.12, 0 }, { 0.8, 0.16, 15 }, { 0.6, 0.2, 30 }, { 0.4, 0.22, 10 }, { 0.2, 0.2, 40 }, { 0.07, 0.14, 20 } }
		local squash = if maxDepth then math.min(1, maxDepth / (radius * 1.04)) else 1
		for index, layer in layers do
			local height = radius * layer[2] * squash
			kit.hex(model, "Rock", if index % 2 == 1 then "Rock" else "RockDark", radius * layer[1], height, base * CFrame.new(0, -depth - height / 2, 0) * CFrame.Angles(0, math.rad(layer[3]), 0))
			depth += height
		end
		for k = 0, 5 do
			kit.gem(model, "Rock", "RockDark", radius * 0.2, base * LowPoly.offset(radius * 0.72, math.rad(30 + 60 * k), -radius * 0.2 - 6))
		end
	end

	return kit
end

return LowPoly
