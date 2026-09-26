--!strict
-- Fundidos a negro para los saltos de cámara (solo en este cliente):
--   · al perder el ala: oscurece durante la voltereta y aclara al reaparecer (no se ve el salto de cámara)
--   · Respawn con el botón: fundido corto desde negro
--   · al empezar a volar desde el lobby: aparece desde negro
--   · al pasar de Flight School al nivel 1 (el ala salta a la salida del recorrido): desde negro
-- Lee los atributos del ala montada (State, Respawns).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ScreenFade = {}

local gui = Instance.new("ScreenGui")
gui.Name = "GliderFade"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 80
local cover = Instance.new("Frame")
cover.Size = UDim2.fromScale(1, 1)
cover.BackgroundColor3 = Color3.new(0, 0, 0)
cover.BackgroundTransparency = 1
cover.BorderSizePixel = 0
cover.Parent = gui
gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

local current: Model? = nil
local lastState: string? = nil
local lastRespawns = 0
local lastTutorial = false

local function fadeTo(transparency: number, seconds: number)
	TweenService:Create(cover, TweenInfo.new(seconds, Enum.EasingStyle.Quad), { BackgroundTransparency = transparency }):Play()
end

local function fromBlack(seconds: number)
	cover.BackgroundTransparency = 0
	fadeTo(1, seconds)
end

-- Cada fotograma (glider = ala montada o nil).
function ScreenFade.update(glider: Model?)
	if glider ~= current then
		current = glider
		if glider then
			local respawns = glider:GetAttribute("Respawns")
			lastRespawns = if type(respawns) == "number" then respawns else 0
			lastTutorial = glider:GetAttribute("Tutorial") == true
			lastState = nil
			fromBlack(0.8) -- empieza el vuelo
		else
			fadeTo(1, 0.3)
		end
	end
	if not glider then
		return
	end
	local state = glider:GetAttribute("State")
	if state == "Ended" and lastState == "Flying" and glider:GetAttribute("Completed") ~= true then
		fadeTo(0, 0.5) -- el ala se pierde: se oscurece durante la voltereta
	end
	lastState = if type(state) == "string" then state else nil
	local tutorial = glider:GetAttribute("Tutorial") == true
	if lastTutorial and not tutorial then
		fromBlack(0.9) -- Flight School → nivel 1
	end
	lastTutorial = tutorial
	local respawns = glider:GetAttribute("Respawns")
	if type(respawns) == "number" then
		if respawns > lastRespawns then
			fromBlack(0.45)
		end
		lastRespawns = respawns
	end
end

return ScreenFade
