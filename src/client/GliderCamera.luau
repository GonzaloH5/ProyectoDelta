--!strict
-- Cámara detrás del ala mirando hacia adelante, pensada para LEER el recorrido:
--   · sigue el rumbo y la altura con suavizado y copia solo una fracción pequeña del alabeo;
--   · anticipa: mira un poco hacia la línea ideal que viene (atributo RouteAhead que publica el servidor) y
--     adelanta el punto de mira al subir o bajar, así se ve antes la curva o el hueco;
--   · nunca atraviesa paredes ni techos: si algo se interpone entre el ala y la cámara, se acerca;
--   · FOV arcade con tope (se abre al picar, se cierra un poco al subir);
--   · temblor corto al perder un corazón y suave mientras roza (Impacts / Scraping).
-- Con "reducir movimiento" (Settings) no hay alabeo, cambios de FOV ni temblores.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Glider.GliderConfig)
local GliderMath = require(ReplicatedStorage.Glider.GliderMath)
local Settings = require(script.Parent:WaitForChild("Settings"))

local GliderCamera = {}

local active = false
local yaw = 0
local height = 0
local roll = 0
local lead = 0 -- adelanto vertical del punto de mira (suavizado)
local distanceScale = 1 -- < 1 cuando algo tapa la cámara
local tracked = Vector3.zero -- posición del ala predicha localmente (sin tirones de red)
local savedFieldOfView = 70
local shake = 0
local shakeClock = 0
local lastImpacts = 0
local occlusion = RaycastParams.new()
occlusion.FilterType = Enum.RaycastFilterType.Exclude
local occlusionRefresh = 0

local function unwrapAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

local function headingOf(root: BasePart): number
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	return if look.Magnitude > 1e-3 then GliderMath.yawOf(look.Unit) else yaw
end

-- La cámara no choca con alas ni personajes (de nadie), solo con el mapa.
local function refreshOcclusion()
	local ignore: { Instance } = {}
	local gliders = workspace:FindFirstChild(Config.GliderFolderName)
	if gliders then
		table.insert(ignore, gliders)
	end
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	occlusion.FilterDescendantsInstances = ignore
end

function GliderCamera.start(root: BasePart)
	local camera = workspace.CurrentCamera
	active = true
	yaw = headingOf(root)
	height = root.Position.Y
	roll = 0
	lead = 0
	distanceScale = 1
	shake = 0
	tracked = root.Position
	local glider = root.Parent
	local impacts = glider and glider:GetAttribute("Impacts")
	lastImpacts = if type(impacts) == "number" then impacts else 0
	savedFieldOfView = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = Config.CameraFieldOfView
	refreshOcclusion()
end

-- Temblor extra desde fuera (p. ej. efectos): amplitud en studs.
function GliderCamera.kick(amount: number)
	shake = math.max(shake, amount)
end

