--!strict
-- Cuelga un personaje de la barra (Weld + Massless + sin colisiones + IK de ambas manos)
-- y lo restaura al soltarlo. No sabe nada del vuelo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Glider.GliderConfig)
local CollisionGroups = require(script.Parent.CollisionGroups)

local RIDER_GROUP = CollisionGroups.Riders

export type Rig = {
	character: Model,
	humanoid: Humanoid,
	rootPart: BasePart,
	weld: Weld,
	side: number, -- -1 izquierda, +1 derecha
	savedParts: { [BasePart]: { massless: boolean, group: string } },
	created: { Instance },
}

local RiderRig = {}

local function hangRotation(): CFrame
	-- Ángulo negativo sobre X = torso inclinado hacia adelante (manos por delante del pecho).
	return CFrame.Angles(math.rad(-Config.HangLean), 0, 0)
end

-- CFrame del HumanoidRootPart en el espacio del Root del ala para un desplazamiento lateral.
function RiderRig.offsetFor(lateral: number): CFrame
	return CFrame.new(lateral, -Config.HangDepth, Config.HangBack) * hangRotation()
end

-- Posición de cada mano relativa al HumanoidRootPart. Es constante porque el cuerpo
-- se desliza junto con sus manos: siempre caen sobre la barra.
local function gripOffset(handSide: number): CFrame
	return hangRotation():Inverse() * CFrame.new(handSide * Config.HandSpacing, Config.HangDepth, -Config.HangBack)
end

local function makeArmIK(rig: Rig, humanoid: Humanoid, prefix: string, handSide: number)
	local character = rig.character
	local upperArm = character:FindFirstChild(prefix .. "UpperArm")
	local hand = character:FindFirstChild(prefix .. "Hand")
	if not (upperArm and hand) then
		return -- R6 u otro rig: el cuerpo queda colgado igualmente, sin IK
	end

	local target = Instance.new("Attachment")
	target.Name = "GliderGrip" .. prefix
	target.CFrame = gripOffset(handSide)
	target.Parent = rig.rootPart

	-- Polo detrás y hacia afuera para que los codos se abran de forma natural.
	local pole = Instance.new("Attachment")
	pole.Name = "GliderPole" .. prefix
	pole.CFrame = CFrame.new(handSide * 2, 1.2, 1.5)
	pole.Parent = rig.rootPart

	local grip = hand:FindFirstChild(prefix .. "GripAttachment")

	local ik = Instance.new("IKControl")
	ik.Name = "GliderIK" .. prefix
	ik.Type = Enum.IKControlType.Position
	ik.ChainRoot = upperArm
	ik.EndEffector = if grip then grip else hand
	ik.Target = target
	ik.Pole = pole
	ik.Weight = 1
	ik.SmoothTime = 0.05
	ik.Parent = humanoid

	table.insert(rig.created, target)
	table.insert(rig.created, pole)
	table.insert(rig.created, ik)
end

function RiderRig.attach(character: Model, gliderRoot: BasePart, side: number, lateral: number): Rig?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and rootPart and rootPart:IsA("BasePart")) or humanoid.Health <= 0 then
		return nil
	end

	local rig: Rig = {
		character = character,
		humanoid = humanoid,
		rootPart = rootPart,
		weld = Instance.new("Weld"),
		side = side,
		savedParts = {},
		created = {},
	}

	-- Sin masa ni colisiones: el cuerpo no puede desestabilizar la simulación del ala.
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			rig.savedParts[part] = { massless = part.Massless, group = part.CollisionGroup }
			part.Massless = true
			part.CollisionGroup = RIDER_GROUP
		end
	end

	humanoid.PlatformStand = true
	humanoid.AutoRotate = false

	rig.weld.Name = "GliderHang"
	rig.weld.Part0 = gliderRoot
	rig.weld.Part1 = rootPart
	rig.weld.C0 = RiderRig.offsetFor(lateral)
	rig.weld.Parent = gliderRoot
	table.insert(rig.created, rig.weld)

	makeArmIK(rig, humanoid, "Left", -1)
	makeArmIK(rig, humanoid, "Right", 1)

	character:SetAttribute("GliderSide", side)
	return rig
end

function RiderRig.setLateral(rig: Rig, lateral: number)
	rig.weld.C0 = RiderRig.offsetFor(lateral)
end

function RiderRig.detach(rig: Rig)
	for _, instance in rig.created do
		instance:Destroy()
	end
	table.clear(rig.created)

	for part, saved in rig.savedParts do
		if part.Parent then
			part.Massless = saved.massless
			part.CollisionGroup = saved.group
		end
	end

	if rig.humanoid.Parent then
		rig.humanoid.PlatformStand = false
		rig.humanoid.AutoRotate = true
	end
	rig.character:SetAttribute("GliderSide", nil)
end

return RiderRig
