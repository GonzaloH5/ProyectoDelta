--!strict
-- Imagen de tutorial que aparece al unirse a la sala y se cierra con la X de arriba a la derecha.
-- Solo se muestra una vez por sesión (no vuelve a salir al reaparecer tras un choque).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Glider.GliderConfig)

local Tutorial = {}

function Tutorial.show()
	if not Config.ShowTutorialOnJoin then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "GliderTutorial"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100 -- por encima del resto de la interfaz

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Active = true -- los clics no atraviesan el fondo
	backdrop.Parent = gui

	local image = Instance.new("ImageLabel")
	image.Name = "Image"
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromScale(0.85, 0.85)
	image.BackgroundTransparency = 1
	image.Image = Config.TutorialImageId
	image.ScaleType = Enum.ScaleType.Fit
	image.Parent = backdrop

	-- Mantiene la proporción de la imagen para que la X quede justo en su esquina.
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = Config.TutorialImageAspect
	aspect.Parent = image

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.fromOffset(48, 48)
	close.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Font = Enum.Font.GothamBold
	close.TextSize = 26
	close.Text = "X"
	close.Parent = image

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = close

	close.Activated:Connect(function()
		gui:Destroy()
	end)

	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
end

return Tutorial
