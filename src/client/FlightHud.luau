--!strict
-- HUD de vuelo (solo mientras vas en el ala). Lee los atributos que publica el servidor en el ala:
--   · arriba izquierda: LEVEL NN / total, título, franja del color del bioma y barra de progreso del nivel
--                       (se encoge a una tira compacta unos segundos después de empezar cada nivel)
--   · centro, al empezar cada nivel: tarjeta "LEVEL NN · título" que aparece y se va
--   · arriba derecha:   cronómetro del recorrido (RunTime)
--   · arriba centro:    corazones del ala (Hearts / MaxHearts): parpadean al perder uno, y debajo la barra de
--                       energía de impulso (Energy) con "BOOST!" / "BOOST ×2!" cuando os balanceáis (Boost)
--   · abajo centro:     la barra del ala con tu marca y la de tu compañero (con flechas de hacia dónde se está
--                       moviendo cada uno: LeftAxis / RightAxis), zona central, indicadores CLIMB / DIVE / GLIDE
--                       (LiftInput) y de giro << >> (BalanceInput), y "IN SYNC!" cuando os movéis a la vez
--   · centro:           cuenta atrás grande "3 · 2 · 1 · GO!" y avisos de choque / meta
--   · depuración:       valores internos solo con Config.ShowDebug

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Glider.GliderConfig)
local UiScale = require(script.Parent:WaitForChild("UiScale"))
local FlightAudio = require(script.Parent:WaitForChild("FlightAudio"))

local FlightHud = {}

local PANEL = Color3.fromRGB(18, 22, 30)
local ME_COLOR = Color3.fromRGB(255, 205, 50)
local PARTNER_COLOR = Color3.fromRGB(235, 240, 255)
local CLIMB_COLOR, DIVE_COLOR = Color3.fromRGB(110, 230, 120), Color3.fromRGB(255, 150, 70)
local HEART_COLOR, HEART_EMPTY = Color3.fromRGB(255, 80, 95), Color3.fromRGB(70, 60, 70)
local DEFAULT_ACCENT = Color3.fromRGB(255, 110, 95)
local LIFT_BAND = 0.06 -- LiftInput a menos de esto del punto neutro = GLIDE
local TURN_BAND = 0.12 -- BalanceInput por debajo de esto = recto
local TIMER_EXTRAPOLATION = 0.15 -- s que el cronómetro avanza solo entre actualizaciones del servidor

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

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

local function stroke(parent: Instance, thickness: number, transparency: number)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Transparency = transparency
	s.Parent = parent
end

local function panel(parent: Instance, name: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0
	frame.Parent = parent
	corner(frame, UDim.new(0, 10))
	return frame
end

-- ── Construcción ──────────────────────────────────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name = "GliderHud"
gui.ResetOnSpawn = false
gui.Enabled = false
UiScale.attach(gui)

-- Tarjeta de nivel (arriba izquierda).
local card = panel(gui, "Level")
card.Position = UDim2.fromOffset(16, 12)
card.Size = UDim2.fromOffset(300, 74)
local accent = Instance.new("Frame")
accent.Size = UDim2.new(0, 6, 1, 0)
accent.BorderSizePixel = 0
accent.Parent = card
corner(accent, UDim.new(0, 3))
local levelText = text(card, Enum.Font.GothamBlack, 22)
levelText.Position = UDim2.fromOffset(18, 8)
levelText.Size = UDim2.new(1, -30, 0, 24)
levelText.TextXAlignment = Enum.TextXAlignment.Left
levelText.RichText = true
local titleText = text(card, Enum.Font.GothamMedium, 15, Color3.fromRGB(215, 222, 235))
titleText.Position = UDim2.fromOffset(18, 33)
titleText.Size = UDim2.new(1, -30, 0, 18)
titleText.TextXAlignment = Enum.TextXAlignment.Left
titleText.TextTruncate = Enum.TextTruncate.AtEnd
local featherText = text(card, Enum.Font.GothamBold, 15, Color3.fromRGB(255, 225, 90))
featherText.AnchorPoint = Vector2.new(1, 0)
featherText.Position = UDim2.new(1, -12, 0, 10)
featherText.Size = UDim2.fromOffset(70, 20)
featherText.TextXAlignment = Enum.TextXAlignment.Right
local track = Instance.new("Frame")
track.Position = UDim2.new(0, 18, 1, -14)
track.Size = UDim2.new(1, -32, 0, 6)
track.BackgroundColor3 = Color3.new(1, 1, 1)
track.BackgroundTransparency = 0.8
track.BorderSizePixel = 0
track.Parent = card
corner(track, UDim.new(1, 0))
local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0, 1)
fill.BorderSizePixel = 0
fill.Parent = track
corner(fill, UDim.new(1, 0))

