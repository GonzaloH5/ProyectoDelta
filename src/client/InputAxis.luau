--!strict
-- Eje de control -1 (izquierda) / 0 / 1 (derecha) a partir de cualquier dispositivo:
--   · teclado: A/D o flechas
--   · mando: gatillos L2 = izquierda, R2 = derecha (también cruceta y stick izquierdo)
--   · táctil: dos botones grandes ◀ ▶ abajo a los lados, solo mientras se vuela
-- Balanceo (impulso): Espacio · botón A del mando · botón táctil PUMP (InputAxis.pump).
-- Si se pulsan los dos lados a la vez, se anulan (0), igual que con A+D.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local UiScale = require(script.Parent:WaitForChild("UiScale"))

local InputAxis = {}

local TRIGGER_THRESHOLD = 0.3 -- cuánto hay que apretar el gatillo
local STICK_THRESHOLD = 0.5
local IDLE_COLOR, PRESSED_COLOR = Color3.fromRGB(25, 30, 40), Color3.fromRGB(255, 205, 50)

local touch = { left = false, right = false, pump = false }

-- ── Botones táctiles ──────────────────────────────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name = "GliderTouch"
gui.ResetOnSpawn = false
gui.Enabled = false
UiScale.attach(gui)

local function touchButton(side: string, text: string): TextButton
	local isLeft = side == "left"
	local button = Instance.new("TextButton")
	button.Name = if isLeft then "Left" else "Right"
	button.AnchorPoint = Vector2.new(if isLeft then 0 else 1, 1)
	button.Position = if isLeft then UDim2.new(0, 28, 1, -28) else UDim2.new(1, -28, 1, -28)
	button.Size = UDim2.fromOffset(136, 136)
	button.BackgroundColor3 = IDLE_COLOR
	button.BackgroundTransparency = 0.35
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBlack
	button.TextSize = 64
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = text
	button.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 3
	stroke.Transparency = 0.3
	stroke.Parent = button

	-- Se mantiene pulsado mientras el dedo siga apoyado (aunque se deslice fuera del botón).
	local function setPressed(pressed: boolean)
		touch[side] = pressed
		button.BackgroundColor3 = if pressed then PRESSED_COLOR else IDLE_COLOR
		button.TextColor3 = if pressed then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
	end
	button.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		setPressed(true)
		local connection: RBXScriptConnection
		connection = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
			if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
				connection:Disconnect()
				setPressed(false)
			end
		end)
	end)
	return button
end

touchButton("left", "<")
touchButton("right", ">")
local pumpButton = touchButton("pump", "⇑")
pumpButton.Name = "Pump"
pumpButton.AnchorPoint = Vector2.new(1, 1)
pumpButton.Position = UDim2.new(1, -28, 1, -180)
pumpButton.Size = UDim2.fromOffset(104, 104)
pumpButton.TextSize = 44
gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

-- ── Lectura ───────────────────────────────────────────────────────────

local function gamepadSides(): (boolean, boolean)
	if not UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) then
		return false, false
	end
	local left, right = false, false
	for _, input in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		local key = input.KeyCode
		if key == Enum.KeyCode.ButtonL2 and input.Position.Z > TRIGGER_THRESHOLD then
			left = true
		elseif key == Enum.KeyCode.ButtonR2 and input.Position.Z > TRIGGER_THRESHOLD then
			right = true
		elseif key == Enum.KeyCode.Thumbstick1 then
			left = left or input.Position.X < -STICK_THRESHOLD
			right = right or input.Position.X > STICK_THRESHOLD
		end
	end
	left = left or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.DPadLeft)
	right = right or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.DPadRight)
	return left, right
end

function InputAxis.read(): number
	if UserInputService:GetFocusedTextBox() then
		return 0 -- escribiendo en el chat
	end
	local left = UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) or touch.left
	local right = UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) or touch.right
	local padLeft, padRight = gamepadSides()
	left, right = left or padLeft, right or padRight
	return (if right then 1 else 0) - (if left then 1 else 0)
end

-- ¿Se está balanceando? (Espacio, A del mando o el botón táctil).
function InputAxis.pump(): boolean
	if UserInputService:GetFocusedTextBox() then
		return false
	end
	return UserInputService:IsKeyDown(Enum.KeyCode.Space)
		or touch.pump
		or (UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) and UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA))
end

-- Botones táctiles visibles solo mientras se vuela y en dispositivos táctiles.
function InputAxis.setEnabled(enabled: boolean)
	gui.Enabled = enabled and UserInputService.TouchEnabled
	if not enabled then
		touch.left, touch.right, touch.pump = false, false, false
	end
end

return InputAxis
