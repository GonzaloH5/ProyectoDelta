--!strict
-- Pantalla de CHECKPOINT: aparece rápido (~2 s) cuando el dúo cruza una isla de descanso o la meta.
--   · banda inclinada del color del bioma que entra deslizando desde la izquierda
--   · "CHECKPOINT" con golpe de escala · nivel superado y el siguiente
--   · fila de rombos de progreso (el recién superado "salta") · aviso de bioma nuevo
--   · medalla del nivel (oro = sin golpes, plata = sin perder el ala, bronce = superado)
--   · último nivel de un capítulo: "CHAPTER N CLEAR!" con el nombre del bioma
--   · en la meta: tiempo del recorrido y, poco después (showResult), récord del dúo / puesto / récord personal
-- El servidor manda los datos (Checkpoints.info); aquí solo se dibuja.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UiScale = require(script.Parent:WaitForChild("UiScale"))

local CheckpointBanner = {}

local HOLD_TIME, FINAL_HOLD_TIME = 1.7, 4.5
local MAX_DIAMONDS = 20 -- con más niveles, el progreso se muestra como texto
local DEFAULT_COLOR = Color3.fromRGB(255, 110, 95)
local RECORD_COLOR = Color3.fromRGB(255, 205, 50)
-- Medallas: nombre, color y lema (índice = 1 bronce, 2 plata, 3 oro).
local MEDALS = {
	{ name = "BRONZE", color = Color3.fromRGB(215, 140, 80), note = "Level cleared" },
	{ name = "SILVER", color = Color3.fromRGB(215, 225, 240), note = "No wing lost" },
	{ name = "GOLD", color = Color3.fromRGB(255, 205, 50), note = "Flawless!" },
}
local BAND_Y = UDim.new(0.5, -12)

local function tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out)
	TweenService:Create(instance, info, goal):Play()
end

local function label(parent: Instance, font: Enum.Font, size: number, y: number): TextLabel
	local text = Instance.new("TextLabel")
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.new(0.5, 0, 0.5, y)
	text.Size = UDim2.new(1, 0, 0, size + 8)
	text.BackgroundTransparency = 1
	text.Font = font
	text.TextSize = size
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Text = ""
	text.Parent = parent
	return text
end

-- string.upper no convierte letras acentuadas (UTF-8): "Cañón" → "CAñóN". Esta sí.
local ACCENTS = { ["á"] = "Á", ["é"] = "É", ["í"] = "Í", ["ó"] = "Ó", ["ú"] = "Ú", ["ü"] = "Ü", ["ñ"] = "Ñ" }
local function upper(text: string): string
	return (string.upper(text):gsub("[\195][\128-\191]", ACCENTS))
end

local function stroke(parent: Instance, thickness: number, transparency: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Transparency = transparency
	s.Color = Color3.new(0, 0, 0)
	s.Parent = parent
	return s
end

-- ── Construcción (una vez) ────────────────────────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name = "GliderCheckpoint"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 20
gui.Enabled = false
UiScale.attach(gui)

local root = Instance.new("Frame")
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.36)
root.Size = UDim2.new(1, 0, 0, 300) -- alto de sobra: el CanvasGroup de detalles recorta a este tamaño
root.BackgroundTransparency = 1
root.Parent = gui

-- La banda y sus filos no tienen hijos: van inclinados sin inclinar el texto.
local band = Instance.new("Frame")
band.Name = "Band"
band.AnchorPoint = Vector2.new(0.5, 0.5)
band.Size = UDim2.new(1.3, 0, 0, 124)
band.Rotation = -3
band.BorderSizePixel = 0
band.BackgroundTransparency = 0.06
band.Parent = root
local bandGradient = Instance.new("UIGradient") -- luz arriba, algo más oscura abajo: volumen
bandGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200))
bandGradient.Rotation = 90
bandGradient.Parent = band
local edgeFade = NumberSequence.new({ -- los filos se desvanecen hacia los lados
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.2, 0),
	NumberSequenceKeypoint.new(0.8, 0),
	NumberSequenceKeypoint.new(1, 1),
})

