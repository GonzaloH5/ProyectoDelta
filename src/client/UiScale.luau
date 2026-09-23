--!strict
-- Interfaz adaptable: cada ScreenGui recibe un UIScale según el tamaño de pantalla (referencia 1280×720),
-- limitado a [MIN, MAX]. Los botones y paneles medidos en píxeles se ven proporcionados en móvil y en PC.

local UiScale = {}

local REFERENCE = Vector2.new(1280, 720)
local MIN, MAX = 0.6, 1.2

local scales: { UIScale } = {}

function UiScale.get(): number
	local camera = workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else REFERENCE
	return math.clamp(math.min(size.X / REFERENCE.X, size.Y / REFERENCE.Y), MIN, MAX)
end

local function refresh()
	local scale = UiScale.get()
	for _, uiScale in scales do
		uiScale.Scale = scale
	end
end

function UiScale.attach(gui: ScreenGui)
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = UiScale.get()
	uiScale.Parent = gui
	table.insert(scales, uiScale)
end

local viewportConnection: RBXScriptConnection? = nil
local function watchCamera()
	if viewportConnection then
		viewportConnection:Disconnect()
	end
	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
	end
	refresh()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
watchCamera()

return UiScale
