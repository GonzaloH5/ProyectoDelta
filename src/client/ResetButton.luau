--!strict
-- Botón en pantalla (tecla R, botón Y del mando) que pide al servidor reaparecer en el último punto seguro
-- (checkpoint o tramo reciente de vuelo limpio): ala y ambos jugadores, con cuenta atrás corta. Sirve para
-- salir de un atasco; cuenta como ala perdida para el "viento a favor". El servidor decide si lo acepta.
-- En pantallas táctiles se coloca arriba a la derecha (abajo están los botones de control).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local remote = ReplicatedStorage:WaitForChild("Glider"):WaitForChild("GliderRemote") :: RemoteEvent
local UiScale = require(script.Parent:WaitForChild("UiScale"))

local ResetButton = {}

local gui = Instance.new("ScreenGui")
gui.Name = "GliderReset"
gui.ResetOnSpawn = false
gui.Enabled = false
UiScale.attach(gui)

local button = Instance.new("TextButton")
button.Name = "Reset"
button.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
button.TextColor3 = Color3.new(1, 1, 1)
button.Font = Enum.Font.GothamBold
button.TextSize = 20
button.AutoButtonColor = true
button.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = button

gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

-- Posición y texto según el dispositivo (se recalcula al mostrarse).
local function layout()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		button.AnchorPoint = Vector2.new(1, 0)
		button.Position = UDim2.new(1, -16, 0, 72) -- bajo el cronómetro del HUD
		button.Size = UDim2.fromOffset(130, 42)
		button.Text = "RESPAWN"
	else
		button.AnchorPoint = Vector2.new(1, 1)
		button.Position = UDim2.new(1, -20, 1, -20)
		button.Size = UDim2.fromOffset(150, 48)
		button.Text = if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then "RESPAWN (Y)" else "RESPAWN (R)"
	end
end

local function requestReset()
	if gui.Enabled then
		remote:FireServer("Reset")
	end
end

button.Activated:Connect(requestReset)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonY then
		requestReset()
	end
end)

-- Solo visible mientras el jugador va en el ala.
function ResetButton.setVisible(visible: boolean)
	if visible then
		layout()
	end
	gui.Enabled = visible
end

return ResetButton
