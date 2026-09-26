--!strict
-- Efectos del vuelo (solo en este cliente) y sus sonidos. Todo sale de los atributos que publica el servidor en
-- el ala y de sus mensajes; nada de esto cambia el vuelo:
--   · golpe (Impacts): chispas en el punto de contacto (ContactPoint) y sonido · roce (Scraping): chispas
--     continuas · rasante (Skimming): polvo bajo el ala
--   · "Close!": pasar muy cerca de una pared u obstáculo sin tocarlo (rayos desde las puntas del ala)
--   · invulnerable tras un golpe: el ala parpadea
--   · reaparición (Respawns): burbuja que se expande · despegue: 3 · 2 · 1 · GO! con sonido
--   · checkpoint: columna de luz y confeti · aterrizaje: polvo
--   · picado rápido: líneas de velocidad en pantalla · giros fuertes: estelas de aire en las puntas
-- Con "reducir movimiento" (Settings) no hay líneas de velocidad.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Glider.GliderConfig)
local FlightAudio = require(script.Parent:WaitForChild("FlightAudio"))
local Settings = require(script.Parent:WaitForChild("Settings"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))

local FlightEffects = {}

local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local NEAR_MISS_REACH = 9 -- studs más allá de la punta del ala que cuentan como "Close!"
local NEAR_MISS_COOLDOWN = 2.5
local SPEED_LINES = 14

local player = Players.LocalPlayer :: Player

-- ── Utilidades ────────────────────────────────────────────────────────

local function anchorAt(position: Vector3): Attachment
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain
	return attachment
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local particles = Instance.new("ParticleEmitter")
	particles.Enabled = false
	particles.LightEmission = 0.6
	particles.Texture = SPARK_TEXTURE
	for key, value in props do
		(particles :: any)[key] = value
	end
	particles.Parent = parent
	return particles
end

-- Ráfaga única de partículas en un punto (se limpia sola).
local function burst(position: Vector3, count: number, props: { [string]: any })
	local attachment = anchorAt(position)
	local particles = emitter(attachment, props)
	particles:Emit(count)
	task.delay(3, function()
		attachment:Destroy()
	end)
end

local function sparks(position: Vector3, count: number)
	burst(position, count, {
		Color = ColorSequence.new(Color3.fromRGB(255, 230, 150), Color3.fromRGB(255, 140, 60)),
		Size = NumberSequence.new(0.9, 0),
		Lifetime = NumberRange.new(0.25, 0.5),
		Speed = NumberRange.new(25, 45),
		SpreadAngle = Vector2.new(70, 70),
		Drag = 4,
		LightEmission = 1,
	})
end

local function dust(position: Vector3, count: number, color: Color3?)
	burst(position, count, {
		Texture = SMOKE_TEXTURE,
		Color = ColorSequence.new(color or Color3.fromRGB(215, 205, 185)),
		Size = NumberSequence.new(3, 9),
		Transparency = NumberSequence.new(0.4, 1),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(4, 10),
		SpreadAngle = Vector2.new(80, 20),
		LightEmission = 0,
	})
end

