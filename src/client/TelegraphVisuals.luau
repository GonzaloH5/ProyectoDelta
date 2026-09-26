--!strict
-- Avisos visuales por capas (los construye MapBuilder; aquí se animan, solo en este cliente):
--   · luces en secuencia (Chevron con TelegraphGroup / TelegraphOrder): se encienden en cadena hacia el hueco,
--     como las luces de una pista, y aparecen al acercarse (invisibles a más de FAR studs);
--   · velos de luz en los huecos (TelegraphLayer "veil");
--   · aviso cercano (marcadores CueNN con CueU / CueV): ~1-1,8 s antes del paso, flecha en el borde de la pantalla
--     hacia donde hay que ir, sonido (agudo = subir, grave = bajar, medio = girar) y vibración del mando;
--   · compuertas: luz en el borde de cada puerta, roja con el hueco cerrado y verde abierto, y "bip… bip… ¡ya!"
--     al acercarse para llegar con el hueco máximo.
-- Cuánto se ve: ajuste telegraphMode (0 mínimo · 1 normal = lo que diga el nivel, TelegraphLevel · 2 siempre
-- completo). En mínimo quedan la silueta (franjas, aros), los paneles de curva y los avisos de los móviles.

local CollectionService = game:GetService("CollectionService")
local HapticService = game:GetService("HapticService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Movers = require(ReplicatedStorage:WaitForChild("Glider"):WaitForChild("Movers"))
local FlightAudio = require(script.Parent:WaitForChild("FlightAudio"))
local Settings = require(script.Parent:WaitForChild("Settings"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))

local TelegraphVisuals = {}

local FAR, NEAR = 520, 260 -- studs: a partir de FAR empiezan a verse las luces; a NEAR, del todo
local STEP = 1 / 7 -- s que dura encendida cada luz de la secuencia
local DIM = 0.72 -- transparencia de las luces apagadas de la secuencia
local CUE_FROM, CUE_TO = 110, 55 -- studs por delante del ala en los que salta el aviso cercano (≈1-1,8 s)
local GATE_REACH = 260 -- studs antes de una compuerta en los que suena el "bip… bip… ¡ya!"
local MOVER_TAG = "GliderMoverVisual"

type Light = { part: BasePart, group: string, order: number, level: Instance? }
local lights: { Light } = {}
local veils: { { part: BasePart, level: Instance? } } = {}
local cues: { { part: BasePart, level: Instance?, done: boolean } } = {}

local function levelOf(instance: Instance): Instance?
	local node: Instance? = instance
	while node and not node.Name:match("^Level%d+$") do
		node = node.Parent
	end
	return node
end

-- ¿Se ven las capas completas en este nivel?
local function fullIn(level: Instance?): boolean
	local mode = math.floor((Settings.get() :: any).telegraphMode + 0.5)
	if mode >= 2 then
		return true
	elseif mode <= 0 then
		return false
	end
	return level == nil or level:GetAttribute("TelegraphLevel") ~= "minimal"
end

local function track(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local order = instance:GetAttribute("TelegraphOrder")
	if type(order) == "number" then
		local level = levelOf(instance)
		table.insert(lights, { part = instance, group = tostring(level) .. ":" .. tostring(instance:GetAttribute("TelegraphGroup")), order = order, level = level })
		instance.Transparency = 1
	elseif instance:GetAttribute("TelegraphLayer") == "veil" then
		table.insert(veils, { part = instance, level = levelOf(instance) })
	elseif instance:GetAttribute("CueU") ~= nil then
		table.insert(cues, { part = instance, level = levelOf(instance), done = false })
	end
end

local map = workspace:WaitForChild("Map", 30)
if map then
	for _, d in map:GetDescendants() do
		track(d)
	end
	map.DescendantAdded:Connect(track)
end

-- ── Aviso cercano en pantalla ─────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "GliderTelegraphs"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 2
UiScale.attach(gui)
local arrow = Instance.new("TextLabel")
arrow.AnchorPoint = Vector2.new(0.5, 0.5)
arrow.Size = UDim2.fromOffset(90, 90)
arrow.BackgroundTransparency = 1
arrow.Font = Enum.Font.GothamBlack
arrow.TextSize = 80
arrow.Text = "▲"
arrow.TextColor3 = Color3.fromRGB(255, 215, 70)
arrow.TextTransparency = 1
arrow.Parent = gui
local arrowStroke = Instance.new("UIStroke")
arrowStroke.Thickness = 4
arrowStroke.Color = Color3.fromRGB(40, 30, 10)
arrowStroke.Transparency = 1
arrowStroke.Parent = arrow
gui.Parent = (game:GetService("Players").LocalPlayer :: Player):WaitForChild("PlayerGui")

local function pulse(angle: number)
	-- angle: 0 = derecha, 90° = arriba (pantalla). La flecha va al borde y apunta hacia fuera.
	arrow.Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.36, 0.5 - math.sin(angle) * 0.3)
	arrow.Rotation = 90 - math.deg(angle)
	arrow.TextTransparency = 0
	arrowStroke.Transparency = 0.2
	arrow.Size = UDim2.fromOffset(120, 120)
	local info = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(arrow, info, { TextTransparency = 1, Size = UDim2.fromOffset(80, 80) }):Play()
	TweenService:Create(arrowStroke, info, { Transparency = 1 }):Play()
end

local function rumble()
	local ok, supported = pcall(function()
		return HapticService:IsVibrationSupported(Enum.UserInputType.Gamepad1)
	end)
	if ok and supported then
		pcall(function()
			HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0.5)
		end)
		task.delay(0.12, function()
			pcall(function()
				HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0)
			end)
		end)
	end
