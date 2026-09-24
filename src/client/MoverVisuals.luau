--!strict
-- Dibuja los obstáculos móviles en el cliente (copias visuales con etiqueta GliderMoverVisual que crea
-- MoverService): cada fotograma se colocan con Movers.cframeAt y el reloj compartido, así se mueven suaves y a
-- la vez que el colisionador del servidor. Con StreamingEnabled aparecen y desaparecen solos.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Movers = require(ReplicatedStorage:WaitForChild("Glider"):WaitForChild("Movers"))

local TAG = "GliderMoverVisual"
local VISIBLE_RADIUS = 1200 -- studs de la cámara a los que se animan

local tracked: { [BasePart]: Movers.Params } = {}

local function add(instance: Instance)
	if instance:IsA("BasePart") then
		local params = Movers.read(instance)
		if params then
			tracked[instance] = params
		end
	end
end

for _, instance in CollectionService:GetTagged(TAG) do
	add(instance)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance)
	tracked[instance :: BasePart] = nil
end)

RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local now = Movers.now()
	for part, params in tracked do
		if (params.pivot.Position - eye).Magnitude < VISIBLE_RADIUS then
			part.CFrame = Movers.cframeAt(params, now)
		end
	end
end)

return {}
