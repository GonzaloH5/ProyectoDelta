--!strict
-- Obstáculos móviles: su posición es una función del reloj compartido (workspace:GetServerTimeNow()), la misma
-- en el servidor (colisión), en el cliente (dibujo suave, sin tirones de red) y en el FlightTester / tools/sim.
--
-- Cada móvil es una pieza del mapa con atributos (los pone MapBuilder):
--   Motion  "swing"   tronco colgado de un pivote (Pivot) que se balancea de lado a lado ±Amplitude grados
--           "gate"    compuerta que sale de una pared (Side ±1) y deja un hueco entre MinGap y MaxGap studs
--           "spinner" aspa que gira alrededor del eje del corredor (Pivot) empezando en Angle grados
--   Period (s) · Phase (0-1) · Pivot (CFrame: marco del corredor en el obstáculo, mirando hacia delante)
--   swing: Length (largo del tronco) · gate: DoorWidth · spinner: Radius (largo del aspa)

local Movers = {}

export type Params = {
	motion: string,
	period: number,
	phase: number,
	pivot: CFrame,
	amplitude: number,
	length: number,
	side: number,
	minGap: number,
	maxGap: number,
	doorWidth: number,
	radius: number,
	angle: number,
}

local function number(part: Instance, name: string, default: number): number
	local value = part:GetAttribute(name)
	return if type(value) == "number" then value else default
end

-- Parámetros de un móvil (nil si la pieza no lo es).
function Movers.read(part: Instance): Params?
	local motion = part:GetAttribute("Motion") or part:GetAttribute("VisualMotion") -- colisionador o copia visual
	local pivot = part:GetAttribute("Pivot")
	if type(motion) ~= "string" or typeof(pivot) ~= "CFrame" then
		return nil
	end
	return {
		motion = motion,
		period = math.max(number(part, "Period", 4), 0.5),
		phase = number(part, "Phase", 0),
		pivot = pivot,
		amplitude = number(part, "Amplitude", 50),
		length = number(part, "Length", 60),
		side = number(part, "Side", 1),
		minGap = number(part, "MinGap", 80),
		maxGap = number(part, "MaxGap", 160),
		doorWidth = number(part, "DoorWidth", 100),
		radius = number(part, "Radius", 60),
		angle = number(part, "Angle", 0),
	}
end

-- Fase del ciclo (0-1) en el instante t.
local function cycle(params: Params, t: number): number
	return (t / params.period + params.phase) % 1
end

-- CFrame de la pieza en el instante t (segundos del reloj compartido).
function Movers.cframeAt(params: Params, t: number): CFrame
	local k = cycle(params, t)
	if params.motion == "swing" then
		local angle = math.rad(params.amplitude) * math.sin(2 * math.pi * k)
		return params.pivot * CFrame.Angles(0, 0, angle) * CFrame.new(0, -params.length / 2, 0)
	elseif params.motion == "gate" then
		-- Abre y cierra suave (coseno): hueco entre minGap y maxGap.
		local open = 0.5 - 0.5 * math.cos(2 * math.pi * k)
		local gap = params.minGap + (params.maxGap - params.minGap) * open
		return params.pivot * CFrame.new(params.side * (gap / 2 + params.doorWidth / 2), 0, 0)
	elseif params.motion == "spinner" then
		local angle = math.rad(params.angle) + 2 * math.pi * k
		return params.pivot * CFrame.Angles(0, 0, angle) * CFrame.new(0, params.radius / 2, 0)
	end
	return params.pivot
end

-- Apertura de una compuerta (0 = hueco mínimo, 1 = máximo) y fase del ciclo (el máximo llega en 0,5).
function Movers.gateOpenness(params: Params, t: number): (number, number)
	local k = cycle(params, t)
	return 0.5 - 0.5 * math.cos(2 * math.pi * k), k
end

-- Reloj compartido (servidor y clientes ven lo mismo).
function Movers.now(): number
	return workspace:GetServerTimeNow()
end

return Movers
