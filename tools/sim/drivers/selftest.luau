-- Pruebas de la imitación de Roblox: matemática de CFrame y consultas físicas.
local failures = 0
local function check(name, ok, detail)
	if not ok then
		failures += 1
		print("FALLA", name, detail or "")
	end
end
local function near(a, b, eps)
	eps = eps or 1e-6
	if typeof(a) == "Vector3" then
		return (a - b).Magnitude <= eps
	end
	return math.abs(a - b) <= eps
end

-- Convenciones de Roblox
check("Angles yaw +90 gira -Z hacia -X", near(CFrame.Angles(0, math.rad(90), 0) * Vector3.new(0, 0, -1), Vector3.new(-1, 0, 0)))
check("Angles pitch +90 gira -Z hacia +Y", near(CFrame.Angles(math.rad(90), 0, 0) * Vector3.new(0, 0, -1), Vector3.new(0, 1, 0)))
check("Angles roll +90 gira +X hacia +Y", near(CFrame.Angles(0, 0, math.rad(90)) * Vector3.new(1, 0, 0), Vector3.new(0, 1, 0)))
local a = CFrame.Angles(0.3, 0.2, 0.1)
local b = CFrame.Angles(0.3, 0, 0) * CFrame.Angles(0, 0.2, 0) * CFrame.Angles(0, 0, 0.1)
check("Angles = Rx·Ry·Rz", near(a * Vector3.new(1, 2, 3), b * Vector3.new(1, 2, 3)))
local look = CFrame.lookAt(Vector3.new(1, 2, 3), Vector3.new(5, 2, 0))
check("lookAt LookVector", near(look.LookVector, (Vector3.new(4, 0, -3)).Unit))
check("lookAt UpVector vertical", near(look.UpVector, Vector3.yAxis))
check("lookAt RightVector", near(look.RightVector, look.LookVector:Cross(Vector3.yAxis).Unit))
local c = CFrame.new(10, 20, 30) * CFrame.Angles(0.4, -1.1, 0.7)
check("inverse", near((c:Inverse() * c) * Vector3.new(3, -2, 5), Vector3.new(3, -2, 5)))
check("PointToObjectSpace", near(c:PointToObjectSpace(c * Vector3.new(1, 2, 3)), Vector3.new(1, 2, 3)))
check("Rotation sin posición", near(c.Rotation.Position, Vector3.zero))
check("cf + v", near((c + Vector3.new(1, 1, 1)).Position, Vector3.new(11, 21, 31)))
local rx, ry, rz = CFrame.Angles(0.4, -0.3, 0.7):ToEulerAnglesXYZ()
check("ToEulerAnglesXYZ", near(rx, 0.4) and near(ry, -0.3) and near(rz, 0.7), string.format("%g %g %g", rx, ry, rz))
check("fromMatrix", near(CFrame.fromMatrix(Vector3.zero, Vector3.zAxis, Vector3.xAxis).UpVector, Vector3.xAxis))

-- Física
local folder = Instance.new("Folder")
folder.Parent = workspace
local floor = Instance.new("Part")
floor.Size = Vector3.new(100, 2, 100)
floor.CFrame = CFrame.new(0, -1, 0)
floor.Parent = folder
local hit = workspace:Raycast(Vector3.new(0, 10, 0), Vector3.new(0, -20, 0))
check("rayo al suelo", hit and hit.Instance == floor and near(hit.Position.Y, 0) and near(hit.Normal, Vector3.yAxis))
check("rayo corto no llega", workspace:Raycast(Vector3.new(0, 10, 0), Vector3.new(0, -5, 0)) == nil)
check("rayo desde dentro no detecta", workspace:Raycast(Vector3.new(0, -1, 0), Vector3.new(0, -5, 0)) == nil)

local wedge = Instance.new("WedgePart")
wedge.Size = Vector3.new(10, 10, 10)
wedge.CFrame = CFrame.new(0, 5, 50)
wedge.Parent = folder
-- Sube hacia +Z: en z local = 0 la pendiente está a y local = 0 (mundo 5); en z = +5 arriba del todo.
local w = workspace:Raycast(Vector3.new(0, 30, 50), Vector3.new(0, -40, 0))
check("rayo a la pendiente de la cuña", w and w.Instance == wedge and near(w.Position.Y, 5, 1e-4) and near(w.Normal, Vector3.new(0, 1, -1).Unit, 1e-4), w and tostring(w.Position) .. " n " .. tostring(w.Normal))
local w2 = workspace:Raycast(Vector3.new(0, 30, 54), Vector3.new(0, -40, 0))
check("cuña más alta hacia +Z", w2 and near(w2.Position.Y, 9, 1e-4), w2 and tostring(w2.Position))
local w3 = workspace:Raycast(Vector3.new(0, 8, 40), Vector3.new(0, 0, 20))
check("rayo horizontal por encima de la parte baja", w3 and w3.Instance == wedge and near(w3.Position.Z, 53, 1e-4), w3 and tostring(w3.Position))

local ball = Instance.new("Part")
ball.Shape = Enum.PartType.Ball
ball.Size = Vector3.new(6, 6, 6)
ball.CFrame = CFrame.new(-40, 3, 0)
ball.Parent = folder
local bh = workspace:Raycast(Vector3.new(-40, 20, 0), Vector3.new(0, -30, 0))
check("rayo a la bola", bh and bh.Instance == ball and near(bh.Position.Y, 6, 1e-6))

