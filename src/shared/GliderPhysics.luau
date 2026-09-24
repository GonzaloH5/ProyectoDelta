--!strict
-- GliderPhysics: el vuelo del ala delta en un solo sitio, compartido por el servidor (GliderSession), el piloto
-- de pruebas (FlightTester) y la imitación de tools/sim. Si cambia una ecuación, cambia para todos.
--
-- Principios (juego cooperativo, no un obby de precisión):
--   · Respuesta tranquila cerca del punto neutro: zona muerta + curva > 1. "Más o menos nivelados" = vuelo
--     recto y a la misma altura; los movimientos claros siguen llegando al máximo.
--   · Tocar algo no es morir: el ala RESBALA a lo largo de la superficie (se quita la parte de la velocidad
--     que entra en ella) y se separa un poco. Los golpes fuertes y los roces largos quitan un corazón; con 3
--     corazones perdidos se choca. Tras un golpe hay unos instantes de invulnerabilidad.
--   · Suelo con cojín (como el techo): cerca del suelo el ala se levanta sola; rozarlo solo levanta polvo.
--   · Inercia suave: en picado se gana algo de velocidad y subiendo se pierde; tras un golpe se recupera.
--   · Asistencia de rumbo opcional (la da el servidor): empuja suavemente hacia la línea ideal cuando nadie
--     está girando fuerte.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Glider = ReplicatedStorage:WaitForChild("Glider")
local Config = require(Glider:WaitForChild("GliderConfig"))
local GliderMath = require(Glider:WaitForChild("GliderMath"))

local GliderPhysics = {}

export type State = {
	yaw: number, -- rumbo (radianes, compatible con CFrame.Angles(0, yaw, 0))
	speed: number, -- avance actual (studs/s)
	verticalSpeed: number,
	roll: number,
	rollVelocity: number,
	pitch: number,
	pitchVelocity: number,
	turnRate: number, -- grados/s (+ = izquierda)
	push: Vector3, -- empujón de separación tras un contacto (se desvanece)
}

export type Health = {
	hearts: number,
	invulnerableUntil: number,
	scrapeTime: number, -- segundos de roce acumulados (quitan un corazón al llegar a ScrapeDamageTime)
	lastContact: number,
}

export type Dimensions = { span: number, wingTop: number }

export type Sense = {
	maxVertical: number,
	minVertical: number,
	floorGap: number?, -- studs entre los pies y el suelo de debajo (si está cerca)
	contact: RaycastResult?,
	harmless: boolean, -- el contacto es un suelo (Kind Ground/Grass o superficie que mira hacia arriba): solo roza
}

-- Eventos de daño que devuelve fly(): "scrape" (roce), "impact" (golpe: −1 corazón), "crash" (sin corazones).
export type Event = "scrape" | "impact" | "crash"

export type FlyResult = {
	velocity: Vector3,
	event: Event?,
	contact: RaycastResult?,
	landed: boolean,
	skimming: boolean,
}

local function forwardOf(yaw: number): Vector3
	return CFrame.Angles(0, yaw, 0).LookVector
end
GliderPhysics.forwardOf = forwardOf

