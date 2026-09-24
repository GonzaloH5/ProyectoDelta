--!strict
-- Carga del mapa alrededor de cada dúo (StreamingEnabled).
--
-- Los niveles e islas del mapa usan ModelStreamingMode = Default: cada cliente recibe sus piezas poco a poco,
-- por distancia (StreamingTargetRadius), nunca un nivel entero en un solo paso. (Antes eran
-- PersistentPerPlayer, que para quien no está fijado se comporta como Atomic: al entrar en radio llegaba el
-- modelo completo, ~1.000-1.500 piezas con el vestido, y el cliente daba un tirón: al acercarse al mapa desde
-- el lobby y en cada checkpoint.) La colisión es del servidor, que siempre tiene el mapa entero.
--
-- Lo único que hace este módulo: cuando el ala salta de sitio (despegue desde el lobby o reaparición en el
-- último checkpoint), pide al motor que cargue la zona de destino durante la cuenta atrás.

local LevelStreaming = {}

-- Por si el place se guardó con un mapa antiguo (modelos PersistentPerPlayer o Atomic): se pasan a Default
-- al arrancar el servidor, antes de que entre nadie. Regenerar el mapa con MapBuilder ya los crea así.
function LevelStreaming.load(map: Instance?)
	if not map then
		return
	end
	for _, child in map:GetChildren() do
		if child:IsA("Model") and child.ModelStreamingMode ~= Enum.ModelStreamingMode.Default then
			child.ModelStreamingMode = Enum.ModelStreamingMode.Default
		end
	end
end

-- Pide cargar la zona alrededor de `position` para el jugador (sin bloquear: la cuenta atrás sigue).
function LevelStreaming.prepare(player: Player, position: Vector3)
	task.spawn(function()
		pcall(player.RequestStreamAroundAsync, player, position, 5)
	end)
end

return LevelStreaming
