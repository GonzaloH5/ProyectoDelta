--!strict
-- Panel de ajustes: botón ⚙ (izquierda, a media altura; siempre visible) que abre volúmenes, temblor de cámara,
-- reducir movimiento y tamaño del HUD. Cada cambio se aplica al momento (Settings) y el servidor lo guarda.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Settings = require(script.Parent:WaitForChild("Settings"))
local UiScale = require(script.Parent:WaitForChild("UiScale"))

local SettingsPanel = {}

local PANEL = Color3.fromRGB(18, 22, 30)
local TRACK = Color3.fromRGB(60, 68, 84)
local ON = Color3.fromRGB(80, 200, 110)
local OFF = Color3.fromRGB(90, 98, 115)
local ACCENT = Color3.fromRGB(255, 205, 50)
local HUD_STEP = 0.05

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function text(parent: Instance, size: number, font: Enum.Font?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = font or Enum.Font.GothamBold
	label.TextSize = size
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = ""
	label.Parent = parent
	return label
end

local gui = Instance.new("ScreenGui")
gui.Name = "GliderSettings"
gui.ResetOnSpawn = false
gui.DisplayOrder = 60
UiScale.attach(gui)

local gear = Instance.new("TextButton")
gear.Name = "SettingsButton"
gear.AnchorPoint = Vector2.new(0, 0.5)
gear.Position = UDim2.new(0, 16, 0.5, 0)
gear.Size = UDim2.fromOffset(46, 46)
gear.BackgroundColor3 = PANEL
gear.BackgroundTransparency = 0.25
gear.Font = Enum.Font.GothamBold
gear.TextSize = 26
gear.TextColor3 = Color3.new(1, 1, 1)
gear.Text = "⚙"
gear.Parent = gui
corner(gear, UDim.new(1, 0))

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0, 0.5)
panel.Position = UDim2.new(0, 72, 0.5, 0)
panel.Size = UDim2.fromOffset(340, 356)
panel.BackgroundColor3 = PANEL
panel.BackgroundTransparency = 0.05
panel.Visible = false
panel.Parent = gui
corner(panel, UDim.new(0, 14))
local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 18)
padding.PaddingRight = UDim.new(0, 18)
padding.PaddingTop = UDim.new(0, 14)
padding.Parent = panel
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 10)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = panel

local order = 0
local function row(height: number): Frame
	order += 1
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = order
	frame.Parent = panel
	return frame
end

local header = row(30)
local title = text(header, 22, Enum.Font.GothamBlack)
title.Size = UDim2.fromScale(1, 1)
title.Text = "SETTINGS"
local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.fromScale(1, 0)
close.Size = UDim2.fromOffset(30, 30)
close.BackgroundColor3 = OFF
close.Font = Enum.Font.GothamBold
close.TextSize = 18
close.TextColor3 = Color3.new(1, 1, 1)
close.Text = "✕"
close.Parent = header
corner(close, UDim.new(1, 0))

local refreshers: { () -> () } = {}

-- Deslizador 0-100 % para un ajuste numérico entre 0 y 1.
local function slider(caption: string, key: string)
	local frame = row(44)
	local label = text(frame, 15)
	label.Size = UDim2.new(1, 0, 0, 18)
	local value = text(frame, 15)
	value.Size = UDim2.new(1, 0, 0, 18)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.TextColor3 = ACCENT
	local track = Instance.new("TextButton")
	track.AutoButtonColor = false
	track.Text = ""
	track.Position = UDim2.fromOffset(0, 26)
	track.Size = UDim2.new(1, 0, 0, 12)
	track.BackgroundColor3 = TRACK
	track.Parent = frame
	corner(track, UDim.new(1, 0))
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = ACCENT
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner(fill, UDim.new(1, 0))
	local function refresh()
		local current = (Settings.get() :: any)[key] :: number
		label.Text = caption
		value.Text = string.format("%d%%", math.floor(current * 100 + 0.5))
		fill.Size = UDim2.fromScale(current, 1)
	end
	local dragging = false
	local function setFrom(x: number)
		local fraction = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		Settings.set(key, math.floor(fraction * 20 + 0.5) / 20)
	end
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFrom(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFrom(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	table.insert(refreshers, refresh)
end

-- Interruptor ON/OFF para un ajuste booleano.
local function toggle(caption: string, key: string)
	local frame = row(32)
	local label = text(frame, 15)
	label.Size = UDim2.new(1, -80, 1, 0)
	label.Text = caption
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.fromScale(1, 0.5)
	button.Size = UDim2.fromOffset(70, 28)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Parent = frame
	corner(button, UDim.new(1, 0))
	local function refresh()
		local on = (Settings.get() :: any)[key] == true
		button.Text = if on then "ON" else "OFF"
		button.BackgroundColor3 = if on then ON else OFF
	end
	button.Activated:Connect(function()
		Settings.set(key, not ((Settings.get() :: any)[key] == true))
	end)
	table.insert(refreshers, refresh)
end

slider("Master volume", "masterVolume")
slider("Effects", "effectsVolume")
slider("Ambience", "ambienceVolume")
toggle("Camera shake", "cameraShake")
toggle("Reduce motion", "reduceMotion")

-- Tamaño del HUD: − / + en pasos de 5 %.
do
	local frame = row(32)
	local label = text(frame, 15)
	label.Size = UDim2.new(1, -120, 1, 0)
	label.Text = "HUD size"
	local function stepButton(caption: string, x: number, delta: number)
		local button = Instance.new("TextButton")
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, x, 0.5, 0)
		button.Size = UDim2.fromOffset(30, 28)
		button.BackgroundColor3 = OFF
		button.Font = Enum.Font.GothamBlack
		button.TextSize = 18
		button.TextColor3 = Color3.new(1, 1, 1)
		button.Text = caption
		button.Parent = frame
		corner(button, UDim.new(0, 8))
		button.Activated:Connect(function()
			local scale = Settings.get().hudScale + delta
			Settings.set("hudScale", math.floor(scale / HUD_STEP + 0.5) * HUD_STEP)
		end)
	end
	stepButton("+", 0, HUD_STEP)
	stepButton("−", -80, -HUD_STEP)
	local value = text(frame, 15)
	value.AnchorPoint = Vector2.new(1, 0.5)
	value.Position = UDim2.new(1, -34, 0.5, 0)
	value.Size = UDim2.fromOffset(44, 20)
	value.TextXAlignment = Enum.TextXAlignment.Center
	value.TextColor3 = ACCENT
	table.insert(refreshers, function()
		value.Text = string.format("%d%%", math.floor(Settings.get().hudScale * 100 + 0.5))
	end)
end

local function refreshAll()
	for _, refresh in refreshers do
		refresh()
	end
end
refreshAll()
Settings.Changed:Connect(refreshAll)

gear.Activated:Connect(function()
	panel.Visible = not panel.Visible
end)
close.Activated:Connect(function()
	panel.Visible = false
end)

gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

function SettingsPanel.close()
	panel.Visible = false
end

return SettingsPanel