-- Pieza local, solo visual.
local function visualPart(shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Shape = shape
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = material
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	part.Parent = workspace
	return part
end

-- ── Pantalla: "Close!" y líneas de velocidad ─────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name = "GliderEffects"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 3
UiScale.attach(gui)

local close = Instance.new("TextLabel")
close.AnchorPoint = Vector2.new(0.5, 0.5)
close.Position = UDim2.fromScale(0.5, 0.3)
close.Size = UDim2.fromOffset(300, 50)
close.BackgroundTransparency = 1
close.Font = Enum.Font.GothamBlack
close.TextSize = 40
close.TextColor3 = Color3.fromRGB(120, 230, 255)
close.Text = "Close!"
close.Visible = false
close.Parent = gui
local closeStroke = Instance.new("UIStroke")
closeStroke.Thickness = 3
closeStroke.Transparency = 0.2
closeStroke.Parent = close
local closeScale = Instance.new("UIScale")
closeScale.Parent = close

local lines = Instance.new("Frame")
lines.Size = UDim2.fromScale(1, 1)
lines.BackgroundTransparency = 1
lines.Parent = gui
type Line = { frame: Frame, angle: number, phase: number }
local speedLines: { Line } = {}
for index = 1, SPEED_LINES do
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(120, 2)
	frame.Parent = lines
	table.insert(speedLines, { frame = frame, angle = (index / SPEED_LINES) * 2 * math.pi + math.random() * 0.3, phase = math.random() })
end

gui.Parent = player:WaitForChild("PlayerGui")

local function showClose()
	close.Visible = true
	closeScale.Scale = 1.5
	TweenService:Create(closeScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.8, function()
		close.Visible = false
	end)
end

-- ── Estado por ala montada ────────────────────────────────────────────

local current: Model? = nil
local parts: { BasePart } = {}
local lastImpacts, lastRespawns, lastRings, lastBonks = 0, 0, 0, 0
local hiddenFeathers: { BasePart } = {}
local lastState: string? = nil
local lastCount = -1
local scrapeEmitter: ParticleEmitter? = nil
local scrapeAnchor: Attachment? = nil
local skimEmitter: ParticleEmitter? = nil
local wisps: { ParticleEmitter } = {}
local nearMissTimer, nearMissCooldown = 0, 0
local blinkClock = 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function number(glider: Model, name: string): number
	local value = glider:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function clear()
	for _, part in parts do
		part.LocalTransparencyModifier = 0
	end
	table.clear(parts)
	if scrapeAnchor then
		scrapeAnchor:Destroy()
		scrapeAnchor, scrapeEmitter = nil, nil
	end
	if skimEmitter then
		skimEmitter:Destroy()
		skimEmitter = nil
	end
	for _, wisp in wisps do
		wisp:Destroy()
	end
	table.clear(wisps)
	for _, line in speedLines do
		line.frame.BackgroundTransparency = 1
	end
	for _, feather in hiddenFeathers do
		feather.LocalTransparencyModifier = 0 -- el próximo vuelo las vuelve a tener
	end
	table.clear(hiddenFeathers)
	current = nil
end

local function mount(glider: Model)
	clear()
	current = glider
	lastImpacts, lastRespawns, lastRings, lastBonks = number(glider, "Impacts"), number(glider, "Respawns"), number(glider, "Rings"), number(glider, "Bonks")
	lastState, lastCount = nil, -1
	for _, part in glider:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "Root" and part.Transparency < 1 then
			table.insert(parts, part)
		end
	end
	local root = glider:FindFirstChild("Root")
	if root then
		scrapeAnchor = anchorAt(Vector3.zero)
		scrapeEmitter = emitter(scrapeAnchor :: Attachment, {
			Color = ColorSequence.new(Color3.fromRGB(255, 220, 140)),
			Size = NumberSequence.new(0.6, 0),
			Lifetime = NumberRange.new(0.2, 0.4),
			Speed = NumberRange.new(15, 30),
			SpreadAngle = Vector2.new(60, 60),
			Rate = 60,
			LightEmission = 1,
		})
		local below = Instance.new("Attachment")
		below.Position = Vector3.new(0, -Config.FeetBelowRoot - 2, 0)
		below.Parent = root
		skimEmitter = emitter(below, {
			Texture = SMOKE_TEXTURE,
			Color = ColorSequence.new(Color3.fromRGB(215, 205, 185)),
			Size = NumberSequence.new(4, 10),
			Transparency = NumberSequence.new(0.5, 1),
			Lifetime = NumberRange.new(0.6, 1),
			Speed = NumberRange.new(2, 6),
			Rate = 25,
			LightEmission = 0,
		})
		-- Estelas de aire en las puntas (las Trail del servidor ya marcan la punta; esto añade remolinos).
		for _, name in { "TrailTop1", "TrailTop2" } do
			local tip = root:FindFirstChild(name)
			if tip and tip:IsA("Attachment") then
				local wisp = emitter(tip, {
					Color = ColorSequence.new(Color3.new(1, 1, 1)),
					Size = NumberSequence.new(0.5, 0),
					Transparency = NumberSequence.new(0.3, 1),
					Lifetime = NumberRange.new(0.3, 0.5),
					Speed = NumberRange.new(0, 1),
					Rate = 40,
					LightEmission = 0.8,
				})
				table.insert(wisps, wisp)
			end
		end
	end
	local ignore: { Instance } = {}
	local gliders = workspace:FindFirstChild(Config.GliderFolderName)
	if gliders then
		table.insert(ignore, gliders)
	end
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	rayParams.FilterDescendantsInstances = ignore
end

-- Paso cerca de una pared u obstáculo (no techo ni suelo) sin tocarlo.
local function nearMiss(glider: Model, root: BasePart): boolean
	local span = number(glider, "Span")
	if span <= 0 then
		span = 30
	end
	local frame = root.CFrame
	for _, side in { -1, 1 } do
		local origin = frame.Position + frame.RightVector * side * span * 0.45
		local hit = workspace:Raycast(origin, frame.RightVector * side * (span * 0.05 + NEAR_MISS_REACH), rayParams)
		if hit and math.abs(hit.Normal.Y) < 0.5 then
			return true
		end
	end
	local ahead = workspace:Raycast(frame.Position, frame.LookVector * (NEAR_MISS_REACH + 6), rayParams)
	return ahead ~= nil and math.abs(ahead.Normal.Y) < 0.5
end

-- Cada fotograma (glider = ala montada o nil).
function FlightEffects.update(glider: Model?, dt: number)
	if glider ~= current then
		if glider then
			mount(glider)
		else
			clear()
		end
	end
	if not glider then
		return
	end
	local root = glider:FindFirstChild("Root")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local state = glider:GetAttribute("State")
	local flying = state == "Flying"

	-- Despegue: 3 · 2 · 1 · GO!
	if state == "Countdown" then
		local count = math.ceil(number(glider, "Countdown"))
		if count ~= lastCount and count > 0 then
			FlightAudio.play("Countdown")
		end
		lastCount = count
	elseif flying and lastState == "Countdown" then
		FlightAudio.play("Go")
		lastCount = -1
	end
	if state == "Ended" and lastState == "Flying" and glider:GetAttribute("Completed") ~= true then
		FlightAudio.play("WingLost")
	end
	if state == "Landed" and lastState ~= "Landed" then
		FlightAudio.play("Landing")
		dust(root.Position - Vector3.new(0, Config.FeetBelowRoot, 0), 30)
	end
	lastState = if type(state) == "string" then state else nil

	-- Golpe: chispas y sonido.
	local impacts = number(glider, "Impacts")
	if impacts > lastImpacts then
		local contact = glider:GetAttribute("ContactPoint")
		sparks(if typeof(contact) == "Vector3" then contact else root.Position, 40)
		FlightAudio.play("Impact")
	end
	lastImpacts = impacts
	-- "Bonk" en Flight School (modo práctica): el mismo golpe, pero sin corazón perdido.
	local bonks = number(glider, "Bonks")
	if bonks > lastBonks then
		local contact = glider:GetAttribute("ContactPoint")
		sparks(if typeof(contact) == "Vector3" then contact else root.Position, 30)
		FlightAudio.play("Impact")
	end
	lastBonks = bonks

	-- Anillo de impulso: destello azul y sonido.
	local rings = number(glider, "Rings")
	if rings > lastRings then
		FlightAudio.play("Ring")
		burst(root.Position, 30, {
			Color = ColorSequence.new(Color3.fromRGB(90, 210, 255), Color3.new(1, 1, 1)),
			Size = NumberSequence.new(1, 0),
			Lifetime = NumberRange.new(0.3, 0.6),
			Speed = NumberRange.new(20, 35),
			SpreadAngle = Vector2.new(180, 180),
			LightEmission = 1,
		})
	end
	lastRings = rings

	-- Reaparición: burbuja que se expande.
	local respawns = number(glider, "Respawns")
	if respawns > lastRespawns then
		FlightAudio.play("Respawn")
		local bubble = visualPart(Enum.PartType.Ball, Vector3.one * 12, root.CFrame, Color3.fromRGB(150, 220, 255), Enum.Material.ForceField)
		TweenService:Create(bubble, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 70, Transparency = 1 }):Play()
		task.delay(0.8, function()
			bubble:Destroy()
		end)
	end
	lastRespawns = respawns

	-- Roce y rasante.
	local scraping = flying and glider:GetAttribute("Scraping") == true
	if scrapeEmitter and scrapeAnchor then
		local contact = glider:GetAttribute("ContactPoint")
		if typeof(contact) == "Vector3" then
			scrapeAnchor.WorldPosition = contact
		end
		scrapeEmitter.Enabled = scraping
	end
	if skimEmitter then
		skimEmitter.Enabled = flying and glider:GetAttribute("Skimming") == true
	end
	local turning = math.abs(number(glider, "TurnRate")) / Config.MaxTurnRate
	for _, wisp in wisps do
		wisp.Enabled = flying and turning > 0.45
	end

	-- Invulnerable: el ala parpadea.
	blinkClock += dt
	local blink = glider:GetAttribute("Invulnerable") == true and (blinkClock * 10) % 2 < 1
	for _, part in parts do
		part.LocalTransparencyModifier = if blink then 0.65 else 0
	end

	-- "Close!"
	nearMissCooldown -= dt
	nearMissTimer -= dt
	if flying and not scraping and glider:GetAttribute("Invulnerable") ~= true and nearMissTimer <= 0 then
		nearMissTimer = 0.1
		if nearMissCooldown <= 0 and nearMiss(glider, root) then
			nearMissCooldown = NEAR_MISS_COOLDOWN
			showClose()
			FlightAudio.play("NearMiss")
		end
	end

	-- Líneas de velocidad (picado rápido o mucha velocidad).
	local calm = Settings.get().reduceMotion
	local vertical = number(glider, "VerticalSpeed")
	local speed = number(glider, "Speed")
	local intensity = if flying and not calm then math.clamp(math.max((-vertical - 14) / 14, (speed - 64) / 6), 0, 1) else 0
	for _, line in speedLines do
		if intensity <= 0 then
			line.frame.BackgroundTransparency = 1
			continue
		end
		line.phase = (line.phase + dt * (1.2 + intensity)) % 1
		local radius = 0.25 + line.phase * 0.45
		line.frame.Position = UDim2.fromScale(0.5 + math.cos(line.angle) * radius * 0.6, 0.5 + math.sin(line.angle) * radius)
		line.frame.Rotation = math.deg(line.angle)
		line.frame.BackgroundTransparency = 1 - intensity * 0.55 * (1 - line.phase)
	end
