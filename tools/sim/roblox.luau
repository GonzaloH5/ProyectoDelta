-- Imitación mínima de Roblox para ejecutar fuera de Studio el código de src/ que no depende del motor
-- (MapBuilder, MapDresser, LowPoly, Biomes, FlightTester…). bundle.py pega este archivo al principio del
-- programa: todo lo que se declara aquí queda visible (como upvalue) para los módulos del juego.
--
-- Incluye: Vector3, CFrame, Color3, UDim2, Enum, Random, instancias con propiedades, atributos e hijos,
-- game/workspace y las consultas físicas que usa el FlightTester (Raycast, Blockcast, GetPartsInPart)
-- sobre formas exactas: bloque, cuña (WedgePart) y bola. Cilindros = bloque (aproximación conservadora).
-- Random no reproduce la secuencia de Roblox: el vestido aleatorio sale distinto que en Studio.

local sqrt, abs, huge, floor, min, max = math.sqrt, math.abs, math.huge, math.floor, math.min, math.max

local rawtypeof = typeof
local function typeof(value: any): string
	if type(value) == "table" then
		local mt = getmetatable(value)
		if type(mt) == "table" and mt.__type then
			return mt.__type
		end
	end
	return rawtypeof(value)
end

local sim = { dirty = true } -- estado compartido con la parte física (y la sal de las semillas)

-- ── Vector3 ───────────────────────────────────────────────────────────

local V3mt = { __type = "Vector3" }
local V3methods = {}
local function v3(x: number, y: number, z: number)
	return setmetatable({ X = x, Y = y, Z = z }, V3mt)
end

function V3methods.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3methods.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3methods.Lerp(a, b, t)
	return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
end
function V3methods.Abs(a)
	return v3(abs(a.X), abs(a.Y), abs(a.Z))
end
function V3methods.Min(a, b)
	return v3(min(a.X, b.X), min(a.Y, b.Y), min(a.Z, b.Z))
end
function V3methods.Max(a, b)
	return v3(max(a.X, b.X), max(a.Y, b.Y), max(a.Z, b.Z))
end
function V3methods.FuzzyEq(a, b, epsilon)
	epsilon = epsilon or 1e-5
	return abs(a.X - b.X) <= epsilon and abs(a.Y - b.Y) <= epsilon and abs(a.Z - b.Z) <= epsilon
end
function V3methods.Angle(a, b)
	local d = V3methods.Dot(a, b) / (sqrt(V3methods.Dot(a, a)) * sqrt(V3methods.Dot(b, b)))
	return math.acos(math.clamp(d, -1, 1))
end

V3mt.__index = function(v, key)
	local method = V3methods[key]
	if method then
		return method
	end
	if key == "Magnitude" then
		return sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif key == "Unit" then
		local m = sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return v3(v.X / m, v.Y / m, v.Z / m)
	elseif key == "x" then
		return v.X
	elseif key == "y" then
		return v.Y
	elseif key == "z" then
		return v.Z
	end
	error("Vector3: miembro desconocido " .. tostring(key), 2)
end
V3mt.__newindex = function()
	error("Vector3 es inmutable", 2)
