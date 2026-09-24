--!strict
-- Tutorial en el cliente:
--   · offer(): ventana "¿Quieres jugar el tutorial?" (solo la primera vez que entras; el servidor decide cuándo).
--     PLAY / NO THANKS → "TutorialAnswer" al servidor. Acepte o rechace, no vuelve a salir.
--   · update(glider): mientras vas en un ala de tutorial (atributo Tutorial), indicación grande arriba al centro
--     (atributo TutorialHint, lo pone TutorialBot en el servidor) y botón SKIP TUTORIAL.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local remote = ReplicatedStorage:WaitForChild("Glider"):WaitForChild("GliderRemote") :: RemoteEvent
local UiScale = require(script.Parent:WaitForChild("UiScale"))

local TutorialHints = {}

local PANEL = Color3.fromRGB(18, 22, 30)
local GREEN = Color3.fromRGB(80, 200, 110)
local GREY = Color3.fromRGB(90, 98, 115)

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function text(parent: Instance, font: Enum.Font, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = size
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextWrapped = true
	label.Text = ""
	label.Parent = parent
	return label
end

local function button(parent: Instance, caption: string, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 22
	b.Text = caption
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 10)
	return b
end

local playerGui = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

-- ── Indicación y botón SKIP (en vuelo) ────────────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name = "GliderTutorial"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 15
UiScale.attach(gui)

local hint = text(gui, Enum.Font.GothamBlack, 34)
hint.AnchorPoint = Vector2.new(0.5, 0)
hint.Position = UDim2.new(0.5, 0, 0, 110)
hint.Size = UDim2.fromOffset(760, 90)
local hintStroke = Instance.new("UIStroke")
hintStroke.Thickness = 3
hintStroke.Transparency = 0.2
hintStroke.Parent = hint
local hintScale = Instance.new("UIScale")
hintScale.Parent = hint

local caption = text(gui, Enum.Font.GothamBold, 16)
caption.AnchorPoint = Vector2.new(0.5, 0)
caption.Position = UDim2.new(0.5, 0, 0, 86)
caption.Size = UDim2.fromOffset(400, 20)
caption.TextColor3 = Color3.fromRGB(255, 205, 50)
caption.Text = "TUTORIAL · your partner is a bot"

local skip = button(gui, "SKIP TUTORIAL", GREY)
skip.AnchorPoint = Vector2.new(0.5, 0)
skip.Position = UDim2.new(0.5, 0, 0, 16)
skip.Size = UDim2.fromOffset(190, 44)
skip.TextSize = 18
skip.Activated:Connect(function()
	remote:FireServer("SkipTutorial")
end)

gui.Parent = playerGui

local lastHint = ""

function TutorialHints.update(glider: Model?)
	local active = glider ~= nil and glider:GetAttribute("Tutorial") == true
	gui.Enabled = active
	if not (active and glider) then
		lastHint = ""
		return
	end
	local value = glider:GetAttribute("TutorialHint")
	local current = if type(value) == "string" then value else ""
	if current ~= lastHint then
		lastHint = current
		hint.Text = current
		hintScale.Scale = 1.25
		TweenService:Create(hintScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

-- ── Oferta (solo la primera vez) ──────────────────────────────────────

function TutorialHints.offer()
	local offer = Instance.new("ScreenGui")
	offer.Name = "GliderTutorialOffer"
	offer.ResetOnSpawn = false
	offer.IgnoreGuiInset = true
	offer.DisplayOrder = 100
	UiScale.attach(offer)

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.Active = true
	backdrop.Parent = offer

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(520, 270)
	panel.BackgroundColor3 = PANEL
	panel.Parent = backdrop
	corner(panel, 14)

	local title = text(panel, Enum.Font.GothamBlack, 34)
	title.Position = UDim2.fromOffset(20, 22)
	title.Size = UDim2.new(1, -40, 0, 44)
	title.Text = "First time flying?"
	local body = text(panel, Enum.Font.GothamMedium, 19)
	body.Position = UDim2.fromOffset(30, 76)
	body.Size = UDim2.new(1, -60, 0, 80)
	body.TextColor3 = Color3.fromRGB(215, 222, 235)
	body.Text = "Learn to climb, dive and turn in a short tutorial.\nA bot will fly with you as your partner."

	local play = button(panel, "PLAY TUTORIAL", GREEN)
	play.AnchorPoint = Vector2.new(1, 1)
	play.Position = UDim2.new(0.5, -8, 1, -24)
	play.Size = UDim2.fromOffset(210, 54)
	local decline = button(panel, "NO THANKS", GREY)
	decline.AnchorPoint = Vector2.new(0, 1)
	decline.Position = UDim2.new(0.5, 8, 1, -24)
	decline.Size = UDim2.fromOffset(210, 54)

	local answered = false
	local function answer(accept: boolean)
		if answered then
			return
		end
		answered = true
		remote:FireServer("TutorialAnswer", accept)
		offer:Destroy()
	end
	play.Activated:Connect(function()
		answer(true)
	end)
	decline.Activated:Connect(function()
		answer(false)
	end)
	offer.Parent = playerGui
end

return TutorialHints
