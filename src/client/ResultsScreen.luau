--!strict
-- Pantalla de resultados al volver al lobby tras aterrizar en la meta ("Results" del servidor):
-- tiempo del recorrido, medallas de este vuelo, alas perdidas y golpes, y el resultado de la clasificación del
-- dúo cuando llega ("DuoResult"). Botón CONTINUE para cerrarla.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UiScale = require(script.Parent:WaitForChild("UiScale"))

local ResultsScreen = {}

local PANEL = Color3.fromRGB(18, 22, 30)
local GOLD, SILVER, BRONZE = Color3.fromRGB(255, 205, 50), Color3.fromRGB(215, 225, 240), Color3.fromRGB(215, 140, 80)
local GREEN = Color3.fromRGB(80, 200, 110)

local function text(parent: Instance, font: Enum.Font, size: number, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = size
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.Text = ""
	label.Parent = parent
	return label
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function formatTime(seconds: number): string
	local minutes = math.floor(seconds / 60)
	return string.format("%d:%05.2f", minutes, seconds - minutes * 60)
end

local gui = Instance.new("ScreenGui")
gui.Name = "GliderResults"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 90
gui.Enabled = false
UiScale.attach(gui)

local backdrop = Instance.new("Frame")
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
backdrop.BackgroundTransparency = 0.45
backdrop.Active = true
backdrop.Parent = gui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(520, 400)
panel.BackgroundColor3 = PANEL
panel.Parent = backdrop
corner(panel, 16)
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local title = text(panel, Enum.Font.GothamBlack, 36)
title.Position = UDim2.fromOffset(0, 20)
title.Size = UDim2.new(1, 0, 0, 42)
title.Text = "COURSE COMPLETE!"
local timeText = text(panel, Enum.Font.RobotoMono, 44, GOLD)
timeText.Position = UDim2.fromOffset(0, 70)
timeText.Size = UDim2.new(1, 0, 0, 50)
local rankText = text(panel, Enum.Font.GothamBold, 18, GOLD)
rankText.Position = UDim2.fromOffset(0, 122)
rankText.Size = UDim2.new(1, 0, 0, 22)

local medalRow = Instance.new("Frame")
medalRow.AnchorPoint = Vector2.new(0.5, 0)
medalRow.Position = UDim2.new(0.5, 0, 0, 160)
medalRow.Size = UDim2.fromOffset(420, 80)
medalRow.BackgroundTransparency = 1
medalRow.Parent = panel
local medalLayout = Instance.new("UIListLayout")
medalLayout.FillDirection = Enum.FillDirection.Horizontal
medalLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
medalLayout.Padding = UDim.new(0, 26)
medalLayout.Parent = medalRow
local medalCounts: { [string]: TextLabel } = {}
local MEDAL_ROW: { { name: string, color: Color3 } } = {
	{ name = "GOLD", color = GOLD },
	{ name = "SILVER", color = SILVER },
	{ name = "BRONZE", color = BRONZE },
}
for index, medal in MEDAL_ROW do
	local slot = Instance.new("Frame")
	slot.Size = UDim2.fromOffset(100, 80)
	slot.BackgroundTransparency = 1
	slot.LayoutOrder = index
	slot.Parent = medalRow
	local disc = Instance.new("Frame")
	disc.AnchorPoint = Vector2.new(0.5, 0)
	disc.Position = UDim2.fromScale(0.5, 0)
	disc.Size = UDim2.fromOffset(52, 52)
	disc.BackgroundColor3 = medal.color
	disc.Parent = slot
	corner(disc, 26)
	local count = text(disc, Enum.Font.GothamBlack, 24, Color3.fromRGB(40, 30, 20))
	count.Size = UDim2.fromScale(1, 1)
	local name = text(slot, Enum.Font.GothamBold, 14, medal.color)
	name.Position = UDim2.fromOffset(0, 58)
	name.Size = UDim2.new(1, 0, 0, 18)
	name.Text = medal.name
	medalCounts[medal.name] = count
end

local stats = text(panel, Enum.Font.GothamMedium, 18, Color3.fromRGB(215, 222, 235))
stats.Position = UDim2.fromOffset(20, 256)
stats.Size = UDim2.new(1, -40, 0, 48)
stats.TextWrapped = true

local continueButton = Instance.new("TextButton")
continueButton.AnchorPoint = Vector2.new(0.5, 1)
continueButton.Position = UDim2.new(0.5, 0, 1, -22)
continueButton.Size = UDim2.fromOffset(220, 54)
continueButton.BackgroundColor3 = GREEN
continueButton.Font = Enum.Font.GothamBold
continueButton.TextSize = 22
continueButton.TextColor3 = Color3.new(1, 1, 1)
continueButton.Text = "CONTINUE"
continueButton.Parent = panel
corner(continueButton, 10)
continueButton.Activated:Connect(function()
	gui.Enabled = false
end)

gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

local lastDuoResult: { [string]: any }? = nil
local lastDuoClock = -math.huge

local function showRank(data: { [string]: any })
	local rank = if type(data.rank) == "number" then data.rank else nil
	if data.duoRecord == true then
		rankText.Text = if rank then string.format("NEW DUO RECORD  ·  #%d ON THE BOARD", rank) else "NEW DUO RECORD!"
	elseif data.personalBest == true then
		rankText.Text = "NEW PERSONAL BEST!"
	elseif rank then
		rankText.Text = string.format("#%d ON THE DUO BOARD", rank)
	end
end

-- data = { time, levels, gold, silver, bronze, losses, hits, practice }
function ResultsScreen.show(data: { [string]: any })
	local time = if type(data.time) == "number" then data.time else 0
	timeText.Text = formatTime(time)
	rankText.Text = if data.practice == true then "Practice run (started mid-course): not on the board" else ""
	medalCounts.GOLD.Text = tostring(data.gold or 0)
	medalCounts.SILVER.Text = tostring(data.silver or 0)
	medalCounts.BRONZE.Text = tostring(data.bronze or 0)
	local losses = if type(data.losses) == "number" then data.losses else 0
	local hits = if type(data.hits) == "number" then data.hits else 0
	stats.Text = string.format("%d levels  ·  %s  ·  %s", data.levels or 0, if losses == 0 then "no wings lost!" else string.format("%d wing%s lost", losses, if losses == 1 then "" else "s"), if hits == 0 then "no hits" else string.format("%d hit%s", hits, if hits == 1 then "" else "s"))
	if lastDuoResult and os.clock() - lastDuoClock < 30 and data.practice ~= true then
		showRank(lastDuoResult)
	end
	gui.Enabled = true
	panelScale.Scale = 0.7
	TweenService:Create(panelScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Resultado de la clasificación (puede llegar antes o después de la pantalla).
function ResultsScreen.duoResult(data: { [string]: any })
	lastDuoResult, lastDuoClock = data, os.clock()
	if gui.Enabled then
		showRank(data)
	end
end

return ResultsScreen
