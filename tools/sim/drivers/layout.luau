-- Trazado del recorrido completo (sin vestido): extensión, altitudes, tramos que se acercan demasiado y
-- un SVG visto desde arriba (entre las líneas <<<SVG y SVG>>>). Argumentos: gap (distancia mínima que se
-- exige entre tramos no consecutivos, por defecto 1500), svg=false para no imprimirlo.
local ServerScriptService = game:GetService("ServerScriptService")
local MIN_GAP = ARGS.gap or 1500

local MapBuilder = require(ServerScriptService.Glider.DevTools.MapBuilder:Clone())
print(MapBuilder.build({ dress = false }))
local map = workspace.Map

-- Modelos en orden de recorrido.
local order = { map.StartIsland }
local index = 1
while map:FindFirstChild(string.format("Level%02d", index)) do
	table.insert(order, map[string.format("Level%02d", index)])
	local rest = map:FindFirstChild(string.format("RestIsland%02d", index))
	if rest then
		table.insert(order, rest)
	end
	index += 1
end
table.insert(order, map.FinishIsland)

local function bounds(parts)
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, part in parts do
		local cf, size = part.CFrame, part.Size
		local r = cf.RightVector:Abs() * size.X / 2 + cf.UpVector:Abs() * size.Y / 2 + cf.LookVector:Abs() * size.Z / 2
		lo = lo:Min(cf.Position - r)
		hi = hi:Max(cf.Position + r)
	end
	return lo, hi
end

local models = {}
local worldLo, worldHi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
for position, model in order do
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.CanQuery then
			table.insert(parts, d)
		end
	end
	local lo, hi = bounds(parts)
	local boxes = {}
	for _, part in parts do
		local plo, phi = bounds({ part })
		table.insert(boxes, { plo, phi })
	end
	models[position] = { model = model, lo = lo, hi = hi, boxes = boxes }
	worldLo, worldHi = worldLo:Min(lo), worldHi:Max(hi)
end

local function boxGap(alo, ahi, blo, bhi)
	local dx = math.max(0, blo.X - ahi.X, alo.X - bhi.X)
	local dy = math.max(0, blo.Y - ahi.Y, alo.Y - bhi.Y)
	local dz = math.max(0, blo.Z - ahi.Z, alo.Z - bhi.Z)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Tramos no vecinos (a 3 o más posiciones en el recorrido) más cerca de MIN_GAP.
local problems = {}
for i = 1, #models do
	for j = i + 3, #models do -- i+1 e i+2 son vecinos (nivel · valle · nivel)
		local a, b = models[i], models[j]
		if boxGap(a.lo, a.hi, b.lo, b.hi) < MIN_GAP then
			local best = math.huge
			for _, pa in a.boxes do
				for _, pb in b.boxes do
					local g = boxGap(pa[1], pa[2], pb[1], pb[2])
					if g < best then
						best = g
					end
				end
			end
			if best < MIN_GAP then
				table.insert(problems, string.format("  %s ↔ %s: %.0f studs", a.model.Name, b.model.Name, best))
			end
		end
	end
end

if ARGS.levels ~= false then
	for _, m in models do
		local model = m.model
		local entry, exit = model:FindFirstChild("Entry"), model:FindFirstChild("Exit")
		if entry and exit then
			local function heading(cf)
				return math.deg(math.atan2(-cf.LookVector.Z, cf.LookVector.X))
			end
			print(string.format("%-8s entrada (%6.0f, %6.0f) alt %4.0f rumbo %4.0f° → salida (%6.0f, %6.0f) alt %4.0f rumbo %4.0f° · %s", model.Name, entry.Position.X, entry.Position.Z, entry.Position.Y, heading(entry.CFrame), exit.Position.X, exit.Position.Z, exit.Position.Y, heading(exit.CFrame), tostring(model:GetAttribute("Title"))))
		end
	end
end

local farthest = 0
for _, m in models do
	for _, corner in { m.lo, m.hi, Vector3.new(m.lo.X, 0, m.hi.Z), Vector3.new(m.hi.X, 0, m.lo.Z) } do
		farthest = math.max(farthest, Vector3.new(corner.X, 0, corner.Z).Magnitude)
	end
