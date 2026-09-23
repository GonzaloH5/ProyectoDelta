--!nonstrict
-- FlightTester: piloto automático de pruebas para el blockout (solo modo edición, no se usa en el juego).
-- Vuela un nivel con las MISMAS ecuaciones y la MISMA detección de choques que GliderSession,
-- controlado por dos "jugadores" simulados con limitaciones humanas:
--   · reaccionan con retraso (REACTION_TIME) · se deslizan por la barra a la velocidad real
-- Sigue la ruta prevista del nivel (Folder "Route") y dice si llega, dónde choca y qué margen tuvo.
--
-- Uso: require(game.ServerScriptService.Glider.DevTools.FlightTester:Clone()).run(4)
--      .run(8, "RouteAlt") para probar la ruta alternativa · .runAll() para todos los niveles
--      .run(4, nil, FlightTester.CALM) = piloto "tranquilo": solo usa la mitad del giro y de la sustentación.
--      Si un nivel sale con el piloto tranquilo es fácil; si solo sale con el completo, exige maniobras fuertes.
-- Si cambian las ecuaciones de vuelo en GliderSession, actualizar también aquí.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Glider.GliderConfig:Clone())
local GliderMath = require(ReplicatedStorage.Glider.GliderMath:Clone())

local FlightTester = {}

local DT = 1 / 60
local MARGINS = { 32, 24, 16, 8, 4 } -- para medir a qué distancia pasó el ala de los obstáculos

local function templateGeometry()
	local template = workspace:FindFirstChild(Config.GliderName)
	local bar = template:FindFirstChild(Config.BarPartName)
	local boxCFrame, size = template:GetBoundingBox()
	-- La plantilla mira a +X: en el espacio de Root, X local = Z del mundo (envergadura).
	local span = size.Z
	local wingTop = (boxCFrame.Position.Y + size.Y / 2) - bar.Position.Y
	return span, wingTop
end

local function sortedPoints(folder: Instance): { BasePart }
	local children = folder:GetChildren()
	table.sort(children, function(a, b)
		return a.Name < b.Name
	end)
	return children
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Ya pasamos un punto cuando está detrás según su propia orientación (la del recorrido allí).
local function passed(pos: Vector3, point: BasePart): boolean
	return flat(pos - point.Position):Dot(flat(point.CFrame.LookVector)) >= 0
end

-- lookahead = cuántos studs por delante mira la pareja sobre la línea ideal (~1,7-2,2 s).
-- reaction = segundos de retraso · deadband = precisión al colocarse en la barra (studs).
FlightTester.FULL = { name = "completo", maxBalance = 1, maxLiftDelta = 0.5, lookahead = 100, reaction = 0.3, deadband = 0.15 }
FlightTester.CALM = { name = "tranquilo", maxBalance = 0.5, maxLiftDelta = 0.25, lookahead = 130, reaction = 0.3, deadband = 0.15 }
-- Novato: reacciona tarde, se coloca "más o menos" y mira menos adelante (va corrigiendo a toques).
FlightTester.NOVICE = { name = "novato", maxBalance = 1, maxLiftDelta = 0.5, lookahead = 90, reaction = 0.5, deadband = 0.8 }

local function invertCurve(value: number, exponent: number): number
	value = math.clamp(value, -1, 1)
	return math.sign(value) * math.abs(value) ^ (1 / exponent)
end

