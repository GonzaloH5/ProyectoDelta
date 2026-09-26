--!strict
-- Flight School (el principio del recorrido para los dúos con alguien nuevo) en el cliente:
--   · update(glider): mientras vas en un ala de Flight School (atributo Tutorial), indicación grande (una o dos
--     palabras, atributo TutorialHint), "BONK!" al chocar (modo práctica: no quita corazones), "NICE!" al pasar al
--     tramo siguiente y botón SKIP (en dúo hace falta que lo pulsen los dos: atributo SkipVotes).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local remote = ReplicatedStorage:WaitForChild("Glider"):WaitForChild("GliderRemote") :: RemoteEvent
local UiScale = require(script.Parent:WaitForChild("UiScale"))

local TutorialHints = {}

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
	caption.Text = "FLIGHT SCHOOL · learn it together"
	local votes = glider:GetAttribute("SkipVotes")
	skip.Text = if type(votes) == "number" and votes > 0 then string.format("SKIP (%d/2)", votes) else "SKIP TUTORIAL"
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

return TutorialHints
