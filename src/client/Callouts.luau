--!strict
-- Avisos rápidos al compañero mientras se vuela ("Climb!", "Dive!", "Left!", "Right!", "Nice!"):
--   · teclado 1-5 · mando A (Climb) B (Dive) L1 (Left) R1 (Right) · táctil: botón 💬 y la lista que abre
--   · el servidor los reenvía a los dos del ala ("Callout"); el del compañero sale grande sobre la barra y en
--     un bocadillo encima de su cabeza, el propio sale pequeño como confirmación.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Glider.GliderConfig)
local remote = ReplicatedStorage:WaitForChild("Glider"):WaitForChild("GliderRemote") :: RemoteEvent
local UiScale = require(script.Parent:WaitForChild("UiScale"))

local Callouts = {}

local PANEL = Color3.fromRGB(18, 22, 30)
local ME_COLOR = Color3.fromRGB(255, 205, 50)
local PARTNER_COLOR = Color3.fromRGB(235, 240, 255)
local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }
local PAD = { [Enum.KeyCode.ButtonA] = 1, [Enum.KeyCode.ButtonB] = 2, [Enum.KeyCode.ButtonL1] = 3, [Enum.KeyCode.ButtonR1] = 4 }

local player = Players.LocalPlayer :: Player

local gui = Instance.new("ScreenGui")
gui.Name = "GliderCallouts"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 5
UiScale.attach(gui)

-- Bocadillo sobre la barra (el HUD de la barra está abajo al centro).
local bubble = Instance.new("TextLabel")
bubble.AnchorPoint = Vector2.new(0.5, 1)
bubble.Position = UDim2.new(0.5, 0, 1, -150)
bubble.Size = UDim2.fromOffset(320, 46)
bubble.BackgroundColor3 = PANEL
bubble.BackgroundTransparency = 0.15
bubble.Font = Enum.Font.GothamBlack
bubble.TextSize = 26
bubble.TextColor3 = PARTNER_COLOR
bubble.Visible = false
bubble.Parent = gui
local bubbleCorner = Instance.new("UICorner")
bubbleCorner.CornerRadius = UDim.new(0, 12)
bubbleCorner.Parent = bubble
local bubbleScale = Instance.new("UIScale")
bubbleScale.Parent = bubble

-- Botón táctil y su lista.
local toggle = Instance.new("TextButton")
toggle.AnchorPoint = Vector2.new(1, 0.5)
toggle.Position = UDim2.new(1, -20, 0.5, -70)
toggle.Size = UDim2.fromOffset(52, 52)
toggle.BackgroundColor3 = PANEL
toggle.BackgroundTransparency = 0.25
toggle.Font = Enum.Font.GothamBold
toggle.TextSize = 26
toggle.Text = "💬"
toggle.TextColor3 = Color3.new(1, 1, 1)
toggle.Visible = false
toggle.Parent = gui
local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0.5, 0)
toggleCorner.Parent = toggle

local list = Instance.new("Frame")
list.AnchorPoint = Vector2.new(1, 1)
list.Position = UDim2.new(1, -80, 0.5, -44)
list.Size = UDim2.fromOffset(130, 5 * 42)
list.BackgroundTransparency = 1
list.Visible = false
list.Parent = gui
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.Parent = list

local function send(id: number)
	remote:FireServer("Callout", id)
	list.Visible = false
end

for id, caption in Config.Callouts do
	local option = Instance.new("TextButton")
	option.Size = UDim2.new(1, 0, 0, 38)
	option.BackgroundColor3 = PANEL
	option.BackgroundTransparency = 0.2
	option.Font = Enum.Font.GothamBold
	option.TextSize = 18
	option.TextColor3 = Color3.new(1, 1, 1)
	option.Text = caption
	option.LayoutOrder = id
	option.Parent = list
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = option
	option.Activated:Connect(function()
		send(id)
	end)
end
toggle.Activated:Connect(function()
	list.Visible = not list.Visible
end)

gui.Parent = player:WaitForChild("PlayerGui")

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not gui.Enabled then
		return
	end
	local id = table.find(KEYS, input.KeyCode) or PAD[input.KeyCode]
	if id and Config.Callouts[id] then
		send(id)
	end
end)

-- Bocadillo 3D encima de la cabeza de quien lo dice (solo lo ve este cliente).
local function headBubble(character: Model?, caption: string)
	local head = character and character:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(160, 40)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = PANEL
	label.BackgroundTransparency = 0.2
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = PARTNER_COLOR
	label.Text = caption
	label.Parent = billboard
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = label
	billboard.Parent = gui
	task.delay(2.2, function()
		billboard:Destroy()
	end)
end

local shownToken = 0

-- El servidor reenvía un aviso: { side, id, userId }.
function Callouts.show(data: { [string]: any }, mySide: number)
	local caption = Config.Callouts[data.id]
	if type(caption) ~= "string" then
		return
	end
	local mine = data.side == mySide
	bubble.Text = if mine then "You: " .. caption else caption
	bubble.TextColor3 = if mine then ME_COLOR else PARTNER_COLOR
	bubble.TextSize = if mine then 18 else 28
	bubble.Visible = true
	bubbleScale.Scale = 1.4
	TweenService:Create(bubbleScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	shownToken += 1
	local token = shownToken
	task.delay(if mine then 1.2 else 2.2, function()
		if token == shownToken then
			bubble.Visible = false
		end
	end)
	if not mine and type(data.userId) == "number" then
		local speaker = Players:GetPlayerByUserId(data.userId)
		headBubble(speaker and speaker.Character, caption)
	end
end

function Callouts.setVisible(visible: boolean)
	gui.Enabled = visible
	toggle.Visible = visible and UserInputService.TouchEnabled
	list.Visible = false
	bubble.Visible = false
end

return Callouts
