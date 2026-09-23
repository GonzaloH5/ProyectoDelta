--!strict
-- Suavizado independiente del framerate, compartido por servidor y cliente.

local GliderMath = {}

-- Persigue `target` de forma exponencial. `rate` en 1/s.
function GliderMath.approach(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

-- Muelle amortiguado (semi-implícito). Devuelve posición y velocidad nuevas.
-- omega = frecuencia (rad/s), zeta = amortiguación (1 = crítica, <1 oscila un poco).
function GliderMath.spring(x: number, v: number, target: number, omega: number, zeta: number, dt: number): (number, number)
	local accel = omega * omega * (target - x) - 2 * zeta * omega * v
	v += accel * dt
	x += v * dt
	return x, v
end

-- Curva de respuesta con signo para x ∈ [-1, 1]. exponent < 1 = más brusco cerca de 0 (arcade).
function GliderMath.curve(x: number, exponent: number): number
	x = math.clamp(x, -1, 1)
	return math.sign(x) * math.abs(x) ^ exponent
end

-- Ruido continuo en [-1, 1] para corrientes de aire suaves.
function GliderMath.flow(t: number, seed: number): number
	return math.clamp(math.noise(t, seed, seed * 0.37) * 2, -1, 1)
end

-- Ángulo de rumbo (yaw) de un vector horizontal, compatible con CFrame.Angles(0, yaw, 0).
function GliderMath.yawOf(direction: Vector3): number
	return math.atan2(-direction.X, -direction.Z)
end

return GliderMath
