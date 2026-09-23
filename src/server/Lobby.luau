--!strict
-- Plataformas de dúo del lobby. Dos jugadores de pie sobre la misma plataforma forman un dúo;
-- tras una cuenta atrás, el lobby avisa con onDuoReady(players) y el controlador crea su ala.
-- Las plataformas son Parts llamadas Config.DuoPadName dentro de Workspace[Config.LobbyFolderName].

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Glider.GliderConfig)

type Pad = {
	part: BasePart,
	label: TextLabel,
	occupants: { Player },
	timer: number,
}

local Lobby = {}

local pads: { Pad } = {}
local isBusy: (Player) -> boolean = function()
	return false
end
local onDuoReady: ({ Player }) -> () = function() end

local function makeLabel(part: BasePart): TextLabel
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DuoStatus"
	billboard.Size = UDim2.fromOffset(220, 60)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 150
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Parent = billboard
	return label
end

-- Jugadores vivos, libres, con los pies sobre la plataforma.
local function playersOn(part: BasePart): { Player }
	local found = {}
	for _, player in Players:GetPlayers() do
		if isBusy(player) then
			continue
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not (humanoid and rootPart and rootPart:IsA("BasePart")) or humanoid.Health <= 0 then
			continue
		end
		local localPosition = part.CFrame:PointToObjectSpace(rootPart.Position)
		local half = part.Size / 2
		local above = localPosition.Y - half.Y
		if math.abs(localPosition.X) <= half.X and math.abs(localPosition.Z) <= half.Z
			and above >= 0 and above <= Config.PadDetectHeight
		then
			table.insert(found, player)
		end
	end
	return found
end

local function sameGroup(a: { Player }, b: { Player }): boolean
	if #a ~= #b then
		return false
	end
	for _, player in a do
		if not table.find(b, player) then
			return false
		end
	end
	return true
end

function Lobby.start(options: { isBusy: (Player) -> boolean, onDuoReady: ({ Player }) -> () })
	isBusy = options.isBusy
	onDuoReady = options.onDuoReady

	local folder = workspace:FindFirstChild(Config.LobbyFolderName)
	if not folder then
		warn(`[Glider] No hay carpeta Workspace.{Config.LobbyFolderName}: no habrá plataformas de dúo`)
		return
	end
	for _, part in folder:GetDescendants() do
		if part:IsA("BasePart") and part.Name == Config.DuoPadName then
			table.insert(pads, { part = part, label = makeLabel(part), occupants = {}, timer = 0 })
		end
	end
end

function Lobby.step(dt: number)
	local required = if Config.RequireBothPlayers then 2 else 1
	for _, pad in pads do
		local on = playersOn(pad.part)
		-- Solo los dos primeros forman el dúo; si la composición cambia, la cuenta vuelve a empezar.
		local duo = { on[1], on[2] }
		if not sameGroup(duo, pad.occupants) then
			pad.occupants = duo
			pad.timer = 0
		end

		local count = #pad.occupants
		if count >= required then
			pad.timer += dt
			local remaining = Config.PadCountdown - pad.timer
			if remaining <= 0 then
				local duoPlayers = table.clone(pad.occupants)
				pad.occupants = {}
				pad.timer = 0
				pad.label.Text = ""
				onDuoReady(duoPlayers)
			else
				pad.label.Text = string.format("Duo ready! Takeoff in %d", math.ceil(remaining))
			end
		else
			pad.timer = 0
			pad.label.Text = string.format("Duo %d/2 · Both step on", count)
		end
	end
end

return Lobby
