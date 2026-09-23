--!strict
-- Cámara fija detrás del ala mirando siempre hacia adelante.
-- Sigue el rumbo y la altura con suavizado, y copia solo una fracción pequeña del alabeo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Glider.GliderConfig)
local GliderMath = require(ReplicatedStorage.Glider.GliderMath)

local GliderCamera = {}

local active = false
local yaw = 0
local height = 0
local roll = 0
local tracked = Vector3.zero -- posición del ala predicha localmente (sin tirones de red)
local savedFieldOfView = 70

local function unwrapAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

local function headingOf(root: BasePart): number
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	return if look.Magnitude > 1e-3 then GliderMath.yawOf(look.Unit) else yaw
end

function GliderCamera.start(root: BasePart)
	local camera = workspace.CurrentCamera
	active = true
	yaw = headingOf(root)
	height = root.Position.Y
	roll = 0
	tracked = root.Position
	savedFieldOfView = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = Config.CameraFieldOfView
end

function GliderCamera.update(root: BasePart, dt: number)
	if not active then
		return
	end
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable -- nada puede devolverle el control al ratón

	-- La posición del ala llega por red a saltos. La cámara sigue una posición predicha
	-- con la velocidad del ala y corregida suavemente hacia la real: movimiento continuo.
	tracked += root.AssemblyLinearVelocity * dt
	if (tracked - root.Position).Magnitude > Config.CameraSnapDistance then
		tracked = root.Position -- reset / teletransporte: saltar directamente
	else
		tracked = tracked:Lerp(root.Position, 1 - math.exp(-Config.CameraTrackCorrection * dt))
	end

	-- Rumbo suavizado (por el camino corto) y altura con un poco de retraso.
	local delta = unwrapAngle(headingOf(root) - yaw)
	yaw += delta * (1 - math.exp(-Config.CameraSmoothness * dt))
	height = GliderMath.approach(height, tracked.Y, Config.CameraVerticalSmoothness, dt)

	-- Alabeo del ala ≈ asin(RightVector.Y); la cámara copia solo una fracción.
	local wingRoll = math.asin(math.clamp(root.CFrame.RightVector.Y, -1, 1))
	local maxRoll = math.rad(Config.CameraMaxRoll)
	local targetRoll = math.clamp(wingRoll * Config.CameraRollFactor, -maxRoll, maxRoll)
	roll = GliderMath.approach(roll, targetRoll, Config.CameraRollResponse, dt)

	local heading = CFrame.Angles(0, yaw, 0)
	local focus = Vector3.new(tracked.X, height - Config.CameraFocusDrop, tracked.Z)
	local position = focus - heading.LookVector * Config.CameraDistance + Vector3.new(0, Config.CameraHeight, 0)
	local lookAt = focus + heading.LookVector * Config.CameraLookAhead

	camera.CFrame = CFrame.lookAt(position, lookAt) * CFrame.Angles(0, 0, roll)

	-- FOV arcade: se abre al caer en picado y se cierra un poco al subir.
	local verticalSpeed = root.AssemblyLinearVelocity.Y
	local targetFov = Config.CameraFieldOfView
		+ math.max(0, -verticalSpeed) * Config.CameraDiveFovBoost
		- math.max(0, verticalSpeed) * Config.CameraClimbFovDrop
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
