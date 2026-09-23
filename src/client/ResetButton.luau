--!strict
-- Pruebas: botón en pantalla (y tecla R) que pide al servidor volver al último checkpoint (o a la salida):
-- ala y ambos jugadores, con cuenta atrás. El servidor decide si lo acepta; el cliente solo lo pide.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local remote = ReplicatedStorage:WaitForChild("Glider"):WaitForChild("GliderRemote") :: RemoteEvent

local ResetButton = {}

local gui = Instance.new("ScreenGui")
gui.Name = "GliderReset"
gui.ResetOnSpawn = false
gui.Enabled = false

local button = Instance.new("TextButton")
button.Name = "Reset"
button.AnchorPoint = Vector2.new(1, 1)
button.Position = UDim2.new(1, -20, 1, -20)
button.Size = UDim2.fromOffset(150, 48)
button.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
button.TextColor3 = Color3.new(1, 1, 1)
button.Font = Enum.Font.GothamBold
button.TextSize = 20
button.Text = "RESET (R)"
button.AutoButtonColor = true
button.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = button

gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

local function requestReset()
	if gui.Enabled then
		remote:FireServer("Reset")
	end
end

button.Activated:Connect(requestReset)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.R then
		requestReset()
	end
end)

-- Solo visible mientras el jugador va en el ala.
function ResetButton.setVisible(visible: boolean)
	gui.Enabled = visible
end

return ResetButton
