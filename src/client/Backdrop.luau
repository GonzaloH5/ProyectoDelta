--!strict
-- Fondo lejano (solo en este cliente, mientras vuela): un anillo de montañas low-poly y nubes grandes que siguen
-- a la cámara, así que siempre están "en el horizonte" y dan profundidad por encima de las paredes y a través
-- del techo translúcido. No colisionan ni cuentan en ninguna consulta. Color según el bioma (atributo Biome).
-- Con calidad gráfica baja se ponen menos.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserSettings = UserSettings()

local GliderMath = require(ReplicatedStorage.Glider.GliderMath)

local Backdrop = {}

local RADIUS = 2100 -- studs de la cámara a las montañas
local FOLLOW_STEP = 150 -- el anillo se recoloca cuando la cámara se aleja esto (a esa distancia no se nota)
local rgb = Color3.fromRGB

-- Montaña (roca) y cima (nieve, arena, lava…) de cada bioma.
local PALETTES: { [string]: { rock: Color3, cap: Color3 } } = {
	Pradera = { rock = rgb(112, 138, 112), cap = rgb(238, 242, 248) },
	CanonRojo = { rock = rgb(176, 96, 72), cap = rgb(214, 138, 96) },
	BosqueOtonal = { rock = rgb(132, 108, 92), cap = rgb(212, 150, 78) },
	MesasDesierto = { rock = rgb(200, 158, 112), cap = rgb(232, 196, 146) },
	Glaciar = { rock = rgb(142, 164, 192), cap = rgb(246, 250, 255) },
	Acantilados = { rock = rgb(118, 128, 140), cap = rgb(206, 214, 204) },
	Selva = { rock = rgb(68, 116, 80), cap = rgb(104, 152, 92) },
	Volcan = { rock = rgb(72, 54, 54), cap = rgb(226, 106, 62) },
	Cristal = { rock = rgb(104, 88, 144), cap = rgb(206, 176, 255) },
	CieloFinal = { rock = rgb(206, 216, 236), cap = rgb(252, 252, 255) },
}

local folder: Folder? = nil
type Peak = { rock: { BasePart }, cap: { BasePart }, angle: number, radius: number, width: number }
local peaks: { Peak } = {}
local clouds: { { part: BasePart, angle: number, radius: number, height: number } } = {}
local anchor = Vector3.zero
local currentBiome: string? = nil
local cloudClock = 0

local function visual(parent: Instance, className: string, size: Vector3, color: Color3): BasePart
	local part = Instance.new(className) :: BasePart
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Size = size
	part.Color = color
	part.Parent = parent
	return part
end

-- Prisma triangular (dos cuñas espalda con espalda) que mira al centro del anillo.
local function ridge(parent: Instance, width: number, height: number, depth: number, color: Color3): { BasePart }
	return {
		visual(parent, "WedgePart", Vector3.new(depth, height, width / 2), color),
		visual(parent, "WedgePart", Vector3.new(depth, height, width / 2), color),
	}
end

local function placeRidge(pieces: { BasePart }, base: CFrame, width: number)
	-- base: centro de la base de la cresta, mirando hacia el centro del anillo (−Z local = hacia dentro).
	-- Las cuñas suben hacia su +Z local: las dos se giran para subir hacia la cumbre (x = 0).
	local height = pieces[1].Size.Y
	-- CFrame.Angles(0, θ, 0) lleva el +Z local a (sin θ, 0, cos θ): +π/2 sube hacia +X, −π/2 hacia −X.
	pieces[1].CFrame = base * CFrame.new(-width / 4, height / 2, 0) * CFrame.Angles(0, math.pi / 2, 0)
	pieces[2].CFrame = base * CFrame.new(width / 4, height / 2, 0) * CFrame.Angles(0, -math.pi / 2, 0)
end

