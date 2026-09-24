--!strict
-- Vida del ambiente (solo en este cliente, mientras vuela), según el bioma del nivel (atributo Biome):
--   · partículas alrededor de la cámara: polen en la pradera, hojas en el bosque, nieve en el glaciar,
--     brasas en el volcán, destellos en el cristal…
--   · bandadas de pájaros que dan vueltas por los valles abiertos (bajo techo no se ven)
-- La cantidad baja con la calidad gráfica del jugador. Nada colisiona ni cuenta en consultas.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserSettings = UserSettings()

local Config = require(ReplicatedStorage.Glider.GliderConfig)

local Ambient = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local rgb = Color3.fromRGB

type Mood = {
	color: ColorSequence,
	size: NumberSequence,
	rate: number, -- partículas/s con calidad máxima
	speed: NumberRange,
	acceleration: Vector3,
	light: number,
	lifetime: NumberRange,
	spin: boolean?,
	birds: boolean,
}

local function mood(m: Mood): Mood
	return m
end

local MOODS: { [string]: Mood } = {
	Pradera = mood({ color = ColorSequence.new(rgb(255, 250, 200)), size = NumberSequence.new(0.25), rate = 40, speed = NumberRange.new(0.5, 2), acceleration = Vector3.new(0, 0.3, 0), light = 0.6, lifetime = NumberRange.new(4, 7), birds = true }),
	CanonRojo = mood({ color = ColorSequence.new(rgb(255, 200, 150)), size = NumberSequence.new(0.2), rate = 45, speed = NumberRange.new(2, 5), acceleration = Vector3.new(2, 0, 0), light = 0.2, lifetime = NumberRange.new(3, 5), birds = true }),
	BosqueOtonal = mood({ color = ColorSequence.new(rgb(235, 120, 45), rgb(200, 60, 40)), size = NumberSequence.new(0.7), rate = 30, speed = NumberRange.new(1, 3), acceleration = Vector3.new(1, -3, 0), light = 0, lifetime = NumberRange.new(5, 8), spin = true, birds = true }),
	MesasDesierto = mood({ color = ColorSequence.new(rgb(240, 210, 160)), size = NumberSequence.new(0.2), rate = 60, speed = NumberRange.new(4, 8), acceleration = Vector3.new(4, 0, 0), light = 0.1, lifetime = NumberRange.new(2, 4), birds = true }),
	Glaciar = mood({ color = ColorSequence.new(rgb(255, 255, 255)), size = NumberSequence.new(0.45), rate = 90, speed = NumberRange.new(1, 3), acceleration = Vector3.new(0.5, -4, 0), light = 0.3, lifetime = NumberRange.new(4, 6), spin = true, birds = false }),
	Acantilados = mood({ color = ColorSequence.new(rgb(235, 245, 255)), size = NumberSequence.new(0.3), rate = 35, speed = NumberRange.new(1, 3), acceleration = Vector3.new(1.5, 0.5, 0), light = 0.3, lifetime = NumberRange.new(3, 5), birds = true }),
	Selva = mood({ color = ColorSequence.new(rgb(200, 255, 120)), size = NumberSequence.new(0.3), rate = 30, speed = NumberRange.new(0.3, 1.5), acceleration = Vector3.zero, light = 1, lifetime = NumberRange.new(3, 6), birds = true }),
	Volcan = mood({ color = ColorSequence.new(rgb(255, 160, 60), rgb(255, 70, 30)), size = NumberSequence.new(0.35, 0), rate = 55, speed = NumberRange.new(2, 5), acceleration = Vector3.new(0, 5, 0), light = 1, lifetime = NumberRange.new(2, 4), birds = false }),
	Cristal = mood({ color = ColorSequence.new(rgb(200, 170, 255), rgb(120, 230, 255)), size = NumberSequence.new(0.35), rate = 40, speed = NumberRange.new(0.3, 1.2), acceleration = Vector3.zero, light = 1, lifetime = NumberRange.new(3, 6), birds = false }),
	CieloFinal = mood({ color = ColorSequence.new(rgb(255, 255, 255)), size = NumberSequence.new(0.35), rate = 35, speed = NumberRange.new(1, 3), acceleration = Vector3.new(0, 1, 0), light = 0.8, lifetime = NumberRange.new(3, 5), birds = true }),
}

local BIRD_COLOR = rgb(45, 45, 55)

local holder: Part? = nil
local particles: ParticleEmitter? = nil
local currentBiome: string? = nil
local quality = 6
type Bird = { left: BasePart, right: BasePart, offset: Vector3, phase: number }
type Flock = { center: Vector3, radius: number, speed: number, angle: number, birds: { Bird } }
local flocks: { Flock } = {}
local birdFolder: Folder? = nil
local openSky = true
local skyCheck = 0
local clock = 0
local skyParams = RaycastParams.new()
skyParams.FilterType = Enum.RaycastFilterType.Exclude