function FlightTester.run(levelIndex: number, routeName: string?, pilot): string
	pilot = pilot or FlightTester.FULL
	local map = workspace:FindFirstChild("Map")
	local levelName = string.format("Level%02d", levelIndex)
	local level = map and map:FindFirstChild(levelName)
	local spawn = map and map.DevSpawns:FindFirstChild(levelName)
	if not (level and spawn) then
		return levelName .. ": no existe en Workspace.Map"
	end
	local routeFolder = level:FindFirstChild(routeName or "Route")
	local points = if routeFolder then sortedPoints(routeFolder) else {}
	local exit = level.Exit
	table.insert(points, exit)

	local span, wingTop = templateGeometry()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace:FindFirstChild(Config.GliderName), workspace:FindFirstChild("Lobby") }

	local inner, outer = Config.BarInnerOffset, Config.BarOuterOffset
	local players = {
		{ position = -(inner + Config.StartOutward * (outer - inner)), velocity = 0 },
		{ position = inner + Config.StartOutward * (outer - inner), velocity = 0 },
	}
	local pending = {} -- órdenes en espera por el tiempo de reacción

	local pos = spawn.Position
	local look = spawn.CFrame.LookVector
	local heading = math.atan2(-look.Z, look.X) -- 0 = +X; positivo = hacia la izquierda (-Z)
	local s = { vy = 0, roll = 0, rv = 0, pitch = 0, pv = 0, turn = 0 }
	local t = 0
	-- Línea ideal como polilínea: spawn → puntos de la ruta → salida → un tramo recto más.
	local path = { pos }
	for _, point in points do
		table.insert(path, point.Position)
	end
	table.insert(path, exit.Position + flat(exit.CFrame.LookVector) * 400)
	local segment = 1
	local frames = 0
	local minMargin = math.huge -- menor distancia (aprox.) a la que pasó de algo sólido
	local closest = "" -- contra qué y dónde fue el paso más ajustado
	-- Sonda con geometría exacta (las cuñas no cuentan el aire sobre su pendiente).
	local probe = Instance.new("Part")
	probe.Anchored = true
	probe.CanCollide = false
	probe.CanQuery = false
	probe.CanTouch = false
	probe.Transparency = 1
	probe.Parent = workspace
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { probe, table.unpack(params.FilterDescendantsInstances) }
	local maxBalance, minLift, maxLift = 0, 1, 0
	local result = "OK"

	while t < 150 do
		t += DT
		frames += 1

		-- ── "Jugadores": miran un punto de la línea ideal `lookahead` studs por delante ──
		while segment < #path - 1 do
			local a, b = path[segment], path[segment + 1]
			local ab = flat(b - a)
			if flat(pos - a):Dot(ab) / math.max(ab:Dot(ab), 1e-6) < 1 then
				break
			end
			segment += 1
		end
		local a0, b0 = path[segment], path[segment + 1]
		local ab0 = flat(b0 - a0)
		local cursor = a0:Lerp(b0, math.clamp(flat(pos - a0):Dot(ab0) / math.max(ab0:Dot(ab0), 1e-6), 0, 1))
		local remaining, index = pilot.lookahead, segment
		while true do
			local nextPoint = path[index + 1]
			local d = flat(nextPoint - cursor).Magnitude
			if d >= remaining or index + 1 >= #path then
				cursor = cursor:Lerp(nextPoint, math.min(remaining / math.max(d, 1e-6), 1))
				break
			end
			remaining -= d
			cursor = nextPoint
			index += 1
		end
		local goal = cursor
		local toGoal = flat(goal - pos)
		local timeToGoal = math.max(toGoal.Magnitude / Config.ForwardSpeed, 0.7)
		local wantVy = math.clamp((goal.Y - pos.Y) / timeToGoal, -Config.MaxFallSpeed, Config.MaxClimbSpeed)
		local lift = if wantVy >= 0 then invertCurve(wantVy / Config.MaxClimbSpeed, Config.LiftCurve) else invertCurve(wantVy / Config.MaxFallSpeed, Config.LiftCurve)
		local wantLiftInput = 0.5 + math.clamp(lift * 0.5, -pilot.maxLiftDelta, pilot.maxLiftDelta)
		-- Pure pursuit: velocidad de giro = 2·v·sin(α) / distancia al punto de mira.
		local alpha = (math.atan2(-toGoal.Z, toGoal.X) - heading + math.pi) % (2 * math.pi) - math.pi
		local wantTurn = math.clamp(math.deg(2 * Config.ForwardSpeed * math.sin(alpha) / math.max(toGoal.Magnitude, 1)), -Config.MaxTurnRate, Config.MaxTurnRate)
		local wantBalance = math.clamp(invertCurve(wantTurn / Config.MaxTurnRate, Config.BalanceCurve), -pilot.maxBalance, pilot.maxBalance)
		-- Cada uno en su mitad: lift = promedio de lo abiertos, balance = diferencia.
		local oa = math.clamp(wantLiftInput + wantBalance / 2, 0, 1)
		local ob = math.clamp(wantLiftInput - wantBalance / 2, 0, 1)
		table.insert(pending, { at = t + pilot.reaction, a = -(inner + oa * (outer - inner)), b = inner + ob * (outer - inner) })
		local order = pending[1]
		while #pending > 1 and pending[2].at <= t do
			table.remove(pending, 1)
			order = pending[1]
		end
		if order.at <= t then
			for index, player in players do
				local goalPos = if index == 1 then order.a else order.b
				local axis = if math.abs(goalPos - player.position) > pilot.deadband then math.sign(goalPos - player.position) else 0
				player.velocity = GliderMath.approach(player.velocity, axis * Config.PlayerSlideSpeed, Config.PlayerSlideResponse, DT)
				player.position = math.clamp(player.position + player.velocity * DT, -outer, outer)
			end
		end

		-- ── Mismo cálculo que GliderSession._computeInputs ──
		local a, b = players[1].position, players[2].position
		local function outwardness(p)
			return math.clamp((math.abs(p) - inner) / (outer - inner), 0, 1)
		end
		local liftInput = (outwardness(a) + outwardness(b)) / 2
		local balanceInput = math.clamp(-((a + b) / 2) / ((outer - inner) / 2), -1, 1)
		maxBalance = math.max(maxBalance, math.abs(balanceInput))
		minLift, maxLift = math.min(minLift, liftInput), math.max(maxLift, liftInput)

		-- ── Mismo vuelo que GliderSession._fly (sin viento) ──
		local yaw = -math.pi / 2 + heading
		local rootCFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(s.pitch), 0, 0) * CFrame.Angles(0, 0, math.rad(s.roll))

		local maxVertical = math.huge
		local rollRadians = math.rad(math.abs(s.roll))
		local topExtent = wingTop * math.cos(rollRadians) + span / 2 * math.sin(rollRadians)
		local up = workspace:Raycast(pos, Vector3.new(0, topExtent + Config.CeilingProbeDistance, 0), params)
		if up and up.Normal.Y < -0.5 then
			maxVertical = (up.Position.Y - (pos.Y + topExtent) - Config.CeilingClearance) * Config.CeilingStiffness
		end

		local neutral = Config.NeutralLiftPoint
		local l = if liftInput <= neutral then (liftInput - neutral) / neutral else (liftInput - neutral) / (1 - neutral)
		l = GliderMath.curve(l, Config.LiftCurve)
		local targetVertical = if l >= 0 then l * Config.MaxClimbSpeed else l * Config.MaxFallSpeed
		s.vy = math.min(GliderMath.approach(s.vy, targetVertical, Config.VerticalResponse, DT), maxVertical)
		local balance = GliderMath.curve(balanceInput, Config.BalanceCurve)
		s.roll, s.rv = GliderMath.spring(s.roll, s.rv, balance * Config.MaxRoll, Config.RollResponse, Config.RollDamping, DT)
		s.turn = GliderMath.approach(s.turn, (s.roll / Config.MaxRoll) * Config.MaxTurnRate, Config.TurnResponse, DT)
		heading += math.rad(s.turn) * DT
		local range = if s.vy >= 0 then Config.MaxClimbSpeed else Config.MaxFallSpeed
		s.pitch, s.pv = GliderMath.spring(s.pitch, s.pv, (s.vy / range) * Config.MaxPitch, Config.PitchResponse, Config.PitchDamping, DT)

		local velocity = Vector3.new(math.cos(heading), 0, -math.sin(heading)) * Config.ForwardSpeed + Vector3.new(0, s.vy, 0)

		-- ── Misma detección de choque que GliderSession._hitSomething ──
		local crashed = pos.Y < Config.KillHeight
		if not crashed and workspace:Raycast(pos, Vector3.new(0, -(Config.FeetBelowRoot + Config.GroundClearance), 0), params) then
			crashed = true
		end
		local center = rootCFrame * CFrame.new(0, (wingTop - Config.FeetBelowRoot) / 2, 0)
		local sweep = velocity.Unit * (velocity.Magnitude * DT + Config.ObstacleProbeDistance)
		if not crashed then
			local hit = workspace:Blockcast(center, Vector3.new(span, wingTop + Config.FeetBelowRoot, 2), sweep, params)
			crashed = hit ~= nil and hit.Normal.Y >= -0.5
			if crashed then
				result = string.format("CHOQUE a %.0f de la entrada contra %s", (flat(pos - level.Entry.Position)).Magnitude, hit.Instance:GetFullName():gsub("^Workspace%.Map%.", ""))
			end
		elseif crashed then
			result = string.format("CHOQUE con el suelo a %.0f de la entrada", (flat(pos - level.Entry.Position)).Magnitude)
		end
		if crashed then
			break
		end
		-- Margen: ¿qué obstáculos tocaría un ala inflada N studs por cada lado? (los techos no cuentan)
		for _, margin in MARGINS do
			if margin >= minMargin then
				continue
			end
			local size = Vector3.new(span + 2 * margin, wingTop + Config.FeetBelowRoot + 2 * margin, 2 + 2 * margin)
			local near: BasePart? = nil
			probe.Size = size
			probe.CFrame = center
			for _, part in workspace:GetPartsInPart(probe, overlap) do
				if not part.Name:find("Ceiling") then
					near = part
					break
				end
			end
			if not near then
				break -- si no toca con este margen, con uno menor tampoco
			end
			minMargin = margin
			closest = string.format(" (%s a %.0f)", near:GetFullName():gsub("^Workspace%.Map%.Level%d+%.", ""), (flat(pos - level.Entry.Position)).Magnitude)
		end

		pos += velocity * DT
		if passed(pos - flat(exit.CFrame.LookVector) * 50, exit) then
			break -- cruzó el plano de salida (+50)
		end
	end

	probe:Destroy()
	-- Segundo valor (para checkRules): minMargin = menor inflado del ala que aún tocaba algo (huge = nada a 32).
	return string.format(
		"%s %-8s %-9s %-58s | %4.1fs | margen mín %s | balance máx %.2f | lift %.2f–%.2f",
		levelName,
		routeName or "",
		pilot.name,
		result,
		t,
		if minMargin == math.huge then ">32" else string.format("<%d%s", minMargin, closest),
		maxBalance,
		minLift,
		maxLift
	), { ok = result == "OK", minMargin = minMargin }