-- Cronómetro compacto (arriba derecha).
local timerPanel = panel(gui, "Timer")
timerPanel.AnchorPoint = Vector2.new(1, 0)
timerPanel.Position = UDim2.new(1, -16, 0, 12)
timerPanel.Size = UDim2.fromOffset(136, 40)
local timerCaption = text(timerPanel, Enum.Font.GothamBold, 10, Color3.fromRGB(180, 190, 205))
timerCaption.Position = UDim2.fromOffset(10, 0)
timerCaption.Size = UDim2.fromOffset(30, 40)
timerCaption.TextXAlignment = Enum.TextXAlignment.Left
timerCaption.Text = "TIME"
local timerText = text(timerPanel, Enum.Font.RobotoMono, 22)
timerText.Position = UDim2.fromOffset(38, 0)
timerText.Size = UDim2.new(1, -44, 1, 0)
timerText.TextXAlignment = Enum.TextXAlignment.Right

-- Tarjeta de título al empezar cada nivel (centro, algo arriba).
local titleCard = Instance.new("CanvasGroup")
titleCard.AnchorPoint = Vector2.new(0.5, 0.5)
titleCard.Position = UDim2.fromScale(0.5, 0.26)
titleCard.Size = UDim2.fromOffset(560, 110)
titleCard.BackgroundTransparency = 1
titleCard.GroupTransparency = 1
titleCard.Parent = gui
local cardLevel = text(titleCard, Enum.Font.GothamBlack, 44)
cardLevel.Size = UDim2.new(1, 0, 0, 50)
stroke(cardLevel, 3, 0.2)
local cardTitle = text(titleCard, Enum.Font.GothamBold, 24, Color3.fromRGB(230, 236, 245))
cardTitle.Position = UDim2.fromOffset(0, 52)
cardTitle.Size = UDim2.new(1, 0, 0, 30)
stroke(cardTitle, 2, 0.35)
local cardLine = Instance.new("Frame")
cardLine.AnchorPoint = Vector2.new(0.5, 0)
cardLine.Position = UDim2.new(0.5, 0, 0, 90)
cardLine.Size = UDim2.fromOffset(180, 4)
cardLine.BorderSizePixel = 0
cardLine.Parent = titleCard
corner(cardLine, UDim.new(1, 0))

-- Corazones (arriba centro).
local heartsRow = Instance.new("Frame")
heartsRow.Name = "Hearts"
heartsRow.AnchorPoint = Vector2.new(0.5, 0)
heartsRow.Position = UDim2.new(0.5, 0, 0, 14)
heartsRow.Size = UDim2.fromOffset(150, 40)
heartsRow.BackgroundTransparency = 1
heartsRow.Parent = gui
local heartsLayout = Instance.new("UIListLayout")
heartsLayout.FillDirection = Enum.FillDirection.Horizontal
heartsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
heartsLayout.Padding = UDim.new(0, 6)
heartsLayout.Parent = heartsRow
local hearts: { TextLabel } = {}
local heartScales: { UIScale } = {}
for index = 1, Config.WingHearts do
	local heart = text(heartsRow, Enum.Font.GothamBlack, 34, HEART_COLOR)
	heart.Size = UDim2.fromOffset(40, 40)
	heart.Text = "♥"
	heart.LayoutOrder = index
	stroke(heart, 2, 0.3)
	local scale = Instance.new("UIScale")
	scale.Parent = heart
	hearts[index] = heart
	heartScales[index] = scale