end
V3mt.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3mt.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3mt.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3mt.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	elseif type(a) == "number" then
		return v3(a / b.X, a / b.Y, a / b.Z)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3mt.__idiv = function(a, b)
	return v3(a.X // b, a.Y // b, a.Z // b)
end
V3mt.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3mt.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3mt.__tostring = function(v)
	return string.format("%g, %g, %g", v.X, v.Y, v.Z)
end

local Vector3 = {
	new = function(x: number?, y: number?, z: number?)
		return v3(x or 0, y or 0, z or 0)
	end,
	zero = v3(0, 0, 0),
	one = v3(1, 1, 1),
	xAxis = v3(1, 0, 0),
	yAxis = v3(0, 1, 0),
	zAxis = v3(0, 0, 1),
}

-- ── CFrame ────────────────────────────────────────────────────────────
-- Array: [1..3] = posición, [4..12] = matriz de rotación por filas (columnas = ejes X, Y, Z locales).

local CFmt = { __type = "CFrame" }
local CFmethods = {}
local function cf(x, y, z, a, b, c, d, e, f, g, h, i)
	return setmetatable({ x, y, z, a, b, c, d, e, f, g, h, i }, CFmt)
end

local function cfMul(A, B)
	local a1, a2, a3, a4, a5, a6, a7, a8, a9 = A[4], A[5], A[6], A[7], A[8], A[9], A[10], A[11], A[12]
	local b1, b2, b3, b4, b5, b6, b7, b8, b9 = B[4], B[5], B[6], B[7], B[8], B[9], B[10], B[11], B[12]
	local bx, by, bz = B[1], B[2], B[3]
	return cf(
		a1 * bx + a2 * by + a3 * bz + A[1],
		a4 * bx + a5 * by + a6 * bz + A[2],
		a7 * bx + a8 * by + a9 * bz + A[3],
		a1 * b1 + a2 * b4 + a3 * b7,
		a1 * b2 + a2 * b5 + a3 * b8,
		a1 * b3 + a2 * b6 + a3 * b9,
		a4 * b1 + a5 * b4 + a6 * b7,
		a4 * b2 + a5 * b5 + a6 * b8,
		a4 * b3 + a5 * b6 + a6 * b9,
		a7 * b1 + a8 * b4 + a9 * b7,
		a7 * b2 + a8 * b5 + a9 * b8,
		a7 * b3 + a8 * b6 + a9 * b9
	)
end

local function cfPoint(A, v)
	return v3(
		A[4] * v.X + A[5] * v.Y + A[6] * v.Z + A[1],
		A[7] * v.X + A[8] * v.Y + A[9] * v.Z + A[2],
		A[10] * v.X + A[11] * v.Y + A[12] * v.Z + A[3]
	)
end

local function cfInverse(A)
	local x, y, z = A[1], A[2], A[3]
	-- Transpuesta de la rotación y posición -Rᵀ·t.
	return cf(
		-(A[4] * x + A[7] * y + A[10] * z),
		-(A[5] * x + A[8] * y + A[11] * z),
		-(A[6] * x + A[9] * y + A[12] * z),
		A[4],
		A[7],
		A[10],
		A[5],
		A[8],
		A[11],
		A[6],
		A[9],
		A[12]
	)
end

function CFmethods.Inverse(A)
	return cfInverse(A)
end
function CFmethods.PointToObjectSpace(A, v)
	return cfPoint(cfInverse(A), v)
end
function CFmethods.PointToWorldSpace(A, v)
	return cfPoint(A, v)
end
function CFmethods.VectorToObjectSpace(A, v)
	return v3(A[4] * v.X + A[7] * v.Y + A[10] * v.Z, A[5] * v.X + A[8] * v.Y + A[11] * v.Z, A[6] * v.X + A[9] * v.Y + A[12] * v.Z)
end
function CFmethods.VectorToWorldSpace(A, v)
	return v3(A[4] * v.X + A[5] * v.Y + A[6] * v.Z, A[7] * v.X + A[8] * v.Y + A[9] * v.Z, A[10] * v.X + A[11] * v.Y + A[12] * v.Z)
end
function CFmethods.ToObjectSpace(A, B)
	return cfMul(cfInverse(A), B)
end
function CFmethods.ToWorldSpace(A, B)
	return cfMul(A, B)
end
function CFmethods.GetComponents(A)
	return table.unpack(A, 1, 12)
end
CFmethods.components = CFmethods.GetComponents
function CFmethods.Lerp(A, B, t)
	-- Aproximación: posición lineal y rotación por interpolación de ejes re-ortonormalizados.
	local function lerp(i)
		return A[i] + (B[i] - A[i]) * t
	end
	local x = v3(lerp(4), lerp(7), lerp(10)).Unit
	local y = v3(lerp(5), lerp(8), lerp(11))
	local z = x:Cross(y).Unit
	y = z:Cross(x)
	return cf(lerp(1), lerp(2), lerp(3), x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z)
end
function CFmethods.ToEulerAnglesXYZ(A)
	-- R = Rx·Ry·Rz → r13 = sin(ry)
	local ry = math.asin(math.clamp(A[6], -1, 1))
	local rx = math.atan2(-A[9], A[12])
	local rz = math.atan2(-A[5], A[4])
	return rx, ry, rz
end

CFmt.__index = function(A, key)
	local method = CFmethods[key]
	if method then
		return method
	end
	if key == "Position" or key == "p" then
		return v3(A[1], A[2], A[3])
	elseif key == "X" then
		return A[1]
	elseif key == "Y" then
		return A[2]
	elseif key == "Z" then
		return A[3]
	elseif key == "LookVector" then
		return v3(-A[6], -A[9], -A[12])
	elseif key == "RightVector" or key == "XVector" then
		return v3(A[4], A[7], A[10])
	elseif key == "UpVector" or key == "YVector" then
		return v3(A[5], A[8], A[11])
	elseif key == "ZVector" then
		return v3(A[6], A[9], A[12])
	elseif key == "Rotation" then
		return cf(0, 0, 0, A[4], A[5], A[6], A[7], A[8], A[9], A[10], A[11], A[12])
	end
	error("CFrame: miembro desconocido " .. tostring(key), 2)
end
CFmt.__newindex = function()
	error("CFrame es inmutable", 2)
end
CFmt.__mul = function(A, B)
	if getmetatable(B) == CFmt then
		return cfMul(A, B)
	end
	return cfPoint(A, B)
end
CFmt.__add = function(A, v)
	return cf(A[1] + v.X, A[2] + v.Y, A[3] + v.Z, A[4], A[5], A[6], A[7], A[8], A[9], A[10], A[11], A[12])
end
CFmt.__sub = function(A, v)
	return cf(A[1] - v.X, A[2] - v.Y, A[3] - v.Z, A[4], A[5], A[6], A[7], A[8], A[9], A[10], A[11], A[12])
end
CFmt.__eq = function(A, B)
	for i = 1, 12 do
		if A[i] ~= B[i] then
			return false
		end
	end
	return true
end
CFmt.__tostring = function(A)
	return string.format("%g, %g, %g, %g, %g, %g, %g, %g, %g, %g, %g, %g", table.unpack(A, 1, 12))
end

local IDENTITY = cf(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)

local function fromAxes(pos, xAxis, yAxis, zAxis)
	return cf(pos.X, pos.Y, pos.Z, xAxis.X, yAxis.X, zAxis.X, xAxis.Y, yAxis.Y, zAxis.Y, xAxis.Z, yAxis.Z, zAxis.Z)
end

local function lookAt(at, target, up)
	up = up or Vector3.yAxis
	local back = at - target
	local m = back.Magnitude
	if m < 1e-9 then
		return cf(at.X, at.Y, at.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	back = back / m
	local right = up:Cross(back)
	if right.Magnitude < 1e-6 then
		-- Mirando en vertical: eje derecho arbitrario (como Roblox, cualquiera perpendicular vale).
		right = Vector3.xAxis:Cross(back)
		if right.Magnitude < 1e-6 then
			right = Vector3.zAxis:Cross(back)
		end
	end
	right = right.Unit
	local upAxis = back:Cross(right)
	return fromAxes(at, right, upAxis, back)
end

local function rotX(a)
	local c, s = math.cos(a), math.sin(a)
	return cf(0, 0, 0, 1, 0, 0, 0, c, -s, 0, s, c)
end
local function rotY(a)
	local c, s = math.cos(a), math.sin(a)
	return cf(0, 0, 0, c, 0, s, 0, 1, 0, -s, 0, c)
end
local function rotZ(a)
	local c, s = math.cos(a), math.sin(a)
	return cf(0, 0, 0, c, -s, 0, s, c, 0, 0, 0, 1)
end

local CFrame = {
	identity = IDENTITY,
	new = function(a, b, c, ...)
		if a == nil then
			return IDENTITY
		end
		if type(a) == "number" then
			local extra = { ... }
			if #extra == 9 then
				return cf(a, b, c, table.unpack(extra))
			end
			return cf(a, b, c, 1, 0, 0, 0, 1, 0, 0, 0, 1)
		end
		if b ~= nil then
			return lookAt(a, b) -- forma antigua CFrame.new(pos, lookAt)
		end
		return cf(a.X, a.Y, a.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end,
	lookAt = lookAt,
	fromMatrix = function(pos, xAxis, yAxis, zAxis)
		zAxis = zAxis or xAxis:Cross(yAxis).Unit
		return fromAxes(pos, xAxis, yAxis, zAxis)
	end,
	-- Rotación en orden Z, Y, X (R = Rx·Ry·Rz), como CFrame.Angles de Roblox.
	Angles = function(rx, ry, rz)
		return cfMul(cfMul(rotX(rx or 0), rotY(ry or 0)), rotZ(rz or 0))
	end,
	fromAxisAngle = function(axis, angle)
		local u = axis.Unit
		local c, s, t = math.cos(angle), math.sin(angle), 1 - math.cos(angle)
		local x, y, z = u.X, u.Y, u.Z
		return cf(0, 0, 0, t * x * x + c, t * x * y - s * z, t * x * z + s * y, t * x * y + s * z, t * y * y + c, t * y * z - s * x, t * x * z - s * y, t * y * z + s * x, t * z * z + c)
	end,
}
CFrame.fromEulerAnglesXYZ = CFrame.Angles
CFrame.fromOrientation = function(rx, ry, rz)
	return cfMul(cfMul(rotY(ry), rotX(rx)), rotZ(rz))
end

-- ── Color3, UDim2, Enum ───────────────────────────────────────────────

local C3mt = { __type = "Color3" }
local C3methods = {}
local function c3(r, g, b)
	return setmetatable({ R = r, G = g, B = b }, C3mt)
end
function C3methods.Lerp(a, b, t)
	return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
function C3methods.ToHex(a)
	return string.format("%02X%02X%02X", math.floor(a.R * 255 + 0.5), math.floor(a.G * 255 + 0.5), math.floor(a.B * 255 + 0.5))
end
function C3methods.ToHSV(a)
	local r, g, b = a.R, a.G, a.B
	local mx, mn = max(r, g, b), min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == r then
			h = ((g - b) / d) % 6
		elseif mx == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	return h, if mx > 0 then d / mx else 0, mx
end
C3mt.__index = function(_, key)
	local method = C3methods[key]
	if method then
		return method
	end
	error("Color3: miembro desconocido " .. tostring(key), 2)
end
C3mt.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
C3mt.__tostring = function(a)
	return string.format("%g, %g, %g", a.R, a.G, a.B)
end
local Color3 = {
	new = function(r, g, b)
		return c3(r or 0, g or 0, b or 0)
	end,
	fromRGB = function(r, g, b)
		return c3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
	end,
	fromHSV = function(h, s, v)
		local i = math.floor(h * 6)
		local f = h * 6 - i
		local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
		local k = i % 6
		if k == 0 then
			return c3(v, t, p)
		elseif k == 1 then
			return c3(q, v, p)
		elseif k == 2 then
			return c3(p, v, t)
		elseif k == 3 then
			return c3(p, q, v)
		elseif k == 4 then
			return c3(t, p, v)
		end
		return c3(v, p, q)
	end,
}

local UDmt = { __type = "UDim2" }
local UDim2 = {
	new = function(xs, xo, ys, yo)
		return setmetatable({ X = { Scale = xs or 0, Offset = xo or 0 }, Y = { Scale = ys or 0, Offset = yo or 0 } }, UDmt)
	end,
}
UDim2.fromScale = function(x, y)
	return UDim2.new(x, 0, y, 0)
end
UDim2.fromOffset = function(x, y)
	return UDim2.new(0, x, 0, y)
end
local UDim = {
	new = function(scale, offset)
		return setmetatable({ Scale = scale or 0, Offset = offset or 0 }, { __type = "UDim" })
	end,
}
local Vector2 = {
	new = function(x, y)
		return setmetatable({ X = x or 0, Y = y or 0 }, { __type = "Vector2" })
	end,
}

local ColorSequence = {
	new = function(...)
		return setmetatable({ Keypoints = { ... } }, { __type = "ColorSequence" })
	end,
}
local NumberSequence = {
	new = function(...)
		return setmetatable({ Keypoints = { ... } }, { __type = "NumberSequence" })
	end,
}

local EnumItemMt = { __type = "EnumItem" }
EnumItemMt.__tostring = function(item)
	return "Enum." .. item.EnumType .. "." .. item.Name
end
local Enum = setmetatable({}, {
	__index = function(enums, typeName)
		local items = setmetatable({}, {
			__index = function(list, itemName)
				local item = setmetatable({ Name = itemName, EnumType = typeName }, EnumItemMt)
				rawset(list, itemName, item)
				return item
			end,
		})
		rawset(enums, typeName, items)
		return items
	end,
})

-- ── Random (Park-Miller: determinista, pero no es la secuencia de Roblox) ─

local RandomMethods = {}
local RandomMt = { __type = "Random", __index = RandomMethods }
local function nextRaw(r)
	r.state = (r.state * 48271) % 2147483647
	return r.state
end
function RandomMethods.NextNumber(r, a, b)
	local u = (nextRaw(r) - 1) / 2147483646
	if a == nil then
		return u
	end
	return a + (b - a) * u
end
function RandomMethods.NextInteger(r, a, b)
	local u = (nextRaw(r) - 1) / 2147483646
	return math.min(a + math.floor(u * (b - a + 1)), b)
end
function RandomMethods.Clone(r)
	return setmetatable({ state = r.state }, RandomMt)
end
local Random = {
	new = function(seed)
		local s = math.floor((seed or 1) + (sim.seedSalt or 0) * 7919) % 2147483646
		if s <= 0 then
			s += 2147483646
		end
		local r = setmetatable({ state = s }, RandomMt)
		for _ = 1, 3 do
			nextRaw(r) -- descarta las primeras salidas (semillas parecidas dan valores parecidos)
		end
		return r
	end,
}

-- ── Instancias ────────────────────────────────────────────────────────

local CLASS_PARENT = {
	PVInstance = "Instance",
	BasePart = "PVInstance",
	FormFactorPart = "BasePart",
	Part = "FormFactorPart",
	WedgePart = "FormFactorPart",
	CornerWedgePart = "BasePart",
	TrussPart = "BasePart",
	SpawnLocation = "Part",
	MeshPart = "BasePart",
	Model = "PVInstance",
	WorldRoot = "Model",
	Workspace = "WorldRoot",
	Folder = "Instance",
	ServiceProvider = "Instance",
	DataModel = "ServiceProvider",
	LuaSourceContainer = "Instance",
	ModuleScript = "LuaSourceContainer",
	BaseScript = "LuaSourceContainer",
	Script = "BaseScript",
	LocalScript = "Script",
	GuiBase = "Instance",
	GuiBase2d = "GuiBase",
	LayerCollector = "GuiBase2d",
	SurfaceGuiBase = "LayerCollector",
	SurfaceGui = "SurfaceGuiBase",
	BillboardGui = "LayerCollector",
	ScreenGui = "LayerCollector",
	GuiObject = "GuiBase2d",
	Frame = "GuiObject",
	TextLabel = "GuiObject",
	ImageLabel = "GuiObject",
	UIComponent = "Instance",
	UIBase = "Instance",
	UIStroke = "UIComponent",
	UICorner = "UIComponent",
	UIListLayout = "UIComponent",
	UIPadding = "UIComponent",
	UIGradient = "UIComponent",
	Attachment = "Instance",
	PostEffect = "Instance",
	ColorCorrectionEffect = "PostEffect",
	Atmosphere = "Instance",
	Lighting = "Instance",
	ServerScriptService = "Instance",
	ServerStorage = "Instance",
	ReplicatedStorage = "Instance",
	Players = "Instance",
	RunService = "Instance",
	StringValue = "ValueBase",
	IntValue = "ValueBase",
	NumberValue = "ValueBase",
	ValueBase = "Instance",
}

local function isA(className: string, target: string): boolean
	local c = className
	while c do
		if c == target then
			return true
		end
		c = CLASS_PARENT[c]
	end
	return target == "Instance"
end

local function defaults(className: string)
	local p = {}
	if isA(className, "BasePart") then
		p.Anchored = false
		p.CanCollide = true
		p.CanQuery = true
		p.CanTouch = true
		p.CastShadow = true
		p.Transparency = 0
		p.Size = v3(4, 1, 2)
		p.CFrame = IDENTITY
		p.Color = c3(163 / 255, 162 / 255, 165 / 255)
		p.Material = Enum.Material.Plastic
		if className == "Part" or className == "SpawnLocation" then
			p.Shape = Enum.PartType.Block
		end
	elseif isA(className, "Model") then
		p.ModelStreamingMode = Enum.ModelStreamingMode.Default
	end
	return p
end

local InstanceMethods = {}
local InstanceMt = { __type = "Instance" }

local function newInstance(className: string)
	local inst = setmetatable({
		_class = className,
		_props = defaults(className),
		_children = {},
		_attributes = {},
		_parent = nil,
		_name = className,
		_destroyed = false,
	}, InstanceMt)
	return inst
end

local function detach(inst)
	local parent = inst._parent
	if parent then
		local children = parent._children
		for i = #children, 1, -1 do
			if children[i] == inst then
				table.remove(children, i)
				break
			end
		end
	end
	inst._parent = nil
end

InstanceMt.__index = function(inst, key)
	if string.byte(key, 1) == 95 then -- "_…": campos internos que valen nil
		return nil
	end
	if key == "Name" then
		return inst._name
	elseif key == "Parent" then
		return inst._parent
	elseif key == "ClassName" then
		return inst._class
	end
	local props = inst._props
	local value = props[key]
	if value ~= nil then
		return value
	end
	if key == "Position" and props.CFrame then
		return props.CFrame.Position
	elseif key == "Orientation" and props.CFrame then
		local rx, ry, rz = props.CFrame:ToEulerAnglesXYZ()
		return v3(math.deg(rx), math.deg(ry), math.deg(rz))
	elseif key == "WorldPivot" and isA(inst._class, "Model") then
		return inst:GetPivot()
	end
	local custom = rawget(inst, "_methods")
	if custom and custom[key] ~= nil then
		return custom[key]
	end
	local method = InstanceMethods[key]
	if method then
		return method
	end
	for _, child in inst._children do
		if child._name == key then
			return child
		end
	end
	if isA(inst._class, "BasePart") or isA(inst._class, "Model") or isA(inst._class, "GuiBase") or isA(inst._class, "UIComponent") then
		return nil -- propiedad sin valor por defecto en esta imitación
	end
	error(string.format("%s no es miembro de %s %s", tostring(key), inst._class, inst._name), 2)
end

-- ¿Cambia el mundo que ven las consultas físicas? (las piezas con CanQuery = false no cuentan: así la
-- sonda del FlightTester se mueve cada paso sin rehacer el índice).
local function inWorld(inst): boolean
	local node = inst
	while node do
		if node._class == "Workspace" then
			return true
		end
		node = node._parent
	end
	return false
end

local function affectsQueries(inst): boolean
	return (not isA(inst._class, "BasePart") or inst._props.CanQuery ~= false) and inWorld(inst)
end

InstanceMt.__newindex = function(inst, key, value)
	if string.byte(key, 1) == 95 then -- campos internos
		rawset(inst, key, value)
		return
	end
	if inst._destroyed and key == "Parent" then
		error("no se puede cambiar Parent de una instancia destruida: " .. inst._name, 2)
	end
	if key == "Name" then
		inst._name = value
	elseif key == "Parent" then
		if value == inst._parent then
			return
		end
		local before = affectsQueries(inst)
		detach(inst)
		if value then
			inst._parent = value
			table.insert(value._children, inst)
		end
		if before or affectsQueries(inst) then
			sim.dirty = true
		end
	elseif key == "Position" and isA(inst._class, "BasePart") then
		local old = inst._props.CFrame or IDENTITY
		inst._props.CFrame = old.Rotation + value
		if affectsQueries(inst) then
			sim.dirty = true
		end
	elseif key == "Size" and isA(inst._class, "BasePart") then
		if inst._props.Shape == Enum.PartType.Ball then
			local s = math.min(value.X, value.Y, value.Z)
			value = v3(s, s, s)
		end
		inst._props.Size = value
		if affectsQueries(inst) then
			sim.dirty = true
		end
	elseif key == "Shape" then
		inst._props.Shape = value
		if value == Enum.PartType.Ball and inst._props.Size then
			local size = inst._props.Size
			local s = math.min(size.X, size.Y, size.Z)
			inst._props.Size = v3(s, s, s)
		end
		if affectsQueries(inst) then
			sim.dirty = true
		end
	elseif key == "CanQuery" then
		inst._props.CanQuery = value
		if inWorld(inst) then
			sim.dirty = true
		end
	else
		if key == "CFrame" and affectsQueries(inst) then
			sim.dirty = true
		end
		inst._props[key] = value
	end
end

InstanceMt.__tostring = function(inst)
	return inst._name
end

function InstanceMethods.IsA(inst, className)
	return isA(inst._class, className)
end
function InstanceMethods.FindFirstChild(inst, name, recursive)
	for _, child in inst._children do
		if child._name == name then
			return child
		end
	end
	if recursive then
		for _, child in inst._children do
			local found = child:FindFirstChild(name, true)
			if found then
				return found
			end
		end
	end
	return nil
end
InstanceMethods.WaitForChild = InstanceMethods.FindFirstChild
function InstanceMethods.FindFirstChildOfClass(inst, className)
	for _, child in inst._children do
		if child._class == className then
			return child
		end
	end
	return nil
end
function InstanceMethods.FindFirstChildWhichIsA(inst, className, recursive)
	for _, child in inst._children do
		if isA(child._class, className) then
			return child
		end
	end
	if recursive then
		for _, child in inst._children do
			local found = child:FindFirstChildWhichIsA(className, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function InstanceMethods.FindFirstAncestor(inst, name)
	local p = inst._parent
	while p do
		if p._name == name then
			return p
		end
		p = p._parent
	end
	return nil
end
function InstanceMethods.GetChildren(inst)
	return table.clone(inst._children)
end
function InstanceMethods.GetDescendants(inst)
	local out = {}
	local function walk(node)
		for _, child in node._children do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(inst)
	return out
end
function InstanceMethods.IsDescendantOf(inst, ancestor)
	local p = inst._parent
	while p do
		if p == ancestor then
			return true
		end
		p = p._parent
	end
	return false
end
function InstanceMethods.IsAncestorOf(inst, descendant)
	return descendant:IsDescendantOf(inst)
end
function InstanceMethods.Destroy(inst)
	if affectsQueries(inst) then
		sim.dirty = true
	end
	detach(inst)
	inst._destroyed = true
	for _, child in table.clone(inst._children) do
		child:Destroy()
	end
end
function InstanceMethods.ClearAllChildren(inst)
	for _, child in table.clone(inst._children) do
		child:Destroy()
	end
end
function InstanceMethods.Clone(inst)
	local copy = newInstance(inst._class)
	copy._name = inst._name
	for k, v in inst._props do
		copy._props[k] = v
	end
	for k, v in inst._attributes do
		copy._attributes[k] = v
	end
	copy._module = inst._module
	for _, child in inst._children do
		local c = child:Clone()
		c._parent = copy
		table.insert(copy._children, c)
	end
	return copy
end
function InstanceMethods.SetAttribute(inst, name, value)
	inst._attributes[name] = value
end
function InstanceMethods.GetAttribute(inst, name)
	return inst._attributes[name]
end
function InstanceMethods.GetAttributes(inst)
	return table.clone(inst._attributes)
end
function InstanceMethods.GetFullName(inst)
	local names = {}
	local node = inst
	while node and node._class ~= "DataModel" do
		table.insert(names, 1, node._name)
		node = node._parent
	end
	return table.concat(names, ".")
end
sim.closeCallbacks = {}
function InstanceMethods.BindToClose(_, callback)
	table.insert(sim.closeCallbacks, callback)
end
function InstanceMethods.GetService(inst, name)
	local service = inst:FindFirstChild(name)
	if not service then
		service = newInstance(if CLASS_PARENT[name] then name else "Folder")
		service._name = name
		service.Parent = inst
	end
	return service
end

-- Caja envolvente alineada con el mundo (suficiente para modelos girados solo en rumbo).
local function worldBounds(inst)
	local lo, hi = v3(huge, huge, huge), v3(-huge, -huge, -huge)
	local found = false
	local function add(part)
		local c, s = part._props.CFrame, part._props.Size
		local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
		local ex = abs(c[4]) * hx + abs(c[5]) * hy + abs(c[6]) * hz
		local ey = abs(c[7]) * hx + abs(c[8]) * hy + abs(c[9]) * hz
		local ez = abs(c[10]) * hx + abs(c[11]) * hy + abs(c[12]) * hz
		lo = v3(min(lo.X, c[1] - ex), min(lo.Y, c[2] - ey), min(lo.Z, c[3] - ez))
		hi = v3(max(hi.X, c[1] + ex), max(hi.Y, c[2] + ey), max(hi.Z, c[3] + ez))
		found = true
	end
	if isA(inst._class, "BasePart") then
		add(inst)
	end
	for _, d in inst:GetDescendants() do
		if isA(d._class, "BasePart") then
			add(d)
		end
	end
	if not found then
		return IDENTITY, Vector3.zero
	end
	return CFrame.new((lo + hi) / 2), hi - lo
end

function InstanceMethods.GetBoundingBox(inst)
	return worldBounds(inst)
end
function InstanceMethods.GetExtentsSize(inst)
	local _, size = worldBounds(inst)
	return size
end
function InstanceMethods.GetPivot(inst)
	if isA(inst._class, "BasePart") then
		return inst._props.CFrame
	end
	local pivot = inst._props.WorldPivot
	if pivot then
		return pivot
	end
	local primary = inst._props.PrimaryPart
	if primary then
		return primary._props.CFrame
	end
	local box = worldBounds(inst)
	return box
end
function InstanceMethods.PivotTo(inst, target)
	local delta = cfMul(target, cfInverse(inst:GetPivot()))
	if isA(inst._class, "BasePart") then
		inst.CFrame = target
		return
	end
	for _, d in inst:GetDescendants() do
		if isA(d._class, "BasePart") then
			d.CFrame = cfMul(delta, d._props.CFrame)
		end
	end
	inst._props.WorldPivot = target
	sim.dirty = true
end
function InstanceMethods.ScaleTo(inst, factor)
	local pivot = inst:GetPivot()
	for _, d in inst:GetDescendants() do
		if isA(d._class, "BasePart") then
			local rel = cfMul(cfInverse(pivot), d._props.CFrame)
			d.Size = d._props.Size * factor
			d.CFrame = cfMul(pivot, cf(rel[1] * factor, rel[2] * factor, rel[3] * factor, table.unpack(rel, 4, 12)))
		end
	end
end

local Instance = {
	new = function(className: string, parent: any?)
		local inst = newInstance(className)
		if parent then
			inst.Parent = parent
		end
		return inst
	end,
}

-- ── game / workspace ──────────────────────────────────────────────────

local game = newInstance("DataModel")
game._name = "Game"
local workspace = newInstance("Workspace")
workspace._name = "Workspace"
workspace.Parent = game
for _, name in { "ServerScriptService", "ReplicatedStorage", "ServerStorage", "Lighting", "Players", "RunService" } do
	game:GetService(name)
end

local RaycastParams = {
	new = function()
		return { FilterType = Enum.RaycastFilterType.Exclude, FilterDescendantsInstances = {}, RespectCanCollide = false, IgnoreWater = false }
	end,
}
local OverlapParams = {
	new = function()
		return { FilterType = Enum.RaycastFilterType.Exclude, FilterDescendantsInstances = {}, RespectCanCollide = false, MaxParts = 0 }
	end,
}

-- Planificador mínimo: task.spawn crea corrutinas, task.wait las duerme en tiempo simulado (sim.now) y
-- sim.run(segundos) hace avanzar el reloj despertándolas en orden. Fuera de una corrutina, task.wait avanza
-- el reloj directamente.
sim.now = 0
local sleeping = {} -- { at, thread, args }
local function schedule(at, thread, ...)
	table.insert(sleeping, { at = at, thread = thread, args = table.pack(...) })
end
local function resume(thread, ...)
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		print("ERROR en tarea: " .. tostring(err) .. "\n" .. debug.traceback(thread))
	end
end
function sim.run(seconds)
	local target = sim.now + (seconds or 0)
	while true do
		local nextIndex, nextAt = nil, math.huge
		for i, item in sleeping do
			if item.at < nextAt then
				nextIndex, nextAt = i, item.at
			end
		end
		if not nextIndex or nextAt > target then
			break
		end
		local item = table.remove(sleeping, nextIndex)
		sim.now = math.max(sim.now, item.at)
		resume(item.thread, table.unpack(item.args, 1, item.args.n))
	end
	sim.now = math.max(sim.now, target)
end
local task = {
	wait = function(seconds)
		seconds = seconds or 0.03
		local thread = coroutine.running()
		if coroutine.isyieldable() then
			local start = sim.now
			schedule(sim.now + seconds, thread)
			coroutine.yield()
			return sim.now - start
		end
		sim.run(seconds)
		return seconds
	end,
	spawn = function(f, ...)
		local thread = if type(f) == "thread" then f else coroutine.create(f)
		resume(thread, ...)
		return thread
	end,
	defer = function(f, ...)
		local thread = coroutine.create(f)
		schedule(sim.now, thread, ...)
		return thread
	end,
	delay = function(seconds, f, ...)
		local thread = coroutine.create(f)
		schedule(sim.now + (seconds or 0), thread, ...)
		return thread
	end,
}
local function warn(...)
	print("WARN", ...)
end

local Roblox = {
	typeof = typeof,
	Vector3 = Vector3,
	CFrame = CFrame,
	Color3 = Color3,
	UDim = UDim,
	UDim2 = UDim2,
	Vector2 = Vector2,
	ColorSequence = ColorSequence,
	NumberSequence = NumberSequence,
	Enum = Enum,
	Random = Random,
	Instance = Instance,
	RaycastParams = RaycastParams,
	OverlapParams = OverlapParams,
	game = game,
	workspace = workspace,
	task = task,
	warn = warn,
	sim = sim,
	isA = isA,
	newInstance = newInstance,
}
