--!strict
-- Botón LOBBY (centro derecha) mientras vas en el ala: devuelve a TODO el dúo al lobby y cancela el vuelo.
-- Pide confirmación (segundo clic antes de CONFIRM_TIME s): un clic sin querer cortaría también el vuelo
-- del compañero. Con mando: botón X (dos veces). El servidor decide; el cliente solo lo pide.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local remote = ReplicatedStorage:WaitForChild("Glider"):WaitForChild("GliderRemote") :: RemoteEvent
local UiScale = require(script.Parent:WaitForChild("UiScale"))

local LobbyButton = {}

local CONFIRM_TIME = 3
local IDLE_TEXT, CONFIRM_TEXT = "LOBBY", "SURE?"
local IDLE_HINT, CONFIRM_HINT = "Sends your whole duo back", "Tap again to confirm"
local IDLE_COLOR, CONFIRM_COLOR = Color3.fromRGB(60, 120, 225), Color3.fromRGB(235, 140, 40)

local gui = Instance.new("ScreenGui")
gui.Name = "GliderLobby"
gui.ResetOnSpawn = false
gui.Enabled = false
UiScale.attach(gui)

local button = Instance.new("TextButton")
button.Name = "Lobby"
button.AnchorPoint = Vector2.new(1, 0.5)
button.Position = UDim2.new(1, -20, 0.5, 0)
button.Size = UDim2.fromOffset(150, 52)
button.BackgroundColor3 = IDLE_COLOR
button.TextColor3 = Color3.new(1, 1, 1)
button.Font = Enum.Font.GothamBold
button.TextSize = 22
button.Text = IDLE_TEXT
button.AutoButtonColor = true
button.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = button

local stroke = Instance.new("UIStroke")
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Color = Color3.new(1, 1, 1)
stroke.Thickness = 2
stroke.Transparency = 0.4
stroke.Parent = button

local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 0)
hint.Position = UDim2.new(0.5, 0, 1, 6)
hint.Size = UDim2.new(1, 20, 0, 16)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 13
hint.TextColor3 = Color3.new(1, 1, 1)
hint.TextStrokeTransparency = 0.4
hint.Text = IDLE_HINT
hint.Parent = button

gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

local confirming = false
local token = 0

local function setConfirming(value: boolean)
	confirming = value
	button.Text = if value then CONFIRM_TEXT else IDLE_TEXT
	hint.Text = if value then CONFIRM_HINT else IDLE_HINT
	button.BackgroundColor3 = if value then CONFIRM_COLOR else IDLE_COLOR
end

local function press()
	if not gui.Enabled then
		return
	end
	if confirming then
		setConfirming(false)
		remote:FireServer("Lobby")
		return
	end
	setConfirming(true)
	token += 1
	local mine = token
	task.delay(CONFIRM_TIME, function()
		if token == mine and confirming then
			setConfirming(false)
		end
	end)
end

button.Activated:Connect(press)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.ButtonX then
		press()
	end
end)

-- Solo visible mientras el jugador va en el ala.
function LobbyButton.setVisible(visible: boolean)
	gui.Enabled = visible
	setConfirming(false)
	if visible and UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		button.Text = IDLE_TEXT .. " (X)"
	end
end

return LobbyButton