end

-- Energía de impulso (bajo los corazones).
local energyTrack = Instance.new("Frame")
energyTrack.AnchorPoint = Vector2.new(0.5, 0)
energyTrack.Position = UDim2.new(0.5, 0, 0, 58)
energyTrack.Size = UDim2.fromOffset(170, 10)
energyTrack.BackgroundColor3 = Color3.fromRGB(40, 46, 60)
energyTrack.BorderSizePixel = 0
energyTrack.Parent = gui
corner(energyTrack, UDim.new(1, 0))
stroke(energyTrack, 1.5, 0.4)
local energyFill = Instance.new("Frame")
energyFill.Size = UDim2.fromScale(1, 1)
energyFill.BackgroundColor3 = Color3.fromRGB(90, 210, 255)
energyFill.BorderSizePixel = 0
energyFill.Parent = energyTrack
corner(energyFill, UDim.new(1, 0))
local boostText = text(gui, Enum.Font.GothamBlack, 22, Color3.fromRGB(90, 210, 255))
boostText.AnchorPoint = Vector2.new(0.5, 0)
boostText.Position = UDim2.new(0.5, 0, 0, 72)
boostText.Size = UDim2.fromOffset(220, 26)
stroke(boostText, 2, 0.2)
local boostScale = Instance.new("UIScale")
boostScale.Parent = boostText
local energyHint = text(energyTrack, Enum.Font.GothamBold, 11, Color3.fromRGB(200, 210, 225))
energyHint.AnchorPoint = Vector2.new(1, 0.5)
energyHint.Position = UDim2.new(0, -8, 0.5, 0)
energyHint.Size = UDim2.fromOffset(90, 12)
energyHint.TextXAlignment = Enum.TextXAlignment.Right
energyHint.Text = if UserInputService.KeyboardEnabled then "SPACE: PUMP" elseif UserInputService.GamepadEnabled then "A: PUMP" else "⇑ PUMP"

-- Barra del ala (abajo centro).
local barPanel = panel(gui, "Bar")
barPanel.AnchorPoint = Vector2.new(0.5, 1)
barPanel.Position = UDim2.new(0.5, 0, 1, -18)
barPanel.Size = UDim2.fromOffset(460, 108)
local turnLeft = text(barPanel, Enum.Font.GothamBlack, 22)
turnLeft.Position = UDim2.fromOffset(14, 6)
turnLeft.Size = UDim2.fromOffset(60, 26)
turnLeft.Text = "<<"
local turnRight = text(barPanel, Enum.Font.GothamBlack, 22)
turnRight.AnchorPoint = Vector2.new(1, 0)
turnRight.Position = UDim2.new(1, -14, 0, 6)
turnRight.Size = UDim2.fromOffset(60, 26)
turnRight.Text = ">>"
local liftText = text(barPanel, Enum.Font.GothamBlack, 20)
liftText.AnchorPoint = Vector2.new(0.5, 0)
liftText.Position = UDim2.new(0.5, 0, 0, 7)
liftText.Size = UDim2.fromOffset(160, 24)
local bar = Instance.new("Frame")
bar.AnchorPoint = Vector2.new(0.5, 0)
bar.Position = UDim2.new(0.5, 0, 0, 52)
bar.Size = UDim2.new(1, -48, 0, 12)
bar.BackgroundColor3 = Color3.fromRGB(70, 78, 95)
bar.BorderSizePixel = 0
bar.Parent = barPanel
corner(bar, UDim.new(1, 0))
local innerFraction = Config.BarInnerOffset / Config.BarOuterOffset
local centerZone = Instance.new("Frame")
centerZone.AnchorPoint = Vector2.new(0.5, 0.5)
centerZone.Position = UDim2.fromScale(0.5, 0.5)
centerZone.Size = UDim2.new(innerFraction, 0, 1, 6)
centerZone.BackgroundColor3 = Color3.fromRGB(150, 160, 180)
centerZone.BackgroundTransparency = 0.4
centerZone.BorderSizePixel = 0
centerZone.Parent = bar
corner(centerZone, UDim.new(0, 4))