end

function FlightTester.runAll(): string
	local lines = {}
	for index = 1, 10 do
		local map = workspace:FindFirstChild("Map")
		if map and map:FindFirstChild(string.format("Level%02d", index)) then
			for _, routeName in { "Route", "RouteAlt" } do
				if map[string.format("Level%02d", index)]:FindFirstChild(routeName) then
					for _, pilot in { FlightTester.NOVICE, FlightTester.CALM, FlightTester.FULL } do
						table.insert(lines, FlightTester.run(index, routeName, pilot))
					end
				end
			end
		end
	end
	return table.concat(lines, "\n")
end

-- ── Regla de dificultad (para los 50 niveles) ────────────────────────
-- Cada tramo de niveles exige que ciertos pilotos lleguen a la salida con un margen mínimo: el ala inflada
-- `margin` studs por cada lado no toca nada en todo el nivel (el techo no cuenta).
--   1-10  (capítulos 1-2, aprender): el novato y el tranquilo pasan · novato ≥ 4 · tranquilo ≥ 8
--   11-25 (capítulos 3-5, practicar): el tranquilo pasa con ≥ 4
--   26-50 (capítulos 6-10, dominar): el completo pasa con ≥ 4 (el tranquilo puede fallar)
-- Reglas de diseño que el piloto no mide: ≥ 2 s de vuelo (120 studs) entre dos obstáculos; como mucho una
-- idea nueva por nivel; el último nivel de cada capítulo combina las ideas del capítulo.
FlightTester.RULES = {
	{ upTo = 10, checks = { { FlightTester.NOVICE, 4 }, { FlightTester.CALM, 8 } } },
	{ upTo = 25, checks = { { FlightTester.CALM, 4 } } },
	{ upTo = 50, checks = { { FlightTester.FULL, 4 } } },
}

-- from/to (opcionales) limitan los niveles comprobados.
function FlightTester.checkRules(from: number?, to: number?): string
	local map = workspace:FindFirstChild("Map")
	local lines, failures = {}, 0
	local index = from or 1
	while map and map:FindFirstChild(string.format("Level%02d", index)) and index <= (to or math.huge) do
		local tier
		for _, rule in FlightTester.RULES do
			if index <= rule.upTo then
				tier = rule
				break
			end
		end
		for _, check in tier.checks do
			local pilot, required = check[1], check[2]
			local line, info = FlightTester.run(index, nil, pilot)
			local pass = info.ok and info.minMargin > required
			if not pass then
				failures += 1
			end
			table.insert(lines, string.format("%s necesita ≥%d · %s", if pass then "OK   " else "FALLA", required, line))
		end
		index += 1
	end
	table.insert(lines, if failures == 0 then "Regla de dificultad: todo OK" else string.format("Regla de dificultad: %d fallos", failures))
	return table.concat(lines, "\n")
end

return FlightTester