end

-- Pluma recogida (mensaje del servidor): se oculta aquí y suelta destellos dorados.
function FlightEffects.feather(data: { [string]: any })
	local part = data.part
	FlightAudio.play("Feather", 1 + 0.05 * (if type(data.count) == "number" then data.count else 0))
	if typeof(part) == "Instance" and part:IsA("BasePart") then
		part.LocalTransparencyModifier = 1
		table.insert(hiddenFeathers, part)
		burst(part.Position, 20, {
			Color = ColorSequence.new(Color3.fromRGB(255, 225, 90)),
			Size = NumberSequence.new(0.8, 0),
			Lifetime = NumberRange.new(0.4, 0.8),
			Speed = NumberRange.new(8, 18),
			SpreadAngle = Vector2.new(180, 180),
			LightEmission = 1,
		})
	end
end

-- Checkpoint (mensaje del servidor): columna de luz, confeti y sonido según lo conseguido.
function FlightEffects.checkpoint(data: { [string]: any })
	local glider = current
	local root = glider and glider:FindFirstChild("Root")
	if root and root:IsA("BasePart") then
		local color = if typeof(data.color) == "Color3" then data.color else Color3.fromRGB(255, 220, 120)
		local base = root.Position - Vector3.new(0, 120, 0)
		local pillar = visualPart(Enum.PartType.Cylinder, Vector3.new(400, 26, 26), CFrame.new(base + Vector3.new(0, 200, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.Neon)
		pillar.Transparency = 0.35
		TweenService:Create(pillar, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Size = Vector3.new(400, 4, 4) }):Play()
		task.delay(1.7, function()
			pillar:Destroy()
		end)
		burst(root.Position + Vector3.new(0, 6, 0), 70, {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
				ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 220, 80)),
				ColorSequenceKeypoint.new(0.66, Color3.fromRGB(90, 220, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 255, 120)),
			}),
			Size = NumberSequence.new(0.8, 0.5),
			Lifetime = NumberRange.new(1.2, 2),
			Speed = NumberRange.new(20, 40),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, -25, 0),
			Drag = 1.5,
			RotSpeed = NumberRange.new(-200, 200),
			LightEmission = 0.3,
		})
	end
	if data.final == true then
		FlightAudio.play("Finish")
	elseif type(data.chapter) == "number" then
		FlightAudio.play("ChapterClear")
	else
		FlightAudio.play("Checkpoint")
	end
	if type(data.medal) == "number" then
		task.delay(0.5, function()
			FlightAudio.play("Medal", 0.9 + 0.1 * data.medal)
		end)
	end
end

return FlightEffects
