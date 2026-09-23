--!strict
-- Las alas y los jugadores de OTROS dúos se ven ligeramente transparentes, solo en este cliente
-- (LocalTransparencyModifier no se replica). Tu ala y tu compañero siempre se ven normales.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Glider.GliderConfig)

local OtherDuos = {}

local REFRESH_INTERVAL = 0.25
local timer = REFRESH_INTERVAL
local faded: { [Instance]: true } = {}

local function fade(instance: Instance, into: { [Instance]: true })
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			(descendant :: any).LocalTransparencyModifier = Config.OtherDuoTransparency
			into[descendant] = true
		end
	end
end

local function fadeRider(glider: Model, attribute: string, into: { [Instance]: true })
	local userId = glider:GetAttribute(attribute)
	if type(userId) ~= "number" or userId == 0 then
		return
	end
	local rider = Players:GetPlayerByUserId(userId)
	if rider and rider.Character then
		fade(rider.Character, into)
	end
end

function OtherDuos.update(folder: Instance, mine: Model?, dt: number)
	timer += dt
	if timer < REFRESH_INTERVAL then
		return
	end
	timer = 0

	local now: { [Instance]: true } = {}
	for _, glider in folder:GetChildren() do
		if glider:IsA("Model") and glider ~= mine then
			fade(glider, now)
			fadeRider(glider, "LeftUserId", now)
			fadeRider(glider, "RightUserId", now)
		end
	end

	-- Lo que dejó de pertenecer a otro dúo (aterrizó, o ahora es de mi dúo) vuelve a verse normal.
	for instance in faded do
		if not now[instance] and instance.Parent then
			(instance :: any).LocalTransparencyModifier = 0
		end
	end
	faded = now
end

return OtherDuos