local function marker(color: Color3, caption: string): (Frame, TextLabel)
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(26, 26)
	dot.BackgroundColor3 = color
	dot.BorderSizePixel = 0
	dot.ZIndex = 3
	dot.Parent = bar
	corner(dot, UDim.new(1, 0))
	stroke(dot, 2, 0.2)
	local label = text(dot, Enum.Font.GothamBold, 12, color)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 1, 6)
	label.Size = UDim2.fromOffset(80, 14)
	label.Text = caption
	return dot, label
end
local meDot = marker(ME_COLOR, "YOU")
local partnerDot = marker(PARTNER_COLOR, "PARTNER")
meDot.ZIndex = 4

-- Flecha de intención encima de cada marca: hacia dónde se está deslizando ahora mismo.
local function intentArrow(dot: Frame, color: Color3): TextLabel
	local arrow = text(dot, Enum.Font.GothamBlack, 18, color)
	arrow.AnchorPoint = Vector2.new(0.5, 1)
	arrow.Position = UDim2.new(0.5, 0, 0, -4)
	arrow.Size = UDim2.fromOffset(40, 20)
	stroke(arrow, 1.5, 0.3)
	return arrow
end
local meArrow = intentArrow(meDot, ME_COLOR)
local partnerArrow = intentArrow(partnerDot, PARTNER_COLOR)

-- "IN SYNC!": los dos se mueven a la vez (mismo lado = giro juntos; lados opuestos = abrir/cerrar juntos).
local syncChip = text(barPanel, Enum.Font.GothamBlack, 16, CLIMB_COLOR)
syncChip.AnchorPoint = Vector2.new(0.5, 1)
syncChip.Position = UDim2.new(0.5, 0, 0, -4)
syncChip.Size = UDim2.fromOffset(160, 22)
syncChip.Text = "IN SYNC!"
syncChip.Visible = false
stroke(syncChip, 2, 0.2)
local syncScale = Instance.new("UIScale")
syncScale.Parent = syncChip

-- Cuenta atrás y avisos (centro).
local countdown = text(gui, Enum.Font.GothamBlack, 100) -- 100 = TextSize máximo de Roblox
countdown.AnchorPoint = Vector2.new(0.5, 0.5)
countdown.Position = UDim2.fromScale(0.5, 0.42)
countdown.Size = UDim2.fromOffset(400, 140)
stroke(countdown, 5, 0.2)
local countdownScale = Instance.new("UIScale")
countdownScale.Parent = countdown
local toast = text(gui, Enum.Font.GothamBold, 26)
toast.AnchorPoint = Vector2.new(0.5, 0.5)
toast.Position = UDim2.fromScale(0.5, 0.56)
toast.Size = UDim2.fromOffset(700, 34)
stroke(toast, 3, 0.3)

-- Depuración (solo con Config.ShowDebug).
local debugText = text(gui, Enum.Font.GothamMedium, 14)
debugText.AnchorPoint = Vector2.new(0.5, 0)
debugText.Position = UDim2.new(0.5, 0, 0, 96)
debugText.Size = UDim2.new(0.9, 0, 0, 20)
stroke(debugText, 1.5, 0.4)

gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

-- ── Actualización ─────────────────────────────────────────────────────

local function number(glider: Model, name: string): number
	local value = glider:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function formatTime(seconds: number): string
	return string.format("%02d:%04.1f", math.floor(seconds / 60), seconds % 60)
