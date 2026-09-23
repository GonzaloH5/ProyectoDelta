--!strict
-- Cliente del ala delta: encuentra el ala de su dúo, lee el eje (teclado, mando o táctil: InputAxis),
-- lo envía al servidor, controla la cámara y el HUD. Nunca mueve el ala ni el cuerpo: eso lo decide el servidor.
-- Hay un ala por dúo en Workspace[Config.GliderFolderName]; las de otros dúos se ven
-- semitransparentes (OtherDuos).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Glider")
local Config = require(Shared:WaitForChild("GliderConfig"))
local remote = Shared:WaitForChild("GliderRemote") :: RemoteEvent
local GliderCamera = require(script:WaitForChild("GliderCamera"))
local InputAxis = require(script:WaitForChild("InputAxis"))
local FlightHud = require(script:WaitForChild("FlightHud"))
local ResetButton = require(script:WaitForChild("ResetButton"))
local LobbyButton = require(script:WaitForChild("LobbyButton"))
local CheckpointBanner = require(script:WaitForChild("CheckpointBanner"))
local OtherDuos = require(script:WaitForChild("OtherDuos"))
local Tutorial = require(script:WaitForChild("Tutorial"))

local player = Players.LocalPlayer
Tutorial.show() -- al unirse a la sala
local gliderFolder = workspace:WaitForChild(Config.GliderFolderName)

remote.OnClientEvent:Connect(function(kind: unknown, data: unknown)
	if kind == "Checkpoint" and type(data) == "table" then
		CheckpointBanner.show(data :: any)
	end
end)

-- Controles por defecto (si el place tiene PlayerModule). Si no existe, no hay nada que desactivar.
local controls = nil
task.spawn(function()
	local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 5)
	if module and module:IsA("ModuleScript") then
		local ok, playerModule = pcall(require, module)
		if ok then
			controls = (playerModule :: any):GetControls()
		end
	end
end)

local mountedSide = 0 -- 0 no montado, -1 slot 1, 1 slot 2
local mountedGlider: Model? = nil
local sentAxis = 0

-- El ala de mi dúo (si voy colgado de alguna) y en qué slot.
local function findMyGlider(): (Model?, number)
	for _, glider in gliderFolder:GetChildren() do
		if not glider:IsA("Model") then
			continue
		end
		if glider:GetAttribute("LeftUserId") == player.UserId then
			return glider, -1
		elseif glider:GetAttribute("RightUserId") == player.UserId then
			return glider, 1
		end
	end
	return nil, 0
end

local function setCharacterAnimated(enabled: boolean)
	local character = player.Character
	if not character then
		return
	end
	local animate = character:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		animate.Enabled = enabled
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.PlatformStand = not enabled
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, enabled)
	if not enabled then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in animator:GetPlayingAnimationTracks() do
				track:Stop(0.2) -- cuerpo en reposo: el IK sube las manos a la barra
			end
		end
	end
end

local function mount(glider: Model, root: BasePart, side: number)
	mountedGlider = glider
	mountedSide = side
	if controls then
		controls:Disable()
	end
	setCharacterAnimated(false)
	GliderCamera.start(root)
	InputAxis.setEnabled(true)
	ResetButton.setVisible(true)
	LobbyButton.setVisible(true)
end

local function unmount()
	mountedGlider = nil
	mountedSide = 0
	sentAxis = 0
	if controls then
		controls:Enable()
	end
	setCharacterAnimated(true)
	GliderCamera.stop()
	InputAxis.setEnabled(false)
	ResetButton.setVisible(false)
	LobbyButton.setVisible(false)
end

RunService:BindToRenderStep("GliderClient", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local glider, side = findMyGlider()
	local root = glider and glider:FindFirstChild("Root")
	if not (root and root:IsA("BasePart")) then
		glider, side, root = nil, 0, nil
	end

	if glider ~= mountedGlider or side ~= mountedSide then
		if mountedGlider then
			unmount()
		end
		if glider and root then
			mount(glider, root :: BasePart, side)
		end
	end

	if mountedGlider and root then
		local axis = InputAxis.read()
		if axis ~= sentAxis then
			sentAxis = axis
			remote:FireServer("Axis", axis)
		end
		GliderCamera.update(root :: BasePart, dt)
	end

	FlightHud.update(mountedGlider, mountedSide, dt)
	OtherDuos.update(gliderFolder, mountedGlider, dt)
end)

player.CharacterRemoving:Connect(function()
	if mountedSide ~= 0 then
		unmount()
	end
end)