local function unwrap(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

function GliderPhysics.newState(yaw: number): State
	return {
		yaw = yaw,
		speed = Config.ForwardSpeed,
		verticalSpeed = 0,
		roll = 0,
		rollVelocity = 0,
		pitch = 0,
		pitchVelocity = 0,
		turnRate = 0,
		push = Vector3.zero,
	}
end

function GliderPhysics.newHealth(): Health
	return { hearts = Config.WingHearts, invulnerableUntil = -math.huge, scrapeTime = 0, lastContact = -math.huge }
end

-- ── Entradas ──────────────────────────────────────────────────────────

-- Posiciones de ambos en la barra (studs desde el centro) → LiftInput [0, 1] y BalanceInput [-1, 1].
--   LiftInput    = promedio de lo lejos del centro que está cada uno (da igual hacia qué lado)
--   BalanceInput = hacia dónde cae el peso de los dos juntos (> 0: a la izquierda → gira a la izquierda)
function GliderPhysics.inputs(a: number, b: number): (number, number)
	local inner, outer = Config.BarInnerOffset, Config.BarOuterOffset
	local function outwardness(position: number): number
		return math.clamp((math.abs(position) - inner) / (outer - inner), 0, 1)
	end
	local lift = (outwardness(a) + outwardness(b)) / 2
	local balance = math.clamp(-((a + b) / 2) / ((outer - inner) / 2), -1, 1)
	return lift, balance
end

-- Zona muerta + curva: x ∈ [-1, 1] → [-1, 1]. exponent > 1 = tranquilo cerca de 0, completo en los extremos.
local function shape(x: number, deadzone: number, exponent: number): number
	x = math.clamp(x, -1, 1)
	local magnitude = math.abs(x)
	if magnitude <= deadzone then
		return 0
	end
	return math.sign(x) * ((magnitude - deadzone) / (1 - deadzone)) ^ exponent
end

local function unshape(y: number, deadzone: number, exponent: number): number
	y = math.clamp(y, -1, 1)
	if y == 0 then
		return 0
	end
	return math.sign(y) * (deadzone + (1 - deadzone) * math.abs(y) ^ (1 / exponent))
end

-- LiftInput → sustentación [-1, 1] (0 = mantener altura).
function GliderPhysics.lift(liftInput: number): number
	local neutral = Config.NeutralLiftPoint
	local x = if liftInput <= neutral then (liftInput - neutral) / neutral else (liftInput - neutral) / (1 - neutral)
	return shape(x, Config.LiftDeadzone, Config.LiftCurve)
end

-- BalanceInput → giro [-1, 1].
function GliderPhysics.balance(balanceInput: number): number
	return shape(balanceInput, Config.BalanceDeadzone, Config.BalanceCurve)
end

-- Inversas (para los pilotos automáticos): qué LiftInput / BalanceInput dan esa sustentación / ese giro.
function GliderPhysics.liftInputFor(lift: number): number
	local neutral = Config.NeutralLiftPoint
	local x = unshape(lift, Config.LiftDeadzone, Config.LiftCurve)
	return if x <= 0 then neutral + x * neutral else neutral + x * (1 - neutral)
end

function GliderPhysics.balanceInputFor(balance: number): number
	return unshape(balance, Config.BalanceDeadzone, Config.BalanceCurve)
end

-- Sustentación necesaria para una velocidad vertical deseada (studs/s).
function GliderPhysics.liftFor(verticalSpeed: number): number
	return if verticalSpeed >= 0 then verticalSpeed / Config.MaxClimbSpeed else verticalSpeed / Config.MaxFallSpeed
end

-- Persecución pura: giro (grados/s, + = izquierda) para ir hacia `goal` desde `position` mirando a `forward`.
function GliderPhysics.pursuitTurn(position: Vector3, forward: Vector3, goal: Vector3?, speed: number?): number
	if not goal then
		return 0
	end
	local toGoal = (goal - position) * Vector3.new(1, 0, 1)
	local flat = forward * Vector3.new(1, 0, 1)
	if toGoal.Magnitude < 1e-3 or flat.Magnitude < 1e-3 then
		return 0
	end
	flat = flat.Unit
	local alpha = math.atan2(flat:Cross(toGoal).Y, flat:Dot(toGoal))
	local turn = math.deg(2 * (speed or Config.ForwardSpeed) * math.sin(alpha) / math.max(toGoal.Magnitude, 1))
	return math.clamp(turn, -Config.MaxTurnRate, Config.MaxTurnRate)
end

-- ── Paso de vuelo ─────────────────────────────────────────────────────

-- Avanza el estado dt segundos. maxVertical / minVertical = topes del techo y del cojín del suelo;
-- assistTurn = giro de la asistencia (grados/s), solo cuenta si nadie gira fuerte.
function GliderPhysics.step(state: State, liftInput: number, balanceInput: number, dt: number, maxVertical: number, minVertical: number, assistTurn: number)
	-- Sustentación → velocidad vertical (suavizada), recortada por techo y suelo.
	local lift = GliderPhysics.lift(liftInput)
	local target = if lift >= 0 then lift * Config.MaxClimbSpeed else lift * Config.MaxFallSpeed
	state.verticalSpeed = GliderMath.approach(state.verticalSpeed, target, Config.VerticalResponse, dt)
	state.verticalSpeed = math.min(math.max(state.verticalSpeed, minVertical), maxVertical)

	-- Balance → alabeo (muelle) → giro de rumbo. La asistencia se suma cuando el balance es pequeño.
	local balance = GliderPhysics.balance(balanceInput)
	state.roll, state.rollVelocity = GliderMath.spring(state.roll, state.rollVelocity, balance * Config.MaxRoll, Config.RollResponse, Config.RollDamping, dt)
	local targetTurn = (state.roll / Config.MaxRoll) * Config.MaxTurnRate
	if math.abs(balance) < Config.AssistInputThreshold then
		targetTurn += assistTurn
	end
	state.turnRate = GliderMath.approach(state.turnRate, targetTurn, Config.TurnResponse, dt)
	state.yaw += math.rad(state.turnRate) * dt

	-- Pitch visual según la velocidad vertical.
	local range = if state.verticalSpeed >= 0 then Config.MaxClimbSpeed else Config.MaxFallSpeed
	state.pitch, state.pitchVelocity = GliderMath.spring(state.pitch, state.pitchVelocity, (state.verticalSpeed / range) * Config.MaxPitch, Config.PitchResponse, Config.PitchDamping, dt)

	-- Inercia: en picado se gana velocidad, subiendo se pierde; tras un golpe se recupera poco a poco.
	local targetSpeed = Config.ForwardSpeed
	if Config.MomentumEnabled then
		local dive = math.max(0, -state.verticalSpeed) / Config.MaxFallSpeed
		local climb = math.max(0, state.verticalSpeed) / Config.MaxClimbSpeed
		targetSpeed *= 1 + dive * Config.MomentumDive - climb * Config.MomentumClimb
	end
	state.speed = GliderMath.approach(state.speed, targetSpeed, Config.SpeedResponse, dt)

	state.push = state.push * math.exp(-Config.ContactPushDecay * dt)
end

function GliderPhysics.velocity(state: State): Vector3
	return forwardOf(state.yaw) * state.speed + Vector3.new(0, state.verticalSpeed, 0) + state.push
end

-- Orientación del ala (rumbo, pitch y alabeo) en la posición dada.
function GliderPhysics.cframe(state: State, position: Vector3): CFrame
	return CFrame.new(position) * CFrame.Angles(0, state.yaw, 0) * CFrame.Angles(math.rad(state.pitch), 0, 0) * CFrame.Angles(0, 0, math.rad(state.roll))
end

-- ── Contactos ─────────────────────────────────────────────────────────

-- El ala resbala a lo largo de la superficie de normal `normal`: se quita la parte de la velocidad que entra en
-- ella, el rumbo se va alineando con la superficie y queda un empujón de separación. De frente contra una pared
-- casi se para (y recupera velocidad al apartarse). Devuelve con qué velocidad entraba (studs/s).
function GliderPhysics.contact(state: State, normal: Vector3): number
	local forward = forwardOf(state.yaw)
	local v = forward * state.speed + Vector3.new(0, state.verticalSpeed, 0)
	local into = -v:Dot(normal)
	if into <= 0 then
		return 0
	end
	local slid = v + normal * into
	state.verticalSpeed = slid.Y
	local horizontal = Vector3.new(slid.X, 0, slid.Z)
	local along = horizontal:Dot(forward)
	if along > 1 and horizontal.Magnitude > 1 then
		local slideYaw = GliderMath.yawOf(horizontal.Unit)
		state.yaw += unwrap(slideYaw - state.yaw) * Config.ContactSteer
	end
	state.speed = math.max(along, 0)
	state.push = normal * Config.ContactPush
	state.turnRate *= 0.5
	return into
end

-- Daño de un contacto: golpe fuerte (−1 corazón, invulnerable un rato) o roce (acumula; al llegar a
-- ScrapeDamageTime quita un corazón). Invulnerable o suelo = sin daño. Sin corazones = "crash".
function GliderPhysics.hurt(health: Health, into: number, dt: number, now: number, harmless: boolean): Event?
	health.lastContact = now
	if harmless or now < health.invulnerableUntil or into <= 0 then
		return if into > 0 then "scrape" else nil
	end
	local damage = false
	if into >= Config.ImpactSpeed then
		damage = true
	else
		health.scrapeTime += dt
		if health.scrapeTime >= Config.ScrapeDamageTime then
			damage = true
		end
	end
	if not damage then
		return "scrape"
	end
	health.scrapeTime = 0
	health.hearts -= 1
	health.invulnerableUntil = now + Config.InvulnerableTime
	return if health.hearts <= 0 then "crash" else "impact"
end

-- Sin contacto: el roce acumulado se va olvidando.
function GliderPhysics.calm(health: Health, dt: number, now: number)
	if now - health.lastContact > 0.5 then
		health.scrapeTime = math.max(0, health.scrapeTime - dt)
	end
end

-- ── Percepción del entorno ───────────────────────────────────────────

local function isCeiling(result: RaycastResult): boolean
	return result.Normal.Y < -0.5
end

-- Suelos y tops: tocarlos nunca quita corazones (se resbala por encima).
local function isHarmless(result: RaycastResult): boolean
	local kind = result.Instance:GetAttribute("Kind")
	return kind == "Ground" or kind == "Grass" or result.Normal.Y > Config.HarmlessNormalY
end

-- Techo: máxima velocidad vertical (math.huge sin techo cerca). Frena la subida al acercarse; si ya roza, empuja
-- apenas hacia abajo. Se roza, nunca es choque.
function GliderPhysics.ceilingLimit(state: State, position: Vector3, dims: Dimensions, params: RaycastParams): number
	local rollRadians = math.rad(math.abs(state.roll))
	local topExtent = dims.wingTop * math.cos(rollRadians) + dims.span / 2 * math.sin(rollRadians)
	local up = workspace:Raycast(position, Vector3.new(0, topExtent + Config.CeilingProbeDistance, 0), params)
	if up and isCeiling(up) then
		return (up.Position.Y - (position.Y + topExtent) - Config.CeilingClearance) * Config.CeilingStiffness
	end
	return math.huge
end

-- Techo (tope de subida), cojín del suelo (tope de bajada) y contacto de frente o de lado.
-- landing = recorrido terminado: cualquier superficie de debajo cuenta como suelo para aterrizar.
function GliderPhysics.sense(state: State, position: Vector3, velocity: Vector3, dims: Dimensions, dt: number, params: RaycastParams, landing: boolean?): Sense
	local sense: Sense = { maxVertical = math.huge, minVertical = -math.huge, floorGap = nil, contact = nil, harmless = false }
	sense.maxVertical = GliderPhysics.ceilingLimit(state, position, dims, params)

	-- Suelo (cualquier superficie que mire hacia arriba): cojín que levanta el ala. Al final del recorrido es
	-- la superficie de aterrizaje.
	local reach = Config.FeetBelowRoot + Config.FloorCushion
	local down = workspace:Raycast(position, Vector3.new(0, -reach, 0), params)
	if down and down.Normal.Y > 0.6 then
		local gap = (position.Y - down.Position.Y) - Config.FeetBelowRoot
		sense.floorGap = gap
		if not landing then
			sense.minVertical = (Config.FloorCushion - gap) * Config.FloorCushionStiffness
		end
	end

	-- Contacto de frente: barrido del núcleo del ala (más pequeño que el modelo: perdona los roces de las puntas).
	local core = Vector3.new(dims.span * Config.HitboxSpanFactor, dims.wingTop + Config.FeetBelowRoot * Config.HitboxFeetFactor, 2)
	local center = GliderPhysics.cframe(state, position) * CFrame.new(0, (dims.wingTop - Config.FeetBelowRoot * Config.HitboxFeetFactor) / 2, 0)
	local speed = velocity.Magnitude
	if speed > 1e-3 then
		local hit = workspace:Blockcast(center, core, velocity.Unit * (speed * dt + Config.ObstacleProbeDistance), params)
		if hit and not isCeiling(hit) then
			sense.contact = hit
			sense.harmless = isHarmless(hit)
			return sense
		end
	end

	-- De lado (el barrido no ve lo que ya roza al girar): rayos desde el centro hacia cada punta.
	local frame = CFrame.Angles(0, state.yaw, 0)
	for _, side in { -1, 1 } do
		local direction = frame.RightVector * side * (core.X / 2 + 1)
		local hit = workspace:Raycast(position, direction, params)
		if hit and not isCeiling(hit) then
			sense.contact = hit
			sense.harmless = isHarmless(hit)
			return sense
		end
	end
	return sense
end

-- Un paso completo: percibir, volar, resolver contactos y daño. Devuelve la velocidad a aplicar y lo ocurrido.
-- options.now = reloj (s) · assistTurn · landing · windVertical (viento de la sesión, studs/s).
function GliderPhysics.fly(state: State, health: Health, liftInput: number, balanceInput: number, position: Vector3, dims: Dimensions, dt: number, params: RaycastParams, options: { now: number, assistTurn: number?, landing: boolean?, windVertical: number? }): FlyResult
	local sense = GliderPhysics.sense(state, position, GliderPhysics.velocity(state), dims, dt, params, options.landing)
	local result: FlyResult = { velocity = Vector3.zero, event = nil, contact = nil, landed = false, skimming = false }
	if options.landing and sense.floorGap and sense.floorGap <= Config.GroundClearance then
		result.landed = true
		return result
	end
	GliderPhysics.step(state, liftInput, balanceInput, dt, sense.maxVertical, sense.minVertical, options.assistTurn or 0)
	if sense.contact then
		local into = GliderPhysics.contact(state, sense.contact.Normal)
		result.event = GliderPhysics.hurt(health, into, dt, options.now, sense.harmless)
		result.contact = sense.contact
	else
		GliderPhysics.calm(health, dt, options.now)
	end
	result.skimming = sense.floorGap ~= nil and sense.floorGap < Config.SkimGap
	-- El viento (y la asistencia de altura) se suman sin pasar los topes del techo y del cojín.
	local vertical = math.clamp(state.verticalSpeed + (options.windVertical or 0), math.min(sense.minVertical, sense.maxVertical), sense.maxVertical)
	result.velocity = forwardOf(state.yaw) * state.speed + Vector3.new(0, vertical, 0) + state.push
	return result
end

return GliderPhysics
