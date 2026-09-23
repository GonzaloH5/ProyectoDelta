--!strict
-- Grupos de colisión del juego. Ningún ala ni jugador colgado choca con nada físicamente,
-- y las comprobaciones de choque del vuelo (Probe) ignoran a todos los dúos: un ala solo
-- "choca" con el mapa, nunca con otra ala ni con jugadores de otro dúo.

local PhysicsService = game:GetService("PhysicsService")

local CollisionGroups = {
	Gliders = "Gliders", -- piezas de todas las alas
	Riders = "GliderRiders", -- jugadores colgados de cualquier ala
	Probe = "GliderProbe", -- raycasts/blockcasts de choque y techo
}

local configured = false

function CollisionGroups.setup()
	if configured then
		return
	end
	configured = true

	for _, name in { CollisionGroups.Gliders, CollisionGroups.Riders, CollisionGroups.Probe } do
		PhysicsService:RegisterCollisionGroup(name)
	end
	local flying = { CollisionGroups.Gliders, CollisionGroups.Riders }
	for _, group in PhysicsService:GetRegisteredCollisionGroups() do
		for _, name in flying do
			PhysicsService:CollisionGroupSetCollidable(name, group.name, false)
		end
	end
end

-- Parámetros de consulta para el vuelo: ven el mapa, no ven alas ni jugadores colgados.
function CollisionGroups.probeParams(): RaycastParams
	local params = RaycastParams.new()
	params.CollisionGroup = CollisionGroups.Probe
	return params
end

return CollisionGroups