end

local lastState: string? = nil
local lastCountdown = -1
local shownHearts = Config.WingHearts
local blinkClock = 0
local CARD_TIME = 5 -- s que la tarjeta de nivel se ve entera antes de encogerse
local lastLevel = -1
local cardExpanded = true
local cardExpandUntil = 0
local titleToken = 0

local function setCardExpanded(expanded: boolean)
	if expanded == cardExpanded then
		return
	end
	cardExpanded = expanded
	TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Size = UDim2.fromOffset(if expanded then 300 else 220, if expanded then 74 else 44) }):Play()
	titleText.Visible = expanded
	levelText.TextSize = if expanded then 22 else 18
end

-- "LEVEL NN · título": aparece, se queda un momento y se va.
local function showTitleCard(level: number, title: string, color: Color3)
	titleToken += 1
	local mine = titleToken
	cardLevel.Text = string.format("LEVEL %02d", level)
	cardTitle.Text = title
	cardLine.BackgroundColor3 = color
	titleCard.GroupTransparency = 1
	titleCard.Position = UDim2.fromScale(0.5, 0.28)
	TweenService:Create(titleCard, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.26) }):Play()
	task.delay(2.2, function()
		if titleToken == mine then
			TweenService:Create(titleCard, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { GroupTransparency = 1 }):Play()
		end
	end)
end
local syncTime, syncShownUntil, syncCooldownUntil = 0, 0, 0
local SYNC_HOLD = 0.35 -- s moviéndose a la vez para que cuente
local SYNC_SHOW, SYNC_COOLDOWN = 1.2, 5
local lastBoostLevel = 0

local function arrowFor(axis: number): string
	return if axis < 0 then "◀" elseif axis > 0 then "▶" else ""
end
local shownProgress = 0
local lastRunTime, runTimeClock = -1, 0