end
print(string.format("Extensión X %.0f … %.0f · Z %.0f … %.0f · Y %.0f … %.0f · punto más lejano del origen %.0f", worldLo.X, worldHi.X, worldLo.Z, worldHi.Z, worldLo.Y, worldHi.Y, farthest))
local lobby = Vector3.new(-918.8, 265.8, -4)
local nearestLobby = math.huge
for _, m in models do
	for _, box in m.boxes do
		nearestLobby = math.min(nearestLobby, boxGap(box[1], box[2], lobby, lobby))
	end
end
print(string.format("Distancia mínima del recorrido al lobby: %.0f", nearestLobby))
if #problems == 0 then
	print(string.format("Separación: ningún par de tramos no consecutivos a menos de %d studs", MIN_GAP))
else
	print(string.format("Separación: %d pares a menos de %d studs", #problems, MIN_GAP))
	print(table.concat(problems, "\n"))
end

if ARGS.svg == false then
	return
end

-- SVG desde arriba: X a la derecha, Z hacia abajo. Cada nivel es una línea por su ruta (Entry → Route → Exit)
-- del color de su capítulo; los valles, tramos grises entre niveles.
local pad = 1500
local scale = 0.025
local width = (worldHi.X - worldLo.X + 2 * pad) * scale
local height = (worldHi.Z - worldLo.Z + 2 * pad) * scale
local function px(v: Vector3)
	return (v.X - worldLo.X + pad) * scale, (v.Z - worldLo.Z + pad) * scale
end
local CHAPTER_COLORS = { "#5fbf50", "#28d2c8", "#eb9123", "#a55fd2", "#50afff", "#14af8c", "#78c832", "#f0461e", "#e146c8", "#f0be28" }
local CHAPTER_NAMES = { "Meadow", "Red Canyon", "Autumn Forest", "Desert Mesas", "Glacier", "Sea Cliffs", "Jungle", "Volcano", "Crystal Caverns", "Sky Kingdom" }
local out = { string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%.0f" height="%.0f" viewBox="0 0 %.0f %.0f" font-family="sans-serif">', width, height + 50, width, height + 50) }
table.insert(out, string.format('<rect width="%.0f" height="%.0f" fill="#10151c"/>', width, height + 50))
local previousExit = nil
for _, m in models do
	local model = m.model
	local level = tonumber(model.Name:match("^Level(%d+)$"))
	if level then
		local points = { model.Entry.Position }
		local route = model:FindFirstChild("Route")
		if route then
			local markers = route:GetChildren()
			table.sort(markers, function(a, b)
				return a.Name < b.Name
			end)
			for _, marker in markers do
				table.insert(points, marker.Position)
			end
		end
		table.insert(points, model.Exit.Position)
		if previousExit then
			local x0, z0 = px(previousExit)
			local x1, z1 = px(points[1])
			table.insert(out, string.format('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#5a6675" stroke-width="3"/>', x0, z0, x1, z1))
		end
		local coords = {}
		for _, p in points do
			local x, z = px(p)
			table.insert(coords, string.format("%.1f,%.1f", x, z))
		end
		local color = CHAPTER_COLORS[math.clamp(math.ceil(level / 5), 1, #CHAPTER_COLORS)]
		table.insert(out, string.format('<polyline points="%s" fill="none" stroke="%s" stroke-width="6" stroke-linejoin="round" stroke-linecap="round"/>', table.concat(coords, " "), color))
		local mid = points[math.ceil(#points / 2)]
		local x, z = px(mid)
		table.insert(out, string.format('<text x="%.1f" y="%.1f" fill="#ffffff" font-size="11" font-weight="bold" text-anchor="middle">%d</text>', x, z - 8, level))
		previousExit = points[#points]
	end
end
local lx, lz = px(Vector3.new(-918.8, 0, -4))
table.insert(out, string.format('<circle cx="%.1f" cy="%.1f" r="6" fill="#ffd23c"/><text x="%.1f" y="%.1f" fill="#ffd23c" font-size="12">Lobby</text>', lx, lz, lx + 9, lz + 4))
for i, name in CHAPTER_NAMES do
	local x = 20 + ((i - 1) % 5) * (width - 40) / 5
	local y = height + 4 + ((i - 1) // 5) * 20
	table.insert(out, string.format('<rect x="%.1f" y="%.1f" width="12" height="12" fill="%s"/><text x="%.1f" y="%.1f" fill="#dfe6ee" font-size="12">%d-%d %s</text>', x, y, CHAPTER_COLORS[i], x + 17, y + 10, i * 5 - 4, i * 5, name))
end
table.insert(out, "</svg>")
print("<<<SVG")
print(table.concat(out, "\n"))
print("SVG>>>")
