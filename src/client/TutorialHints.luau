--!strict
-- Flight School (tutorial) en el cliente:
--   · offer(): la primera vez que entras, mientras buscas pareja: "¿practicar con el Coach?" (PRACTICE / NO
--     THANKS → "TutorialAnswer"). Con un compañero de verdad, Flight School empieza sola al despegar.
--   · update(glider): mientras vas en un ala de Flight School (atributo Tutorial), indicación grande (una o dos
--     palabras, atributo TutorialHint), "BONK!" al chocar (modo práctica: no quita corazones), "NICE!" al pasar al
--     tramo siguiente y botón SKIP (en dúo hace falta que lo pulsen los dos: atributo SkipVotes).

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

-- "BONK!" / "NICE!": reacción grande y corta en el centro.
local reaction = text(gui, Enum.Font.GothamBlack, 64)
reaction.AnchorPoint = Vector2.new(0.5, 0.5)
reaction.Position = UDim2.fromScale(0.5, 0.36)
reaction.Size = UDim2.fromOffset(500, 80)
local reactionStroke = Instance.new("UIStroke")
reactionStroke.Thickness = 4
reactionStroke.Transparency = 0.1
reactionStroke.Parent = reaction
local reactionScale = Instance.new("UIScale")
reactionScale.Parent = reaction
local BONKS = { "BONK!", "OOPS!", "OUCH!", "BONK!" }
local reactionToken = 0
local function react(word: string, color: Color3)
	reactionToken += 1
	local mine = reactionToken
	reaction.Text = word
	reaction.TextColor3 = color
	reactionScale.Scale = 1.6
	TweenService:Create(reactionScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.9, function()
		if reactionToken == mine then
			reaction.Text = ""
		end
	end)
end

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
local lastBonks = 0
local lastBonkClock = -math.huge

function TutorialHints.update(glider: Model?)
	local active = glider ~= nil and glider:GetAttribute("Tutorial") == true
	gui.Enabled = active
	if not (active and glider) then
		lastHint = ""
		lastBonks = 0
		return
	end
	local duo = glider:GetAttribute("TutorialDuo") == true
	caption.Text = if duo then "FLIGHT SCHOOL · learn it together" else "PRACTICE · your partner is the Coach"
	local votes = glider:GetAttribute("SkipVotes")
	skip.Text = if duo and type(votes) == "number" and votes > 0 then string.format("SKIP (%d/2)", votes) else "SKIP TUTORIAL"
	-- Golpes en modo práctica: no cuestan nada, solo se ríe uno.
	local bonks = glider:GetAttribute("Bonks")
	if type(bonks) == "number" and bonks > lastBonks then
		lastBonks = bonks
		lastBonkClock = os.clock()
		react(BONKS[bonks % #BONKS + 1], Color3.fromRGB(255, 120, 90))
	end
	local value = glider:GetAttribute("TutorialHint")
	local current = if type(value) == "string" then value else ""
	if current ~= lastHint then
		-- Paso al tramo siguiente sin chocar en el último momento: "NICE!".
		if lastHint ~= "" and #lastHint <= 14 and os.clock() - lastBonkClock > 1.5 then
			react("NICE!", Color3.fromRGB(80, 220, 110))
		end
		lastHint = current
		hint.Text = current
		hint.TextSize = if #current <= 14 then 56 else 30 -- una palabra, bien grande
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
	title.Text = "Waiting for a wingmate?"
	local body = text(panel, Enum.Font.GothamMedium, 19)
	body.Position = UDim2.fromOffset(30, 76)
	body.Size = UDim2.new(1, -60, 0, 80)
	body.TextColor3 = Color3.fromRGB(215, 222, 235)
	body.Text = "Practice in Flight School (40 s) with the Coach.\nWith a real partner, Flight School starts by itself."

	local play = button(panel, "PRACTICE", GREEN)
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
