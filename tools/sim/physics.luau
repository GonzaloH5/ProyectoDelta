-- Consultas físicas de la imitación de Roblox (se pega detrás de roblox.luau).
-- Formas: bloque (OBB), cuña (WedgePart: sube hacia su +Z local) y bola. Cilindro = bloque.
-- · Raycast: el primer punto de entrada; un rayo que nace dentro de una pieza no la detecta (como Roblox).
-- · Blockcast: SAT con barrido (exacto para bloque y cuña; la bola se muestrea). Ignora lo que ya
--   toca al empezar (como los shapecasts de Roblox).
-- · GetPartsInPart: SAT exacto entre la caja de consulta y cada forma.
-- Las piezas se indexan en una rejilla 3D la primera vez que se consulta tras un cambio del mundo.
-- Las piezas con atributo Motion (obstáculos móviles) van aparte: se prueban una a una en cada consulta con su
-- CFrame actual, así moverlas no obliga a reindexar todo el mapa.

do
	local sim, isA = Roblox.sim, Roblox.isA
	local Vector3, Enum, workspace = Roblox.Vector3, Roblox.Enum, Roblox.workspace
	local abs, sqrt, floor, min, max, huge = math.abs, math.sqrt, math.floor, math.min, math.max, math.huge

	local CELL = 64
	local OFFSET = 8192
	local shapes = {} -- lista de formas indexadas
	local grid = {} -- clave de celda → lista de formas
	local stamp = 0
	local dynamicParts = {} -- piezas con atributo Motion

	local function cellKey(ix, iy, iz)
		return ((ix + OFFSET) * 16384 + (iy + OFFSET)) * 16384 + (iz + OFFSET)
	end

	-- Forma a partir de una pieza: centro, ejes (columnas de la rotación), medio tamaño, planos locales y vértices.
	local function makeShape(part)
		local props = part._props
		local c, s = props.CFrame, props.Size
		local shape = {
			part = part,
			cx = c[1],
			cy = c[2],
			cz = c[3],
			-- Ejes locales en el mundo: X = (r1, r4, r7), Y = (r2, r5, r8), Z = (r3, r6, r9).
			r1 = c[4],
			r2 = c[5],
			r3 = c[6],
			r4 = c[7],
			r5 = c[8],
			r6 = c[9],
			r7 = c[10],
			r8 = c[11],
			r9 = c[12],
			hx = s.X / 2,
			hy = s.Y / 2,
			hz = s.Z / 2,
		}
		if part._class == "WedgePart" then
			shape.kind = "wedge"
		elseif props.Shape == Enum.PartType.Ball then
			shape.kind = "ball"
			shape.radius = min(s.X, s.Y, s.Z) / 2
		else
			shape.kind = "block"
		end
		local hx, hy, hz = shape.hx, shape.hy, shape.hz
		local ex = abs(shape.r1) * hx + abs(shape.r2) * hy + abs(shape.r3) * hz
		local ey = abs(shape.r4) * hx + abs(shape.r5) * hy + abs(shape.r6) * hz
		local ez = abs(shape.r7) * hx + abs(shape.r8) * hy + abs(shape.r9) * hz
		if shape.kind == "ball" then
			ex, ey, ez = shape.radius, shape.radius, shape.radius
		end
		shape.minx, shape.maxx = shape.cx - ex, shape.cx + ex
		shape.miny, shape.maxy = shape.cy - ey, shape.cy + ey
		shape.minz, shape.maxz = shape.cz - ez, shape.cz + ez

		-- Planos locales n·p ≤ d.
		if shape.kind == "wedge" then
			local l = sqrt(hy * hy + hz * hz)
			shape.planes = {
				{ 1, 0, 0, hx },
				{ -1, 0, 0, hx },
				{ 0, -1, 0, hy },
				{ 0, 0, 1, hz },
				{ 0, hz / l, -hy / l, 0 }, -- pendiente: y/hy ≤ z/hz
			}
			local verts = {}
			for _, p in { { -hx, -hy, -hz }, { hx, -hy, -hz }, { -hx, -hy, hz }, { hx, -hy, hz }, { -hx, hy, hz }, { hx, hy, hz } } do
				local x, y, z = p[1], p[2], p[3]
				table.insert(verts, {
					shape.cx + shape.r1 * x + shape.r2 * y + shape.r3 * z,
					shape.cy + shape.r4 * x + shape.r5 * y + shape.r6 * z,
					shape.cz + shape.r7 * x + shape.r8 * y + shape.r9 * z,
				})
			end
			shape.verts = verts
			-- Normales de cara y aristas en el mundo (para SAT).
			local function world(x, y, z)
				return { shape.r1 * x + shape.r2 * y + shape.r3 * z, shape.r4 * x + shape.r5 * y + shape.r6 * z, shape.r7 * x + shape.r8 * y + shape.r9 * z }
			end
			shape.normals = { world(1, 0, 0), world(0, 1, 0), world(0, 0, 1), world(0, hz / l, -hy / l) }
			shape.edges = { world(1, 0, 0), world(0, 1, 0), world(0, 0, 1), world(0, hy / l, hz / l) }
		elseif shape.kind == "block" then
			shape.planes = {
				{ 1, 0, 0, hx },
				{ -1, 0, 0, hx },
				{ 0, 1, 0, hy },
				{ 0, -1, 0, hy },
				{ 0, 0, 1, hz },
				{ 0, 0, -1, hz },
			}
		end
		return shape
	end

	local function rebuild()
		shapes = {}
		grid = {}
		dynamicParts = {}
		for _, d in workspace:GetDescendants() do
			if isA(d._class, "BasePart") and d._props.CanQuery ~= false and d._attributes.Motion ~= nil then
				table.insert(dynamicParts, d)
			elseif isA(d._class, "BasePart") and d._props.CanQuery ~= false then
				local shape = makeShape(d)
				table.insert(shapes, shape)
				local x0, x1 = floor(shape.minx / CELL), floor(shape.maxx / CELL)
				local y0, y1 = floor(shape.miny / CELL), floor(shape.maxy / CELL)
				local z0, z1 = floor(shape.minz / CELL), floor(shape.maxz / CELL)
				for ix = x0, x1 do
					for iy = y0, y1 do
						for iz = z0, z1 do
							local key = cellKey(ix, iy, iz)
							local list = grid[key]
							if not list then
								list = {}
								grid[key] = list
							end
							table.insert(list, shape)
						end
					end
				end
			end
		end
		sim.dirty = false
		sim.shapeCount = #shapes
	end

	local function ensureIndex()
		if sim.dirty then
			rebuild()
		end
	end

	-- Formas cuya caja envolvente toca la caja [min, max].
	local function candidates(minx, miny, minz, maxx, maxy, maxz)
		stamp += 1
		local out = {}
		for ix = floor(minx / CELL), floor(maxx / CELL) do
			for iy = floor(miny / CELL), floor(maxy / CELL) do
				for iz = floor(minz / CELL), floor(maxz / CELL) do
					local list = grid[cellKey(ix, iy, iz)]
					if list then
						for _, shape in list do
							if shape.stamp ~= stamp then
								shape.stamp = stamp
								if shape.maxx >= minx and shape.minx <= maxx and shape.maxy >= miny and shape.miny <= maxy and shape.maxz >= minz and shape.minz <= maxz then
									table.insert(out, shape)
								end
							end
						end
					end
				end
			end
		end
		for _, part in dynamicParts do
			local shape = makeShape(part)
			if shape.maxx >= minx and shape.minx <= maxx and shape.maxy >= miny and shape.miny <= maxy and shape.maxz >= minz and shape.minz <= maxz then
				table.insert(out, shape)
			end
		end
		return out
	end

	-- Filtro de RaycastParams / OverlapParams (lista de raíces, Exclude o Include).
	local function makeFilter(params)
		params = params or {}
		local roots = {}
		for _, inst in params.FilterDescendantsInstances or {} do
			roots[inst] = true
		end
		local include = params.FilterType == Enum.RaycastFilterType.Include
		local respect = params.RespectCanCollide
		local cache = {}
		return function(part)
			if respect and part._props.CanCollide == false then
				return false
			end
			local known = cache[part]
			if known ~= nil then
				return known
			end
			local inRoots = false
			local node = part
			while node do
				if roots[node] then
					inRoots = true
					break
				end
				node = node._parent
			end
			local ok = if include then inRoots else not inRoots
			cache[part] = ok
			return ok
		end
	end

	-- ── Rayos ─────────────────────────────────────────────────────────

	-- Devuelve t de entrada (0..1) y normal local, o nil. Rayo en coordenadas locales de la forma.
	local function rayConvex(planes, ox, oy, oz, dx, dy, dz)
		local tEnter, tExit = -huge, huge
		local nx, ny, nz = 0, 0, 0
		for _, p in planes do
			local denom = p[1] * dx + p[2] * dy + p[3] * dz
			local num = p[4] - (p[1] * ox + p[2] * oy + p[3] * oz)
			if abs(denom) < 1e-12 then
				if num < 0 then
					return nil
				end
			else
				local t = num / denom
				if denom < 0 then
					if t > tEnter then
						tEnter = t
						nx, ny, nz = p[1], p[2], p[3]
					end
				elseif t < tExit then
					tExit = t
				end
			end
			if tEnter > tExit then
				return nil
			end
		end
		if tEnter < 0 or tEnter > 1 then
			return nil -- nace dentro (no detecta la pieza) o no llega
		end
		return tEnter, nx, ny, nz
	end

	local function rayShape(shape, ox, oy, oz, dx, dy, dz)
		if shape.kind == "ball" then
			local fx, fy, fz = ox - shape.cx, oy - shape.cy, oz - shape.cz
			local a = dx * dx + dy * dy + dz * dz
			local b = 2 * (fx * dx + fy * dy + fz * dz)
			local c = fx * fx + fy * fy + fz * fz - shape.radius * shape.radius
			if c < 0 then
				return nil
			end
			local disc = b * b - 4 * a * c
			if disc < 0 then
				return nil
			end
			local t = (-b - sqrt(disc)) / (2 * a)
			if t < 0 or t > 1 then
				return nil
			end
			local px, py, pz = fx + dx * t, fy + dy * t, fz + dz * t
			local m = sqrt(px * px + py * py + pz * pz)
			return t, px / m, py / m, pz / m
		end
		-- A coordenadas locales: o' = Rᵀ(o - c), d' = Rᵀ d.
		local rx, ry, rz = ox - shape.cx, oy - shape.cy, oz - shape.cz
		local lox = shape.r1 * rx + shape.r4 * ry + shape.r7 * rz
		local loy = shape.r2 * rx + shape.r5 * ry + shape.r8 * rz
		local loz = shape.r3 * rx + shape.r6 * ry + shape.r9 * rz
		local ldx = shape.r1 * dx + shape.r4 * dy + shape.r7 * dz
		local ldy = shape.r2 * dx + shape.r5 * dy + shape.r8 * dz
		local ldz = shape.r3 * dx + shape.r6 * dy + shape.r9 * dz
		local t, nx, ny, nz = rayConvex(shape.planes, lox, loy, loz, ldx, ldy, ldz)
		if not t then
			return nil
		end
		return t, shape.r1 * nx + shape.r2 * ny + shape.r3 * nz, shape.r4 * nx + shape.r5 * ny + shape.r6 * nz, shape.r7 * nx + shape.r8 * ny + shape.r9 * nz
	end

	local function raycast(origin, direction, params)
		ensureIndex()
		local ox, oy, oz = origin.X, origin.Y, origin.Z
		local dx, dy, dz = direction.X, direction.Y, direction.Z
		if dx * dx + dy * dy + dz * dz < 1e-12 then
			return nil
		end
		local filter = makeFilter(params)
		local best, bestT, bnx, bny, bnz = nil, huge, 0, 0, 0
		for _, shape in candidates(min(ox, ox + dx), min(oy, oy + dy), min(oz, oz + dz), max(ox, ox + dx), max(oy, oy + dy), max(oz, oz + dz)) do
			if filter(shape.part) then
				local t, nx, ny, nz = rayShape(shape, ox, oy, oz, dx, dy, dz)
				if t and t < bestT then
					best, bestT, bnx, bny, bnz = shape, t, nx, ny, nz
				end
			end
		end
		if not best then
			return nil
		end
		local length = sqrt(dx * dx + dy * dy + dz * dz)
		return {
			Instance = best.part,
			Position = Vector3.new(ox + dx * bestT, oy + dy * bestT, oz + dz * bestT),
			Normal = Vector3.new(bnx, bny, bnz),
			Distance = length * bestT,
			Material = best.part._props.Material,
		}
	end

	-- ── Caja de consulta (orientada) ──────────────────────────────────

	local function boxFrom(cframe, size)
		local c = cframe
		return {
			cx = c[1],
			cy = c[2],
			cz = c[3],
			a = { { c[4], c[7], c[10] }, { c[5], c[8], c[11] }, { c[6], c[9], c[12] } }, -- ejes X, Y, Z
			h = { size.X / 2, size.Y / 2, size.Z / 2 },
		}
	end

	local function boxAabb(box, dx, dy, dz)
		local a, h = box.a, box.h
		local ex = abs(a[1][1]) * h[1] + abs(a[2][1]) * h[2] + abs(a[3][1]) * h[3]
		local ey = abs(a[1][2]) * h[1] + abs(a[2][2]) * h[2] + abs(a[3][2]) * h[3]
		local ez = abs(a[1][3]) * h[1] + abs(a[2][3]) * h[2] + abs(a[3][3]) * h[3]
		dx, dy, dz = dx or 0, dy or 0, dz or 0
		return box.cx - ex + min(0, dx), box.cy - ey + min(0, dy), box.cz - ez + min(0, dz), box.cx + ex + max(0, dx), box.cy + ey + max(0, dy), box.cz + ez + max(0, dz)
	end

	-- Ejes SAT entre la caja y una forma (bloque o cuña).
	local function satAxes(box, shape)
		local axes = {}
		local a = box.a
		local faceB, edgeB
		if shape.kind == "wedge" then
			faceB, edgeB = shape.normals, shape.edges
		else
			local bx = { shape.r1, shape.r4, shape.r7 }
			local by = { shape.r2, shape.r5, shape.r8 }
			local bz = { shape.r3, shape.r6, shape.r9 }
			faceB, edgeB = { bx, by, bz }, { bx, by, bz }
		end
		for i = 1, 3 do
			table.insert(axes, a[i])
		end
		for _, n in faceB do
			table.insert(axes, n)
		end
		for i = 1, 3 do
			local u = a[i]
			for _, e in edgeB do
				local x, y, z = u[2] * e[3] - u[3] * e[2], u[3] * e[1] - u[1] * e[3], u[1] * e[2] - u[2] * e[1]
				local m = x * x + y * y + z * z
				if m > 1e-9 then
					m = sqrt(m)
					table.insert(axes, { x / m, y / m, z / m })
				end
			end
		end
		return axes
	end

	-- Proyección de la forma sobre el eje: [min, max].
	local function projectShape(shape, l1, l2, l3)
		if shape.kind == "wedge" then
			local lo, hi = huge, -huge
			for _, v in shape.verts do
				local p = v[1] * l1 + v[2] * l2 + v[3] * l3
				if p < lo then
					lo = p
				end
				if p > hi then
					hi = p
				end
			end
			return lo, hi
		end
		local c = shape.cx * l1 + shape.cy * l2 + shape.cz * l3
		local r = shape.hx * abs(shape.r1 * l1 + shape.r4 * l2 + shape.r7 * l3) + shape.hy * abs(shape.r2 * l1 + shape.r5 * l2 + shape.r8 * l3) + shape.hz * abs(shape.r3 * l1 + shape.r6 * l2 + shape.r9 * l3)
		return c - r, c + r
	end

	local function projectBox(box, l1, l2, l3)
		local a, h = box.a, box.h
		local c = box.cx * l1 + box.cy * l2 + box.cz * l3
		local r = h[1] * abs(a[1][1] * l1 + a[1][2] * l2 + a[1][3] * l3) + h[2] * abs(a[2][1] * l1 + a[2][2] * l2 + a[2][3] * l3) + h[3] * abs(a[3][1] * l1 + a[3][2] * l2 + a[3][3] * l3)
		return c, r
	end

	-- Bola contra caja (estática): punto más cercano de la caja al centro.
	local function ballOverlapsBox(shape, box, ox, oy, oz)
		local px, py, pz = shape.cx - (box.cx + (ox or 0)), shape.cy - (box.cy + (oy or 0)), shape.cz - (box.cz + (oz or 0))
		local a, h = box.a, box.h
		local qx, qy, qz = 0, 0, 0
		for i = 1, 3 do
			local d = px * a[i][1] + py * a[i][2] + pz * a[i][3]
			d = math.clamp(d, -h[i], h[i])
			qx += a[i][1] * d
			qy += a[i][2] * d
			qz += a[i][3] * d
		end
		local dx, dy, dz = px - qx, py - qy, pz - qz
		return dx * dx + dy * dy + dz * dz <= shape.radius * shape.radius, dx, dy, dz
	end

	local function overlaps(box, shape)
		if shape.kind == "ball" then
			return (ballOverlapsBox(shape, box))
		end
		for _, l in satAxes(box, shape) do
			local c, r = projectBox(box, l[1], l[2], l[3])
			local lo, hi = projectShape(shape, l[1], l[2], l[3])
			if c + r < lo or c - r > hi then
				return false
			end
		end
		return true
	end

	-- Barrido: primer t ∈ [0, 1] en que la caja, moviéndose d, toca la forma. nil si ya se tocaban en t = 0.
	local function sweep(box, shape, dx, dy, dz)
		if shape.kind == "ball" then
			local initially = ballOverlapsBox(shape, box)
			if initially then
				return nil
			end
			local length = sqrt(dx * dx + dy * dy + dz * dz)
			local steps = max(4, math.ceil(length / 0.25))
			for i = 1, steps do
				local t = i / steps
				local hit, nx, ny, nz = ballOverlapsBox(shape, box, dx * t, dy * t, dz * t)
				if hit then
					local m = sqrt(nx * nx + ny * ny + nz * nz)
					if m < 1e-9 then
						return t, -dx / length, -dy / length, -dz / length
					end
					return t, -nx / m, -ny / m, -nz / m
				end
			end
			return nil
		end
		local tFirst, tLast = -huge, huge
		local nx, ny, nz = 0, 0, 0
		for _, l in satAxes(box, shape) do
			local c, r = projectBox(box, l[1], l[2], l[3])
			local lo, hi = projectShape(shape, l[1], l[2], l[3])
			local v = dx * l[1] + dy * l[2] + dz * l[3]
			if abs(v) < 1e-12 then
				if c + r < lo or c - r > hi then
					return nil
				end
			else
				local t0 = (lo - (c + r)) / v
				local t1 = (hi - (c - r)) / v
				local enter, exit = min(t0, t1), max(t0, t1)
				if enter > tFirst then
					tFirst = enter
					local sign = if v > 0 then -1 else 1
					nx, ny, nz = l[1] * sign, l[2] * sign, l[3] * sign
				end
				if exit < tLast then
					tLast = exit
				end
				if tFirst > tLast or tFirst > 1 or tLast < 0 then
					return nil
				end
			end
		end
		if tFirst < 0 then
			return nil -- ya se tocaban al empezar: los shapecasts de Roblox no lo detectan
		end
		return tFirst, nx, ny, nz
	end

	local function blockcast(cframe, size, direction, params)
		ensureIndex()
		local box = boxFrom(cframe, size)
		local dx, dy, dz = direction.X, direction.Y, direction.Z
		local filter = makeFilter(params)
		local best, bestT, bnx, bny, bnz = nil, huge, 0, 0, 0
		for _, shape in candidates(boxAabb(box, dx, dy, dz)) do
			if filter(shape.part) then
				local t, nx, ny, nz = sweep(box, shape, dx, dy, dz)
				if t and t < bestT then
					best, bestT, bnx, bny, bnz = shape, t, nx, ny, nz
				end
			end
		end
		if not best then
			return nil
		end
		local length = sqrt(dx * dx + dy * dy + dz * dz)
		return {
			Instance = best.part,
			Position = Vector3.new(box.cx + dx * bestT, box.cy + dy * bestT, box.cz + dz * bestT),
			Normal = Vector3.new(bnx, bny, bnz),
			Distance = length * bestT,
			Material = best.part._props.Material,
		}
	end

	local function partsInBox(cframe, size, params)
		ensureIndex()
		local box = boxFrom(cframe, size)
		local filter = makeFilter(params)
		local out = {}
		for _, shape in candidates(boxAabb(box)) do
			if filter(shape.part) and overlaps(box, shape) then
				table.insert(out, shape.part)
				if params and params.MaxParts and params.MaxParts > 0 and #out >= params.MaxParts then
					break
				end
			end
		end
		return out
	end

	local WorkspaceMethods = {
		Raycast = function(_, origin, direction, params)
			return raycast(origin, direction, params)
		end,
		Blockcast = function(_, cframe, size, direction, params)
			return blockcast(cframe, size, direction, params)
		end,
		GetPartsInPart = function(_, part, params)
			return partsInBox(part._props.CFrame, part._props.Size, params)
		end,
		GetPartBoundsInBox = function(_, cframe, size, params)
			return partsInBox(cframe, size, params)
		end,
	}
	-- Métodos solo del Workspace: se buscan antes que los genéricos de Instance.
	local baseIndex = getmetatable(workspace).__index
	local workspaceMt = table.clone(getmetatable(workspace))
	workspaceMt.__index = function(inst, key)
		local method = WorkspaceMethods[key]
		if method then
			return method
		end
		return baseIndex(inst, key)
	end
	setmetatable(workspace, workspaceMt)

	Roblox.physics = { rebuild = rebuild, shapeCount = function()
		return #shapes
	end }
end
