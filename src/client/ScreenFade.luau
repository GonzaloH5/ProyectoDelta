--!strict
-- Fundidos a negro para los saltos de cámara (solo en este cliente):
--   · al perder el ala: oscurece durante la voltereta y aclara al reaparecer (no se ve el salto de cámara)
--   · Respawn con el botón: fundido corto desde negro
--   · al empezar a volar desde el lobby: aparece desde negro
--   · SKIP de Flight School (el ala salta al despegue del recorrido, atributo Relocations): desde negro
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
local lastRelocations = 0

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
			local relocations = glider:GetAttribute("Relocations")
			lastRelocations = if type(relocations) == "number" then relocations else 0
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
	local relocations = glider:GetAttribute("Relocations")
	if type(relocations) == "number" and relocations > lastRelocations then
		lastRelocations = relocations
		fromBlack(0.9) -- SKIP de Flight School: el ala salta al despegue
	end
	local respawns = glider:GetAttribute("Respawns")
	if type(respawns) == "number" then
		if respawns > lastRespawns then
			fromBlack(0.45)
		end
		lastRespawns = respawns
	end
end

return ScreenFade