function GliderCamera.update(root: BasePart, dt: number)
	if not active then
		return
	end
	local settings = Settings.get()
	local calm = settings.reduceMotion
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable -- nada puede devolverle el control al ratón
	local glider = root.Parent

	-- La posición del ala llega por red a saltos. La cámara sigue una posición predicha
	-- con la velocidad del ala y corregida suavemente hacia la real: movimiento continuo.
	tracked += root.AssemblyLinearVelocity * dt
	if (tracked - root.Position).Magnitude > Config.CameraSnapDistance then
		tracked = root.Position -- reaparición / teletransporte: saltar directamente
		yaw = headingOf(root)
		height = root.Position.Y
		distanceScale = 1
	else
		tracked = tracked:Lerp(root.Position, 1 - math.exp(-Config.CameraTrackCorrection * dt))
	end

	-- Rumbo: el del ala más un poco hacia la línea ideal que viene (anticipa las curvas).
	local heading = headingOf(root)
	local target = heading
	local routeAhead = glider and glider:GetAttribute("RouteAhead")
	if typeof(routeAhead) == "Vector3" then
		local toRoute = (routeAhead - tracked) * Vector3.new(1, 0, 1)
		if toRoute.Magnitude > 20 then
			local bias = unwrapAngle(GliderMath.yawOf(toRoute.Unit) - heading) * Config.CameraRouteBlend
			local limit = math.rad(Config.CameraRouteMaxAngle)
			target = heading + math.clamp(bias, -limit, limit)
		end
	end
	yaw += unwrapAngle(target - yaw) * (1 - math.exp(-Config.CameraSmoothness * dt))
	height = GliderMath.approach(height, tracked.Y, Config.CameraVerticalSmoothness, dt)

	-- Alabeo del ala ≈ asin(RightVector.Y); la cámara copia solo una fracción (nada con reducir movimiento).
	local wingRoll = math.asin(math.clamp(root.CFrame.RightVector.Y, -1, 1))
	local maxRoll = math.rad(Config.CameraMaxRoll)
	local targetRoll = if calm then 0 else math.clamp(wingRoll * Config.CameraRollFactor, -maxRoll, maxRoll)
	roll = GliderMath.approach(roll, targetRoll, Config.CameraRollResponse, dt)

	-- Adelanto vertical: al subir o bajar, el punto de mira va por delante (se ve antes el hueco).
	local verticalSpeed = root.AssemblyLinearVelocity.Y
	lead = GliderMath.approach(lead, verticalSpeed * Config.CameraVerticalLead, 3, dt)

	local forward = CFrame.Angles(0, yaw, 0).LookVector
	local focus = Vector3.new(tracked.X, height - Config.CameraFocusDrop, tracked.Z)
	local wanted = focus - forward * Config.CameraDistance + Vector3.new(0, Config.CameraHeight, 0)
	local lookAt = focus + forward * Config.CameraLookAhead + Vector3.new(0, lead, 0)

	-- Paredes y techos: si algo se interpone entre el ala y la cámara, se acerca (rápido) y luego vuelve (lento).
	occlusionRefresh -= dt
	if occlusionRefresh <= 0 then
		occlusionRefresh = 1
		refreshOcclusion()
	end
	local offset = wanted - focus
	local hit = workspace:Raycast(focus, offset, occlusion)
	local allowed = 1
	if hit then
		allowed = math.clamp(((hit.Position - focus).Magnitude - Config.CameraCollisionRadius) / offset.Magnitude, 0.15, 1)
	end
	local response = if allowed < distanceScale then Config.CameraPullInResponse else Config.CameraReleaseResponse
	distanceScale = GliderMath.approach(distanceScale, allowed, response, dt)
	distanceScale = math.min(distanceScale, allowed + 0.05) -- nunca por detrás de la pared, ni un fotograma
	local position = focus + offset * distanceScale

	-- Temblor: golpe (pierde un corazón) y roce continuo.
	local impacts = glider and glider:GetAttribute("Impacts")
	if type(impacts) == "number" and impacts > lastImpacts then
		shake = math.max(shake, Config.CameraShakeImpact)
	end
	lastImpacts = if type(impacts) == "number" then impacts else lastImpacts
	if glider and glider:GetAttribute("Scraping") == true then
		shake = math.max(shake, Config.CameraShakeScrape)
	end
	shake = GliderMath.approach(shake, 0, Config.CameraShakeDecay, dt)
	shakeClock += dt
	local jitter = Vector3.zero
	if shake > 0.01 and settings.cameraShake and not calm then
		jitter = Vector3.new(GliderMath.flow(shakeClock * 18, 3.1), GliderMath.flow(shakeClock * 18, 7.7), 0) * shake
	end

	camera.CFrame = CFrame.lookAt(position, lookAt) * CFrame.new(jitter) * CFrame.Angles(0, 0, roll)

	-- FOV arcade con tope: se abre al caer en picado y se cierra un poco al subir.
	local targetFov = Config.CameraFieldOfView
	if not calm then
		local boost = math.min(math.max(0, -verticalSpeed) * Config.CameraDiveFovBoost, Config.CameraMaxFovBoost)
		local drop = math.min(math.max(0, verticalSpeed) * Config.CameraClimbFovDrop, Config.CameraMaxFovDrop)
		targetFov += boost - drop
	end
	camera.FieldOfView = GliderMath.approach(camera.FieldOfView, targetFov, Config.CameraFovResponse, dt)
end

function GliderCamera.stop()
	if not active then
		return
	end
	active = false
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = savedFieldOfView
end

return GliderCamera