end

-- ── Compuertas: luz roja/verde y "bip… bip… ¡ya!" ─────────────────────
type Gate = { part: BasePart, params: Movers.Params, light: Part, lastK: number }
local gates: { [BasePart]: Gate } = {}
local RED, GREEN = Color3.fromRGB(255, 70, 60), Color3.fromRGB(90, 255, 120)

local function addMover(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local params = Movers.read(instance)
	if not params or params.motion ~= "gate" then
		return
	end
	local light = Instance.new("Part")
	light.Name = "GateLight"
	light.Anchored = true
	light.CanCollide = false
	light.CanQuery = false
	light.CanTouch = false
	light.CastShadow = false
	light.Material = Enum.Material.Neon
	light.Size = Vector3.new(2, instance.Size.Y, instance.Size.Z + 1)
	light.Parent = workspace.CurrentCamera
	gates[instance] = { part = instance, params = params, light = light, lastK = 0 }
end
for _, instance in CollectionService:GetTagged(MOVER_TAG) do
	addMover(instance)
end
CollectionService:GetInstanceAddedSignal(MOVER_TAG):Connect(addMover)
CollectionService:GetInstanceRemovedSignal(MOVER_TAG):Connect(function(instance)
	local gate = gates[instance :: BasePart]
	if gate then
		gate.light:Destroy()
		gates[instance :: BasePart] = nil
	end
end)

-- ── Cada fotograma ────────────────────────────────────────────────────
local current: Model? = nil
function TelegraphVisuals.update(glider: Model?)
	if glider ~= current then
		current = glider
		for _, cue in cues do
			cue.done = false
		end
	end
end

RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local lit = math.floor(os.clock() / STEP) % 7 + 1 -- 1-5 = luz encendida · 6-7 = pausa antes de repetir

	for _, light in lights do
		local part = light.part
		local distance = (part.Position - eye).Magnitude
		if distance > FAR or not fullIn(light.level) then
			part.Transparency = 1
			continue
		end
		local fade = math.clamp((FAR - distance) / (FAR - NEAR), 0, 1)
		local base = if light.order == lit then 0 else DIM
		part.Transparency = 1 - (1 - base) * fade
	end
	for _, veil in veils do
		veil.part.Transparency = if fullIn(veil.level) then 0.86 else 1
	end

	-- Aviso cercano: el próximo paso por delante del ala.
	local root = current and current:FindFirstChild("Root")
	local flying = current ~= nil and current:GetAttribute("State") == "Flying"
	if root and root:IsA("BasePart") and flying then
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 1e-3 then
			local frame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
			for _, cue in cues do
				if cue.done or not fullIn(cue.level) then
					continue
				end
				local offset = frame:PointToObjectSpace(cue.part.Position)
				local ahead = -offset.Z
				if ahead < CUE_FROM and ahead > CUE_TO and math.abs(offset.X) < 160 and math.abs(offset.Y) < 160 then
					cue.done = true
					local u = cue.part:GetAttribute("CueU") :: number
					local v = cue.part:GetAttribute("CueV") :: number
					pulse(math.atan2(v, u))
					FlightAudio.play(if math.abs(v) >= math.abs(u) then (if v > 0 then "CueUp" else "CueDown") else "CueSide")
					rumble()
				elseif ahead < 0 and ahead > -200 then
					cue.done = true -- ya pasado (p. ej. se montó a mitad del nivel)
				end
			end
		end
	end

	-- Compuertas.
	local now = Movers.now()
	for _, gate in gates do
		local params = gate.params
		if (params.pivot.Position - eye).Magnitude > 700 then
			gate.light.Transparency = 1
			continue
		end
		local open, k = Movers.gateOpenness(params, now)
		gate.light.Transparency = 0.1
		gate.light.Color = RED:Lerp(GREEN, open)
		-- En el borde interior de la puerta (el que da al hueco).
		gate.light.CFrame = gate.part.CFrame * CFrame.new(-params.side * (params.doorWidth / 2 + 0.6), 0, 0)
		if params.side > 0 and root and root:IsA("BasePart") and flying then
			local toGate = params.pivot:PointToObjectSpace(root.Position)
			local before = toGate.Z -- el marco mira hacia delante (-Z): antes de la compuerta, Z > 0
			if before > 30 and before < GATE_REACH and math.abs(toGate.X) < 150 then
				for _, mark in { { 0.2, 1 }, { 0.32, 1 }, { 0.44, 1.5 } } do
					if gate.lastK < mark[1] and k >= mark[1] then
						FlightAudio.play("GateBeep", mark[2])
					end
				end
			end
		end
		gate.lastK = k
	end
end)

return TelegraphVisuals
