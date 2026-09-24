--!strict
-- Obstáculos móviles en el servidor (Movers.luau). Al arrancar, cada pieza móvil del mapa (atributo Motion) pasa
-- a ser el COLISIONADOR invisible, y se crea al lado una copia visual (sin consultas, etiqueta
-- GliderMoverVisual) que cada cliente anima por su cuenta con el mismo reloj: se ve suave y coincide con lo que
-- choca. En cada paso solo se mueven los colisionadores cerca de alguna ala en vuelo.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Movers = require(ReplicatedStorage:WaitForChild("Glider"):WaitForChild("Movers"))

local MoverService = {}

MoverService.VISUAL_TAG = "GliderMoverVisual"
local ACTIVE_RADIUS = 1500 -- studs de un ala a los que se actualiza un colisionador

type Entry = { collider: BasePart, params: Movers.Params }
local entries: { Entry } = {}

-- Prepara los móviles de un mapa (Workspace.Map o Map.Tutorial). Se puede llamar una vez por mapa.
function MoverService.load(map: Instance?)
	if not map then
		return
	end
	for _, part in map:GetDescendants() do
		if not (part:IsA("BasePart") and part:GetAttribute("Motion")) or part:GetAttribute("MoverVisual") then
			continue
		end
		local params = Movers.read(part)
		if not params then
			continue
		end
		local visual = part:Clone()
		visual.Name = part.Name .. "Visual"
		visual.CanCollide = false
		visual.CanQuery = false
		visual.CanTouch = false
		-- La copia no es colisionador (ni para tools/sim): su movimiento va en VisualMotion.
		visual:SetAttribute("VisualMotion", part:GetAttribute("Motion"))
		visual:SetAttribute("Motion", nil)
		visual:SetAttribute("MoverVisual", true)
		CollectionService:AddTag(visual, MoverService.VISUAL_TAG)
		visual.Parent = part.Parent
		part.Transparency = 1
		part.CastShadow = false
		table.insert(entries, { collider = part, params = params })
	end
end

-- Cada paso: mueve los colisionadores cercanos a alguna ala (positions = raíces de las alas en vuelo).
function MoverService.step(positions: { Vector3 })
	if #entries == 0 or #positions == 0 then
		return
	end
	local now = Movers.now()
	for _, entry in entries do
		local pivot = entry.params.pivot.Position
		local near = false
		for _, position in positions do
			if (position - pivot).Magnitude < ACTIVE_RADIUS then
				near = true
				break
			end
		end
		if near then
			entry.collider.CFrame = Movers.cframeAt(entry.params, now)
		end
	end
end

function MoverService.count(): number
	return #entries
end

return MoverService