local params = RaycastParams.new()
params.FilterDescendantsInstances = { ball }
local bh2 = workspace:Raycast(Vector3.new(-40, 20, 0), Vector3.new(0, -30, 0), params)
check("Exclude salta la bola", bh2 and bh2.Instance == floor)
params.FilterType = Enum.RaycastFilterType.Include
local bh3 = workspace:Raycast(Vector3.new(0, 10, 0), Vector3.new(0, -20, 0), params)
check("Include solo la bola", bh3 == nil)

-- Blockcast contra una pared: normal hacia la caja
local wall = Instance.new("Part")
wall.Size = Vector3.new(2, 20, 20)
wall.CFrame = CFrame.new(30, 10, -30)
wall.Parent = folder
local bc = workspace:Blockcast(CFrame.new(20, 10, -30), Vector3.new(4, 4, 4), Vector3.new(10, 0, 0))
check("blockcast pared", bc and bc.Instance == wall and near(bc.Normal, Vector3.new(-1, 0, 0)) and near(bc.Distance, 7, 1e-6), bc and tostring(bc.Normal) .. " d " .. bc.Distance)
check("blockcast corto no llega", workspace:Blockcast(CFrame.new(20, 10, -30), Vector3.new(4, 4, 4), Vector3.new(5, 0, 0)) == nil)
check("blockcast que ya toca: ignora", workspace:Blockcast(CFrame.new(28.5, 10, -30), Vector3.new(4, 4, 4), Vector3.new(5, 0, 0)) == nil)
local rot = workspace:Blockcast(CFrame.new(20, 10, -30) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(4, 4, 4), Vector3.new(10, 0, 0))
check("blockcast girada 45°", rot and near(rot.Distance, 9 - 2 * math.sqrt(2), 1e-6), rot and rot.Distance)
-- Techo: la caja sube contra una losa → normal hacia abajo
local ceiling = Instance.new("Part")
ceiling.Size = Vector3.new(40, 2, 40)
ceiling.CFrame = CFrame.new(0, 60, -100)
ceiling.Parent = folder
local up = workspace:Blockcast(CFrame.new(0, 55, -100), Vector3.new(4, 4, 4), Vector3.new(1, 5, 0))
check("blockcast techo normal abajo", up and near(up.Normal, Vector3.new(0, -1, 0)), up and tostring(up.Normal))
-- Blockcast contra la pendiente de una cuña
local ramp = Instance.new("WedgePart")
ramp.Size = Vector3.new(20, 10, 20)
ramp.CFrame = CFrame.new(0, 5, -200) * CFrame.Angles(0, math.pi, 0) -- sube hacia -Z del mundo
ramp.Parent = folder
local rh = workspace:Blockcast(CFrame.new(0, 4, -180), Vector3.new(4, 2, 2), Vector3.new(0, 0, -30))
check("blockcast cuña: normal de la pendiente", rh and rh.Instance == ramp and near(rh.Normal, Vector3.new(0, 2, 1).Unit, 1e-4), rh and tostring(rh.Normal))

-- GetPartsInPart
local probe = Instance.new("Part")
probe.CanQuery = false
probe.Size = Vector3.new(4, 4, 4)
probe.CFrame = CFrame.new(27.5, 10, -30)
probe.Parent = workspace
local list = workspace:GetPartsInPart(probe)
check("overlap pared", #list == 1 and list[1] == wall)
probe.CFrame = CFrame.new(26, 10, -30)
check("overlap separado", #workspace:GetPartsInPart(probe) == 0)
probe.CFrame = CFrame.new(0, 9.5, 54)
check("overlap cuña parte alta", #workspace:GetPartsInPart(probe) == 1)
probe.CFrame = CFrame.new(0, 9.5, 46.5)
check("overlap aire sobre la pendiente", #workspace:GetPartsInPart(probe) == 0)
probe.CFrame = CFrame.new(-40, 7.5, 0)
check("overlap bola", #workspace:GetPartsInPart(probe) == 1)
probe.CFrame = CFrame.new(-40, 9.5, 3.5) * CFrame.Angles(0, 0.3, 0)
check("overlap junto a bola", #workspace:GetPartsInPart(probe) == 0)

-- Instancias
check("GetFullName", wall:GetFullName() == "Workspace.Folder.Part", wall:GetFullName())
folder.Name = "Map"
check("acceso por nombre", workspace.Map == folder)
check("IsA", wedge:IsA("BasePart") and not folder:IsA("BasePart") and workspace:IsA("Model"))
check("typeof", typeof(Enum.PartType.Ball) == "EnumItem" and typeof(CFrame.identity) == "CFrame" and typeof(wall) == "Instance")
check("Position derivada", near(wall.Position, Vector3.new(30, 10, -30)))
local rng = Random.new(42)
local sum = 0
for _ = 1, 1000 do
	sum += rng:NextNumber()
end
check("Random media", math.abs(sum / 1000 - 0.5) < 0.05, sum / 1000)

print(if failures == 0 then "selftest OK" else string.format("selftest: %d fallos", failures))