local edges = {}
for _, offset in { -66, 66 } do
	local edge = Instance.new("Frame")
	edge.AnchorPoint = Vector2.new(0.5, 0.5)
	edge.Size = UDim2.new(1.3, 0, 0, 4)
	edge.Rotation = -3
	edge.BorderSizePixel = 0
	edge.BackgroundColor3 = Color3.new(1, 1, 1)
	edge.BackgroundTransparency = 0.25
	edge.Parent = root
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = edgeFade
	gradient.Parent = edge
	table.insert(edges, { frame = edge, offset = offset })
end

local title = label(root, Enum.Font.GothamBlack, 64, -30)
title.Name = "Title"
local titleStroke = stroke(title, 3, 0.25)
local titleScale = Instance.new("UIScale")
titleScale.Parent = title

-- Detalles en un CanvasGroup: se desvanecen juntos con GroupTransparency.
local details = Instance.new("CanvasGroup")
details.AnchorPoint = Vector2.new(0.5, 0.5)
details.Position = UDim2.fromScale(0.5, 0.5)
details.Size = UDim2.fromScale(1, 1)
details.BackgroundTransparency = 1
details.Parent = root

local subtitle = label(details, Enum.Font.GothamBold, 24, 26)
stroke(subtitle, 2, 0.55)
local nextLine = label(details, Enum.Font.GothamMedium, 19, 90)
stroke(nextLine, 2, 0.4)

local progress = Instance.new("Frame")
progress.AnchorPoint = Vector2.new(0.5, 0.5)
progress.Position = UDim2.new(0.5, 0, 0.5, 122)
progress.Size = UDim2.new(1, 0, 0, 22)
progress.BackgroundTransparency = 1
progress.Parent = details
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 6)
layout.Parent = progress
local progressText = label(progress, Enum.Font.GothamBold, 18, 0)
stroke(progressText, 2, 0.4)

local pill = Instance.new("Frame")
pill.AnchorPoint = Vector2.new(0.5, 0.5)
pill.Position = UDim2.new(0.5, 0, 0.5, -96)
pill.Size = UDim2.fromOffset(0, 30)
pill.AutomaticSize = Enum.AutomaticSize.X
pill.BorderSizePixel = 0
pill.Parent = details
local pillCorner = Instance.new("UICorner")
pillCorner.CornerRadius = UDim.new(1, 0)
pillCorner.Parent = pill
local pillPadding = Instance.new("UIPadding")
pillPadding.PaddingLeft = UDim.new(0, 16)
pillPadding.PaddingRight = UDim.new(0, 16)
pillPadding.Parent = pill
local pillStroke = Instance.new("UIStroke")
pillStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
pillStroke.Color = Color3.new(1, 1, 1)
pillStroke.Thickness = 2
pillStroke.Parent = pill
local pillScale = Instance.new("UIScale")
pillScale.Parent = pill
local pillText = Instance.new("TextLabel")
pillText.Size = UDim2.fromScale(0, 1)
pillText.AutomaticSize = Enum.AutomaticSize.X
pillText.BackgroundTransparency = 1
pillText.Font = Enum.Font.GothamBold
pillText.TextSize = 16
pillText.TextColor3 = Color3.new(1, 1, 1)
pillText.Parent = pill

-- Medalla del nivel (a la derecha de la banda).
local medalFrame = Instance.new("Frame")
medalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
medalFrame.Position = UDim2.new(0.5, 300, 0.5, -30)
medalFrame.Size = UDim2.fromOffset(78, 78)
medalFrame.BorderSizePixel = 0
medalFrame.Visible = false
medalFrame.Parent = root
local medalCorner = Instance.new("UICorner")
medalCorner.CornerRadius = UDim.new(1, 0)
medalCorner.Parent = medalFrame
local medalRing = Instance.new("UIStroke")
medalRing.Thickness = 4
medalRing.Color = Color3.new(1, 1, 1)
medalRing.Parent = medalFrame
local medalScale = Instance.new("UIScale")
medalScale.Parent = medalFrame
local medalName = Instance.new("TextLabel")
medalName.Size = UDim2.fromScale(1, 1)
medalName.BackgroundTransparency = 1
medalName.Font = Enum.Font.GothamBlack
medalName.TextSize = 15
medalName.TextColor3 = Color3.fromRGB(40, 30, 20)
medalName.Parent = medalFrame
local medalNote = Instance.new("TextLabel")
medalNote.AnchorPoint = Vector2.new(0.5, 0)
medalNote.Position = UDim2.new(0.5, 0, 1, 6)
medalNote.Size = UDim2.fromOffset(200, 18)
medalNote.BackgroundTransparency = 1
medalNote.Font = Enum.Font.GothamBold
medalNote.TextSize = 15
medalNote.TextColor3 = Color3.new(1, 1, 1)
medalNote.Parent = medalFrame
stroke(medalNote, 2, 0.4)

gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

-- ── Contenido ─────────────────────────────────────────────────────────

-- Rombos de progreso: superados rellenos, el recién superado con el color del bioma, el resto huecos.
local function buildDiamonds(index: number, total: number, color: Color3): Frame?
	for _, child in progress:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	if total > MAX_DIAMONDS then
		progressText.Visible = true
		progressText.Text = string.format("%d / %d LEVELS", index, total)
		return nil
	end
	progressText.Visible = false
	local newest: Frame? = nil
	for i = 1, total do
		-- UIListLayout ignora la rotación de sus hijos: el hueco va en la fila y el rombo girado dentro.
		local slot = Instance.new("Frame")
		slot.LayoutOrder = i
		slot.Size = UDim2.fromOffset(18, 18)
		slot.BackgroundTransparency = 1
		slot.Parent = progress
		local diamond = Instance.new("Frame")
		diamond.AnchorPoint = Vector2.new(0.5, 0.5)
		diamond.Position = UDim2.fromScale(0.5, 0.5)
		diamond.Size = UDim2.fromOffset(12, 12)
		diamond.Rotation = 45
		diamond.BorderSizePixel = 0
		diamond.BackgroundColor3 = if i == index then color else Color3.new(1, 1, 1)
		diamond.BackgroundTransparency = if i <= index then 0 else 1
		local outline = Instance.new("UIStroke")
		outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		outline.Color = Color3.new(1, 1, 1)
		outline.Thickness = if i == index then 2.5 else 1.5
		outline.Transparency = if i <= index + 1 then 0 else 0.45
		outline.Parent = diamond
		diamond.Parent = slot
		if i == index then
			newest = diamond
		end
	end
	return newest
end

local token = 0
local finalToken = -1 -- token de la pantalla de meta visible (para showResult)

local function formatTime(seconds: number): string
	local minutes = math.floor(seconds / 60)
	return string.format("%d:%05.2f", minutes, seconds - minutes * 60)
end