local function pop(label: TextLabel, value: string, color: Color3?)
	label.Text = value
	label.TextColor3 = color or Color3.new(1, 1, 1)
	countdownScale.Scale = 1.6
	TweenService:Create(countdownScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function FlightHud.update(glider: Model?, side: number, dt: number)
	gui.Enabled = glider ~= nil and side ~= 0
	if not glider or side == 0 then
		lastState, lastCountdown = nil, -1
		lastLevel = -1
		return
	end

	-- Nivel y progreso.
	local level, total = number(glider, "Level"), number(glider, "LevelCount")
	local color = glider:GetAttribute("LevelColor")
	local accentColor = if typeof(color) == "Color3" then color else DEFAULT_ACCENT
	accent.BackgroundColor3 = accentColor
	fill.BackgroundColor3 = accentColor
	levelText.Text = string.format('LEVEL %02d <font size="15" color="#b4bece">/ %02d</font>', level, total)
	local title = glider:GetAttribute("LevelTitle")
	titleText.Text = if type(title) == "string" then title else ""
	-- Nivel nuevo: tarjeta grande en el centro y la de arriba se ve entera unos segundos.
	if level ~= lastLevel and level > 0 then
		lastLevel = level
		cardExpandUntil = os.clock() + CARD_TIME
		setCardExpanded(true)
		if glider:GetAttribute("Completed") ~= true then
			showTitleCard(level, titleText.Text, accentColor)
		end
	end
	setCardExpanded(os.clock() < cardExpandUntil)
	local featherTotal = number(glider, "LevelFeatherTotal")
	featherText.Text = if featherTotal > 0 then string.format("✦ %d/%d", number(glider, "LevelFeathers"), featherTotal) else ""
	shownProgress += (number(glider, "LevelProgress") - shownProgress) * math.min(1, dt * 8)
	fill.Size = UDim2.fromScale(math.clamp(shownProgress, 0, 1), 1)

	-- Cronómetro: el valor del servidor, avanzando un poco solo entre actualizaciones.
	local runTime = number(glider, "RunTime")
	if runTime ~= lastRunTime then
		lastRunTime, runTimeClock = runTime, os.clock()
	end
	local state = glider:GetAttribute("State")
	local running = runTime > 0 and not glider:GetAttribute("Completed")
	timerText.Text = formatTime(runTime + (if running then math.min(os.clock() - runTimeClock, TIMER_EXTRAPOLATION) else 0))

	-- Corazones: el que se pierde salta y se apaga; invulnerable = parpadeo.
	local maxHearts = math.max(number(glider, "MaxHearts"), 1)
	local heartCount = if glider:GetAttribute("Hearts") == nil then maxHearts else number(glider, "Hearts")
	if heartCount < shownHearts then
		for index = heartCount + 1, math.min(shownHearts, #hearts) do
			heartScales[index].Scale = 1.8
			TweenService:Create(heartScales[index], TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
	shownHearts = heartCount
	blinkClock += dt
	local blinking = glider:GetAttribute("Invulnerable") == true and (blinkClock * 8) % 2 < 1
	for index, heart in hearts do
		heart.Visible = index <= maxHearts
		heart.TextColor3 = if index <= heartCount then HEART_COLOR else HEART_EMPTY
		heart.TextTransparency = if blinking and index <= heartCount then 0.6 else 0
	end
	heartsRow.Visible = state ~= "Landed"

	-- Energía e impulso.
	local energy = if glider:GetAttribute("Energy") == nil then 1 else number(glider, "Energy")
	energyFill.Size = UDim2.fromScale(math.clamp(energy, 0, 1), 1)
	energyFill.BackgroundColor3 = if energy < 0.2 then Color3.fromRGB(255, 120, 90) else Color3.fromRGB(90, 210, 255)
	energyTrack.Visible = state ~= "Landed"
	local boost = number(glider, "Boost")
	local boostLevel = if boost >= Config.PumpBoostBoth - 0.01 then 2 elseif boost > 0.01 then 1 else 0
	if boostLevel ~= lastBoostLevel then
		boostText.Text = if boostLevel == 2 then "BOOST ×2!" elseif boostLevel == 1 then "BOOST!" else ""
		if boostLevel > lastBoostLevel then
			boostScale.Scale = 1.5
			TweenService:Create(boostScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			FlightAudio.play("Boost", if boostLevel == 2 then 1.25 else 1)
		end
		lastBoostLevel = boostLevel
	end

	-- Barra: yo y mi compañero (si hay).
	local mine = number(glider, if side < 0 then "LeftPosition" else "RightPosition")
	local theirs = number(glider, if side < 0 then "RightPosition" else "LeftPosition")
	local partnerId = glider:GetAttribute(if side < 0 then "RightUserId" else "LeftUserId")
	meDot.Position = UDim2.fromScale(0.5 + math.clamp(mine, -1, 1) * 0.5, 0.5)
	local hasPartner = type(partnerId) == "number" and partnerId ~= 0
	partnerDot.Visible = hasPartner
	partnerDot.Position = UDim2.fromScale(0.5 + math.clamp(theirs, -1, 1) * 0.5, 0.5)
	local myAxis = number(glider, if side < 0 then "LeftAxis" else "RightAxis")
	local theirAxis = number(glider, if side < 0 then "RightAxis" else "LeftAxis")
	local myPump = glider:GetAttribute(if side < 0 then "LeftPump" else "RightPump") == true
	local theirPump = glider:GetAttribute(if side < 0 then "RightPump" else "LeftPump") == true
	meArrow.Text = if myPump then "⇑" .. arrowFor(myAxis) else arrowFor(myAxis)
	partnerArrow.Text = if theirPump then "⇑" .. arrowFor(theirAxis) else arrowFor(theirAxis)

	-- IN SYNC!
	local now = os.clock()
	if hasPartner and state == "Flying" and myAxis ~= 0 and theirAxis ~= 0 then
		syncTime += dt
		if syncTime >= SYNC_HOLD and now >= syncCooldownUntil then
			syncShownUntil, syncCooldownUntil = now + SYNC_SHOW, now + SYNC_COOLDOWN
			FlightAudio.play("InSync")
			syncScale.Scale = 1.5
			TweenService:Create(syncScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	else
		syncTime = 0
	end
	syncChip.Visible = now < syncShownUntil

	local lift = number(glider, "LiftInput") - Config.NeutralLiftPoint
	if lift > LIFT_BAND then
		liftText.Text, liftText.TextColor3 = "CLIMB", CLIMB_COLOR
	elseif lift < -LIFT_BAND then
		liftText.Text, liftText.TextColor3 = "DIVE", DIVE_COLOR
	else
		liftText.Text, liftText.TextColor3 = "GLIDE", Color3.new(1, 1, 1)
	end
	local balance = number(glider, "BalanceInput") -- > 0: el peso está a la izquierda → gira a la izquierda
	turnLeft.TextTransparency = if balance > TURN_BAND then 0 else 0.8
	turnRight.TextTransparency = if balance < -TURN_BAND then 0 else 0.8
	turnLeft.TextColor3 = if balance > TURN_BAND then ME_COLOR else Color3.new(1, 1, 1)
	turnRight.TextColor3 = if balance < -TURN_BAND then ME_COLOR else Color3.new(1, 1, 1)

	-- Cuenta atrás, GO! y avisos.
	if state == "Countdown" then
		local seconds = math.ceil(number(glider, "Countdown"))
		if seconds ~= lastCountdown and seconds > 0 then
			pop(countdown, tostring(seconds))
		end
		lastCountdown = seconds
		local checkpoint = number(glider, "Checkpoint")
		if number(glider, "Respawns") > 0 then
			toast.Text = if glider:GetAttribute("WindAssist") then "Tailwind on: the wind will help you this time" else "Back in the air!"
		else
			toast.Text = if checkpoint > 0 then string.format("Starting from checkpoint %d", checkpoint) else "Get ready!"
		end
		toast.TextColor3 = Color3.new(1, 1, 1)
	elseif state == "Flying" then
		if lastState == "Countdown" then
			pop(countdown, "GO!", CLIMB_COLOR)
			task.delay(0.7, function()
				if countdown.Text == "GO!" then
					countdown.Text = ""
				end
			end)
		end
		lastCountdown = -1
		if glider:GetAttribute("Completed") and not glider:GetAttribute("Tutorial") then
			toast.Text, toast.TextColor3 = "FINISH! Glide down and land on the island", CLIMB_COLOR
		else
			toast.Text = ""
		end
	elseif state == "Ended" then
		countdown.Text = ""
		if glider:GetAttribute("Completed") then
			toast.Text, toast.TextColor3 = "FINISH! Back to the lobby…", CLIMB_COLOR
		else
			toast.Text, toast.TextColor3 = "WING LOST! Back to the last safe point", DIVE_COLOR
		end
	elseif state == "Landed" then
		countdown.Text = ""
		toast.Text, toast.TextColor3 = "Nice landing!", CLIMB_COLOR
	end
	lastState = if type(state) == "string" then state else nil

	debugText.Visible = Config.ShowDebug
	if Config.ShowDebug then
		debugText.Text = string.format(
			"P1 %+.2f  P2 %+.2f  |  Lift %.2f  Balance %+.2f  |  Vy %+.1f  Roll %+.0f°  Turn %+.0f°/s  |  Alt %.0f",
			number(glider, "LeftPosition"),
			number(glider, "RightPosition"),
			number(glider, "LiftInput"),
			number(glider, "BalanceInput"),
			number(glider, "VerticalSpeed"),
			number(glider, "Roll"),
			number(glider, "TurnRate"),
			number(glider, "Altitude")
		)
	end
end

return FlightHud