local function build(quality: number)
	local root = Instance.new("Folder")
	root.Name = "GliderBackdrop"
	root.Parent = workspace
	folder = root
	local random = Random.new(20260924)
	local count = if quality <= 3 then 14 elseif quality <= 6 then 22 else 30
	for index = 1, count do
		local height = random:NextNumber(500, 1150)
		local width = height * random:NextNumber(1.6, 2.6)
		local depth = random:NextNumber(300, 500)
		local peak: Peak = {
			rock = ridge(root, width, height, depth, rgb(120, 130, 130)),
			cap = {},
			angle = (index / count) * 2 * math.pi + random:NextNumber(-0.08, 0.08),
			radius = RADIUS + random:NextNumber(-250, 250),
			width = width,
		}
		if height > 800 then
			peak.cap = ridge(root, width * 0.3, height * 0.3, depth * 0.35, rgb(240, 240, 240))
		end
		table.insert(peaks, peak)
	end
	local cloudCount = if quality <= 3 then 6 elseif quality <= 6 then 10 else 14
	for _ = 1, cloudCount do
		local part = visual(root, "Part", Vector3.new(random:NextNumber(250, 480), random:NextNumber(18, 34), random:NextNumber(140, 260)), rgb(255, 255, 255))
		part.Transparency = 0.25
		table.insert(clouds, { part = part, angle = random:NextNumber(0, 2 * math.pi), radius = random:NextNumber(1100, 1800), height = random:NextNumber(260, 620) })
	end
end

local function recolor(biome: string?)
	local palette = PALETTES[biome or "Pradera"] or PALETTES.Pradera
	local info = TweenInfo.new(4, Enum.EasingStyle.Sine)
	for _, peak in peaks do
		for _, part in peak.rock do
			TweenService:Create(part, info, { Color = palette.rock }):Play()
		end
		for _, part in peak.cap do
			TweenService:Create(part, info, { Color = palette.cap }):Play()
		end
	end
end

local function place(center: Vector3)
	anchor = center
	local baseY = center.Y - 420
	for _, peak in peaks do
		local position = Vector3.new(center.X + math.cos(peak.angle) * peak.radius, baseY, center.Z + math.sin(peak.angle) * peak.radius)
		local base = CFrame.lookAt(position, Vector3.new(center.X, baseY, center.Z))
		placeRidge(peak.rock, base, peak.width)
		if #peak.cap > 0 then
			local height = peak.rock[1].Size.Y
			local capHeight = peak.cap[1].Size.Y
			placeRidge(peak.cap, base * CFrame.new(0, height - capHeight + 1, -2), peak.width * 0.3)
		end
	end
end

-- Cada fotograma (glider = ala montada o nil).
function Backdrop.update(glider: Model?, dt: number)
	if not glider then
		if folder then
			folder:Destroy()
			folder = nil
			table.clear(peaks)
			table.clear(clouds)
			currentBiome = nil
		end
		return
	end
	local camera = workspace.CurrentCamera
	local position = camera.CFrame.Position
	if not folder then
		local ok, quality = pcall(function()
			return UserSettings:GetService("UserGameSettings").SavedQualityLevel.Value
		end)
		build(if ok and type(quality) == "number" and quality > 0 then quality else 6)
		place(position)
	end
	if (Vector3.new(position.X, 0, position.Z) - Vector3.new(anchor.X, 0, anchor.Z)).Magnitude > FOLLOW_STEP or math.abs(position.Y - anchor.Y) > FOLLOW_STEP then
		place(position)
	end
	local value = glider:GetAttribute("Biome")
	local biome = if type(value) == "string" then value else "Pradera"
	if biome ~= currentBiome then
		currentBiome = biome
		recolor(biome)
	end
	-- Nubes: giran muy despacio alrededor de la cámara.
	cloudClock += dt
	for _, cloud in clouds do
		local angle = cloud.angle + cloudClock * 0.004
		local drift = GliderMath.flow(cloudClock * 0.02, cloud.radius) * 40
		cloud.part.CFrame = CFrame.new(anchor.X + math.cos(angle) * cloud.radius, anchor.Y + cloud.height + drift, anchor.Z + math.sin(angle) * cloud.radius) * CFrame.Angles(0, -angle, 0)
	end
end

return Backdrop