-- data = Checkpoints.info del servidor: index, total, title, nextTitle, final, color, newBiome.
function CheckpointBanner.show(data: { [string]: any })
	token += 1
	local mine = token
	local index = if type(data.index) == "number" then data.index else 0
	local total = if type(data.total) == "number" then data.total else index
	local color = if typeof(data.color) == "Color3" then data.color else DEFAULT_COLOR
	local final = data.final == true
	local tutorial = data.tutorial == true
	local time = if type(data.time) == "number" then data.time else nil
	finalToken = if final then mine else -1

	local chapter = if type(data.chapter) == "number" and not final then data.chapter else nil
	band.BackgroundColor3 = color
	title.Text = if final and tutorial then "TUTORIAL COMPLETE!" elseif final then "COURSE COMPLETE!" elseif chapter then string.format("CHAPTER %d CLEAR!", chapter) else "CHECKPOINT"
	title.TextSize = if final or chapter then 54 else 64
	titleStroke.Color = color:Lerp(Color3.new(0, 0, 0), 0.55)
	subtitle.Text = if final and tutorial
		then "You're ready to fly with a friend!"
		elseif final and time
		then string.format("%d / %d LEVELS  ·  TIME %s", total, total, formatTime(time))
		elseif final then string.format("%d / %d LEVELS  ·  Great flying, duo!", total, total)
		else string.format("LEVEL %02d CLEARED  ·  %s", index, tostring(data.title or ""))
	nextLine.Text = if final and tutorial
		then "Land on the island, then step on a Duo pad together"
		elseif final
		then "Land on the island to return to the lobby"
		else string.format("NEXT  »  LEVEL %02d  ·  %s", index + 1, tostring(data.nextTitle or ""))
	if chapter and type(data.chapterTitle) == "string" then
		subtitle.Text = string.format("%s COMPLETE  ·  LEVEL %02d CLEARED", upper(data.chapterTitle), index)
	end
	local newBiome = data.newBiome
	pill.Visible = type(newBiome) == "string"
	pill.BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.25)
	pillScale.Scale = 1
	pillText.Text = if type(newBiome) == "string" then "NEW BIOME  ·  " .. upper(newBiome) else ""

	-- Medalla del nivel (con un salto; "NEW BEST" si mejora la guardada).
	local medal = if type(data.medal) == "number" then MEDALS[data.medal] else nil
	medalFrame.Visible = false
	if medal then
		medalFrame.BackgroundColor3 = medal.color
		medalName.Text = medal.name
		medalNote.Text = if data.medalImproved == true then medal.note .. "  ·  NEW BEST" else medal.note
		task.delay(0.35, function()
			if token ~= mine then
				return
			end
			medalFrame.Visible = true
			medalScale.Scale = 2.4
			tween(medalScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
	end
	local newest = buildDiamonds(index, total, color)

	-- Estado inicial (fuera de pantalla / invisible) y entrada.
	band.Position = UDim2.new(-0.7, 0, BAND_Y.Scale, BAND_Y.Offset)
	for _, edge in edges do
		edge.frame.Position = UDim2.new(-0.75, 0, 0.5, BAND_Y.Offset + edge.offset)
	end
	title.TextTransparency = 1
	titleStroke.Transparency = 1
	titleScale.Scale = 1.7
	details.GroupTransparency = 1
	details.Position = UDim2.new(0.5, 0, 0.5, 14)
	gui.Enabled = true

	tween(band, 0.3, { Position = UDim2.new(0.5, 0, BAND_Y.Scale, BAND_Y.Offset) })
	for i, edge in edges do
		task.delay(0.03 * i, function()
			if token == mine then
				tween(edge.frame, 0.3, { Position = UDim2.new(0.5, 0, 0.5, BAND_Y.Offset + edge.offset) })
			end
		end)
	end
	task.delay(0.08, function()
		if token ~= mine then
			return
		end
		tween(title, 0.15, { TextTransparency = 0 })
		tween(titleStroke, 0.15, { Transparency = 0.25 })
		tween(titleScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	task.delay(0.2, function()
		if token ~= mine then
			return
		end
		tween(details, 0.25, { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) })
		if newest then
			local pop = Instance.new("UIScale")
			pop.Scale = 2.2
			pop.Parent = newest
			tween(pop, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end)

	-- Salida por la derecha.
	task.delay((if final then FINAL_HOLD_TIME else HOLD_TIME) + 0.3, function()
		if token ~= mine then
			return
		end
		tween(band, 0.3, { Position = UDim2.new(1.7, 0, BAND_Y.Scale, BAND_Y.Offset) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		for _, edge in edges do
			tween(edge.frame, 0.3, { Position = UDim2.new(1.75, 0, 0.5, BAND_Y.Offset + edge.offset) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		end
		tween(title, 0.2, { TextTransparency = 1 })
		tween(titleStroke, 0.2, { Transparency = 1 })
		tween(details, 0.2, { GroupTransparency = 1 })
		medalFrame.Visible = false
		task.delay(0.35, function()
			if token == mine then
				gui.Enabled = false
			end
		end)
	end)
end

-- Resultado de la meta (llega poco después de la pantalla, cuando responde el almacén de la clasificación):
-- data.duoRecord (nueva mejor marca del dúo), data.rank (puesto en el tablón), data.personalBest.
-- Si la pantalla de meta ya se fue, no se muestra (el tablón del lobby lo refleja igual).
function CheckpointBanner.showResult(data: { [string]: any })
	if finalToken ~= token or not gui.Enabled then
		return
	end
	local rank = if type(data.rank) == "number" then data.rank else nil
	local text: string? = nil
	if data.duoRecord == true then
		text = if rank then string.format("NEW DUO RECORD  ·  #%d ON THE BOARD", rank) else "NEW DUO RECORD!"
	elseif data.personalBest == true then
		text = "NEW PERSONAL BEST!"
	elseif rank then
		text = string.format("#%d ON THE DUO BOARD", rank)
	end
	if not text then
		return
	end
	pill.Visible = true
	pill.BackgroundColor3 = RECORD_COLOR:Lerp(Color3.new(0, 0, 0), 0.3)
	pillText.Text = text
	pillScale.Scale = 1.5
	tween(pillScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
end

return CheckpointBanner