local function readQuality(): number
	local ok, value = pcall(function()
		return UserSettings:GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	return if ok and type(value) == "number" and value > 0 then value else 6
end

local function visual(parent: Instance, size: Vector3, color: Color3): BasePart
	local part = Instance.new("Part")
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

local function build()
	quality = readQuality()
	local part = Instance.new("Part")
	part.Name = "GliderAmbient"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(160, 90, 160)
	part.Parent = workspace
	holder = part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = part
	particles = emitter

	local folder = Instance.new("Folder")
	folder.Name = "GliderBirds"
	folder.Parent = workspace
	birdFolder = folder
	local flockCount = if quality <= 3 then 1 elseif quality <= 6 then 2 else 3
	for _ = 1, flockCount do
		local flock: Flock = { center = Vector3.zero, radius = 0, speed = 0, angle = 0, birds = {} }
		for index = 1, 5 do
			table.insert(flock.birds, {
				left = visual(folder, Vector3.new(3.2, 0.25, 1.4), BIRD_COLOR),
				right = visual(folder, Vector3.new(3.2, 0.25, 1.4), BIRD_COLOR),
				offset = Vector3.new(math.random(-14, 14), math.random(-6, 6), math.random(-14, 14)) + Vector3.new(0, 0, index * 4),
				phase = math.random() * math.pi * 2,
			})
		end
		flock.center = Vector3.new(0, -1e5, 0) -- se coloca en el primer paso
		table.insert(flocks, flock)
	end
end

local function clear()
	if holder then
		holder:Destroy()
		holder, particles = nil, nil
	end
	if birdFolder then
		birdFolder:Destroy()
		birdFolder = nil
	end
	table.clear(flocks)
	currentBiome = nil
end

local function applyMood(biome: string)
	local m = MOODS[biome] or MOODS.Pradera
	local emitter = particles
	if not emitter then
		return
	end
	emitter.Color = m.color
	emitter.Size = m.size
	emitter.Rate = m.rate * math.clamp(quality / 8, 0.25, 1)
	emitter.Speed = m.speed
	emitter.Acceleration = m.acceleration
	emitter.LightEmission = m.light
	emitter.Lifetime = m.lifetime
	emitter.RotSpeed = if m.spin then NumberRange.new(-120, 120) else NumberRange.new(0)
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.2), NumberSequenceKeypoint.new(0.85, 0.2), NumberSequenceKeypoint.new(1, 1) })
end

local function relocate(flock: Flock, camera: CFrame)
	local ahead = camera.LookVector * Vector3.new(1, 0, 1)
	ahead = if ahead.Magnitude > 1e-3 then ahead.Unit else Vector3.xAxis
	local side = Vector3.new(-ahead.Z, 0, ahead.X)
	flock.center = camera.Position + ahead * math.random(250, 550) + side * math.random(-220, 220) + Vector3.new(0, math.random(-20, 70), 0)
	flock.radius = math.random(40, 110)
	flock.speed = (math.random() * 0.25 + 0.2) * (if math.random() < 0.5 then -1 else 1)
	flock.angle = math.random() * math.pi * 2
end

-- Cada fotograma (glider = ala montada o nil).
function Ambient.update(glider: Model?, dt: number)
	if not glider then
		if holder then
			clear()
		end
		return
	end
	if not holder then
		build()
	end
	local camera = workspace.CurrentCamera.CFrame
	clock += dt
	local value = glider:GetAttribute("Biome")
	local biome = if type(value) == "string" then value else "Pradera"
	if biome ~= currentBiome then
		currentBiome = biome
		applyMood(biome)
	end
	if holder then
		holder.CFrame = CFrame.new(camera.Position + camera.LookVector * 50)
	end

	-- ¿Cielo abierto? (bajo el techo de un corredor no hay pájaros)
	skyCheck -= dt
	if skyCheck <= 0 then
		skyCheck = 1
		local ignore: { Instance } = {}
		local gliders = workspace:FindFirstChild(Config.GliderFolderName)
		if gliders then
			table.insert(ignore, gliders)
		end
		skyParams.FilterDescendantsInstances = ignore
		openSky = workspace:Raycast(camera.Position, Vector3.new(0, 300, 0), skyParams) == nil
	end
	local m = MOODS[biome] or MOODS.Pradera
	local showBirds = openSky and m.birds
	for _, flock in flocks do
		if showBirds and (flock.center - camera.Position).Magnitude > 900 then
			relocate(flock, camera)
		end
		flock.angle += flock.speed * dt
		local heading = flock.angle + (if flock.speed > 0 then math.pi / 2 else -math.pi / 2)
		for _, bird in flock.birds do
			local position = flock.center + Vector3.new(math.cos(flock.angle) * flock.radius, 0, math.sin(flock.angle) * flock.radius) + bird.offset
			local body = CFrame.new(position) * CFrame.Angles(0, -heading, 0)
			local flap = math.sin(clock * 9 + bird.phase) * 0.45
			bird.left.CFrame = body * CFrame.Angles(0, 0, flap) * CFrame.new(-1.5, 0, 0)
			bird.right.CFrame = body * CFrame.Angles(0, 0, -flap) * CFrame.new(1.5, 0, 0)
			bird.left.Transparency = if showBirds then 0 else 1
			bird.right.Transparency = if showBirds then 0 else 1
		end
	end
end

return Ambient
