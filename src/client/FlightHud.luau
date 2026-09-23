--!strict
-- HUD de vuelo (solo mientras vas en el ala). Lee los atributos que publica el servidor en el ala:
--   · arriba izquierda: LEVEL NN / total, título, franja del color del bioma y barra de progreso del nivel
--   · arriba derecha:   cronómetro del recorrido (RunTime)
--   · abajo centro:     la barra del ala con tu marca y la de tu compañero, zona central, e indicadores
--                       CLIMB / DIVE / GLIDE (sale de LiftInput) y de giro << >> (sale de BalanceInput)
--   · centro:           cuenta atrás grande "3 · 2 · 1 · GO!" y avisos de choque / meta
--   · depuración:       valores internos solo con Config.ShowDebug

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Glider.GliderConfig)
local UiScale = require(script.Parent:WaitForChild("UiScale"))

local FlightHud = {}

local PANEL = Color3.fromRGB(18, 22, 30)
local ME_COLOR = Color3.fromRGB(255, 205, 50)
local PARTNER_COLOR = Color3.fromRGB(235, 240, 255)
local CLIMB_COLOR, DIVE_COLOR = Color3.fromRGB(110, 230, 120), Color3.fromRGB(255, 150, 70)
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

-- Cronómetro (arriba derecha).
local timerPanel = panel(gui, "Timer")
timerPanel.AnchorPoint = Vector2.new(1, 0)
timerPanel.Position = UDim2.new(1, -16, 0, 12)
timerPanel.Size = UDim2.fromOffset(170, 50)
local timerCaption = text(timerPanel, Enum.Font.GothamBold, 11, Color3.fromRGB(180, 190, 205))
timerCaption.Position = UDim2.fromOffset(0, 5)
timerCaption.Size = UDim2.new(1, 0, 0, 12)
timerCaption.Text = "TIME"
local timerText = text(timerPanel, Enum.Font.RobotoMono, 26)
timerText.Position = UDim2.fromOffset(0, 17)
timerText.Size = UDim2.new(1, 0, 0, 28)

-- Barra del ala (abajo centro).
local barPanel = panel(gui, "Bar")
barPanel.AnchorPoint = Vector2.new(0.5, 1)
barPanel.Position = UDim2.new(0.5, 0, 1, -18)
barPanel.Size = UDim2.fromOffset(380, 92)
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
bar.Position = UDim2.new(0.5, 0, 0, 44)
bar.Size = UDim2.new(1, -40, 0, 10)
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
	dot.Size = UDim2.fromOffset(22, 22)
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

	-- Barra: yo y mi compañero (si hay).
	local mine = number(glider, if side < 0 then "LeftPosition" else "RightPosition")
	local theirs = number(glider, if side < 0 then "RightPosition" else "LeftPosition")
	local partnerId = glider:GetAttribute(if side < 0 then "RightUserId" else "LeftUserId")
	meDot.Position = UDim2.fromScale(0.5 + math.clamp(mine, -1, 1) * 0.5, 0.5)
	partnerDot.Visible = type(partnerId) == "number" and partnerId ~= 0
	partnerDot.Position = UDim2.fromScale(0.5 + math.clamp(theirs, -1, 1) * 0.5, 0.5)

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
		toast.Text = if checkpoint > 0 then string.format("Starting from checkpoint %d", checkpoint) else "Get ready!"
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
		toast.Text = ""
	elseif state == "Ended" then
		countdown.Text = ""
		if glider:GetAttribute("Completed") then
			toast.Text, toast.TextColor3 = "FINISH! Back to the lobby…", CLIMB_COLOR
		else
			local checkpoint = number(glider, "Checkpoint")
			toast.Text = if checkpoint > 0 then string.format("CRASH! Back to checkpoint %d", checkpoint) else "CRASH! Back to the start"
			toast.TextColor3 = DIVE_COLOR
		end
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
