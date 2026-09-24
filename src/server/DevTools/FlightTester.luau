--!nonstrict
-- FlightTester: piloto automático de pruebas para el blockout (solo modo edición, no se usa en el juego).
-- Vuela un nivel con las MISMAS ecuaciones que GliderSession (GliderPhysics), controlado por dos "jugadores"
-- simulados con limitaciones humanas (reaccionan con retraso, se colocan en la barra con cierta imprecisión y se
-- deslizan a la velocidad real). Sigue la línea ideal del nivel (Folder "Route") y dice si llega y con qué margen.
--
-- Dos modos:
--   · "strict" (por defecto): la regla de diseño de siempre. Cualquier contacto del ala ENTERA (envergadura
--     completa, pies incluidos) o del suelo es un choque; sin corazones, sin asistencia y sin viento. Mide el
--     margen: cuánto se podría inflar el ala sin tocar nada.
--   · "game": como en el juego. Contactos que resbalan, 3 corazones, asistencia del nivel, puntos seguros.
--     Cuenta golpes (corazones perdidos) y alas perdidas (reapariciones).
--
-- Uso: require(game.ServerScriptService.Glider.DevTools.FlightTester:Clone()).run(4)
--      .run(4, nil, FlightTester.CALM) = piloto "tranquilo" (usa ~60 % del giro y de la subida)
--      .run(4, nil, FlightTester.NOVICE_GAME) = novato en modo juego · .checkRules() = regla de dificultad
--      .runAll() = los pilotos principales en todos los niveles

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Glider.GliderConfig)
local GliderMath = require(ReplicatedStorage.Glider.GliderMath)
local GliderPhysics = require(ReplicatedStorage.Glider.GliderPhysics)

local FlightTester = {}

local DT = 1 / 60
local MARGINS = { 32, 24, 16, 8, 4 } -- para medir a qué distancia pasó el ala de los obstáculos
local MAX_TIME = 150

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

-- lookahead = cuántos studs por delante mira la pareja sobre la línea ideal (~1,5-2,2 s).
-- reaction = segundos de retraso · deadband = precisión al colocarse en la barra (studs).
-- maxTurn / maxLift = fracción del giro y de la subida/bajada máximos que se atreve a usar el piloto.
-- Opcionales: mode ("strict" | "game"), jitter = error de cada jugador al elegir su sitio (studs, aleatorio),
-- reactions = { a, b } (cada jugador con su retraso), seed, stopOnLoss (false = reaparece y sigue).
FlightTester.FULL = { name = "completo", maxTurn = 1, maxLift = 1, lookahead = 100, reaction = 0.3, deadband = 0.15 }
FlightTester.CALM = { name = "tranquilo", maxTurn = 0.62, maxLift = 0.68, lookahead = 130, reaction = 0.3, deadband = 0.15 }
-- Novato: reacciona tarde, se coloca "más o menos" y mira menos adelante (va corrigiendo a toques).
FlightTester.NOVICE = { name = "novato", maxTurn = 1, maxLift = 1, lookahead = 90, reaction = 0.5, deadband = 0.8 }
-- El mismo novato en el juego de verdad (corazones, asistencia, contactos que resbalan).
FlightTester.NOVICE_GAME = table.clone(FlightTester.NOVICE)
FlightTester.NOVICE_GAME.name = "novato·j"
FlightTester.NOVICE_GAME.mode = "game"
-- Dúo descuidado: cada uno con su retraso, se coloca con error y mira poco adelante (tools/sim/drivers/sloppy).
FlightTester.SLOPPY = { name = "descuidado", mode = "game", maxTurn = 1, maxLift = 1, lookahead = 80, reaction = 0.6, reactions = { 0.5, 0.75 }, deadband = 0.6, jitter = 0.9, seed = 1 }

-- Punto de la polilínea `path` a `distance` studs por delante de la proyección de `pos` (desde el tramo `segment`).
local function ahead(path, segment: number, pos: Vector3, distance: number): Vector3
	local a0, b0 = path[segment], path[segment + 1]
	local ab0 = flat(b0 - a0)
	local cursor = a0:Lerp(b0, math.clamp(flat(pos - a0):Dot(ab0) / math.max(ab0:Dot(ab0), 1e-6), 0, 1))
	local remaining, index = distance, segment
	while true do
		local nextPoint = path[index + 1]
		local d = flat(nextPoint - cursor).Magnitude
		if d >= remaining or index + 1 >= #path then
			return cursor:Lerp(nextPoint, math.min(remaining / math.max(d, 1e-6), 1))
		end
		remaining -= d
		cursor = nextPoint
		index += 1
	end
end

-- Asistencia de rumbo del nivel (misma fórmula que GliderController.assistStrength).
local function assistStrength(levelIndex: number, tutorial: boolean): number
	if tutorial then
		return 0
	end
	local full, stop = Config.AssistFullUntilLevel, Config.AssistEndLevel
	return math.clamp((stop - levelIndex) / math.max(stop - full, 1), 0, 1)
end

-- root (opcional) = recorrido donde está el nivel: Workspace.Map (por defecto) o Workspace.Map.Tutorial.
-- Devuelve la línea de resultado y una tabla { ok, minMargin, hits, losses, time }.
function FlightTester.run(levelIndex: number, routeName: string?, pilot, root: Instance?): string
	pilot = pilot or FlightTester.FULL
	local gameMode = pilot.mode == "game"
	local map = root or workspace:FindFirstChild("Map")
	local tutorial = map ~= nil and map.Name == "Tutorial"
	local levelName = string.format("Level%02d", levelIndex)
	local level = map and map:FindFirstChild(levelName)
	local spawn = map and map.DevSpawns:FindFirstChild(levelName)
	if not (level and spawn) then
		return levelName .. ": no existe en Workspace.Map", { ok = false, minMargin = 0, hits = 0, losses = 0, time = 0 }
	end
	local routeFolder = level:FindFirstChild(routeName or "Route")
	local points = if routeFolder then sortedPoints(routeFolder) else {}
	local exit = level.Exit
	table.insert(points, exit)

	local span, wingTop = templateGeometry()
	local dims = { span = span, wingTop = wingTop }
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace:FindFirstChild(Config.GliderName), workspace:FindFirstChild("Lobby") }

	local random = Random.new(pilot.seed or 1)
	local inner, outer = Config.BarInnerOffset, Config.BarOuterOffset
	local players = {}
	for index = 1, 2 do
		players[index] = {
			position = (if index == 1 then -1 else 1) * (inner + Config.StartOutward * (outer - inner)),
			velocity = 0,
			reaction = if pilot.reactions then pilot.reactions[index] else pilot.reaction,
			pending = {}, -- órdenes en espera por el tiempo de reacción
			error = 0, -- error de colocación actual (jitter), cambia de vez en cuando
			errorTimer = 0,
		}
	end

	local pos = spawn.Position
	local state = GliderPhysics.newState(GliderMath.yawOf(spawn.CFrame.LookVector))
	local health = GliderPhysics.newHealth()
	local t = 0
	-- Línea ideal como polilínea: spawn → puntos de la ruta → salida → un tramo recto más.
	local path = { pos }
	for _, point in points do
		table.insert(path, point.Position)
	end
	table.insert(path, exit.Position + flat(exit.CFrame.LookVector) * 400)
	local segment = 1
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
	local hits, losses = 0, 0
	-- Modo juego: punto seguro (posición + tramo de la ruta) y tiempo de vuelo limpio.
	local safe = { pos = pos, yaw = state.yaw, segment = 1 }
	local clean, sinceSafe = 0, 0
	local strength = assistStrength(levelIndex, tutorial)
	local function where(): string
		return string.format("%.0f de la entrada", (flat(pos - level.Entry.Position)).Magnitude)
	end

	while t < MAX_TIME do
		t += DT

		-- ── "Jugadores": miran un punto de la línea ideal `lookahead` studs por delante ──
		while segment < #path - 1 do
			local a, b = path[segment], path[segment + 1]
			local ab = flat(b - a)
			if flat(pos - a):Dot(ab) / math.max(ab:Dot(ab), 1e-6) < 1 then
				break
			end
			segment += 1
		end
		local goal = ahead(path, segment, pos, pilot.lookahead)
		local toGoal = flat(goal - pos)
		local timeToGoal = math.max(toGoal.Magnitude / state.speed, 0.7)
		local wantVy = math.clamp((goal.Y - pos.Y) / timeToGoal, -Config.MaxFallSpeed, Config.MaxClimbSpeed)
		local lift = math.clamp(GliderPhysics.liftFor(wantVy), -pilot.maxLift, pilot.maxLift)
		local wantLiftInput = GliderPhysics.liftInputFor(lift)
		-- Pure pursuit: velocidad de giro = 2·v·sin(α) / distancia al punto de mira.
		local wantTurn = GliderPhysics.pursuitTurn(pos, GliderPhysics.forwardOf(state.yaw), goal, state.speed)
		local wantBalance = GliderPhysics.balanceInputFor(math.clamp(wantTurn / Config.MaxTurnRate, -pilot.maxTurn, pilot.maxTurn))
		-- Cada uno en su mitad: lift = promedio de lo abiertos, balance = diferencia.
		local oa = math.clamp(wantLiftInput + wantBalance / 2, 0, 1)
		local ob = math.clamp(wantLiftInput - wantBalance / 2, 0, 1)
		local targets = { -(inner + oa * (outer - inner)), inner + ob * (outer - inner) }
		for index, player in players do
			table.insert(player.pending, { at = t + player.reaction, goal = targets[index] })
			local pending = player.pending
			while #pending > 1 and pending[2].at <= t do
				table.remove(pending, 1)
			end
			local order = pending[1]
			if order.at <= t then
				if pilot.jitter then
					player.errorTimer -= DT
					if player.errorTimer <= 0 then
						player.errorTimer = 0.6 + random:NextNumber() * 1.2
						player.error = (random:NextNumber() * 2 - 1) * pilot.jitter
					end
				end
				local goalPos = order.goal + player.error
				local axis = if math.abs(goalPos - player.position) > pilot.deadband then math.sign(goalPos - player.position) else 0
				player.velocity = GliderMath.approach(player.velocity, axis * Config.PlayerSlideSpeed, Config.PlayerSlideResponse, DT)
				player.position = math.clamp(player.position + player.velocity * DT, -outer, outer)
			end
		end

		-- ── Mismo cálculo que GliderSession._computeInputs ──
		local liftInput, balanceInput = GliderPhysics.inputs(players[1].position, players[2].position)
		maxBalance = math.max(maxBalance, math.abs(balanceInput))
		minLift, maxLift = math.min(minLift, liftInput), math.max(maxLift, liftInput)

		local velocity
		if gameMode then
			-- ── Como GliderSession._fly: GliderPhysics.fly con corazones y asistencia (sin viento) ──
			local assistTurn = 0
			if strength > 0 then
				local assistGoal = ahead(path, segment, pos, Config.AssistLookahead)
				assistTurn = GliderPhysics.pursuitTurn(pos, GliderPhysics.forwardOf(state.yaw), assistGoal, state.speed) * Config.AssistTurnFraction * strength
			end
			local flown = GliderPhysics.fly(state, health, liftInput, balanceInput, pos, dims, DT, params, { now = t, assistTurn = assistTurn })
			if flown.event == "impact" or flown.event == "crash" then
				hits += 1
			end
			if flown.event == "crash" or pos.Y < Config.KillHeight then
				losses += 1
				if result == "OK" then
					result = string.format("PIERDE EL ALA a %s", where())
				end
				if pilot.stopOnLoss ~= false then
					break
				end
				-- Reaparece en el punto seguro (como GliderSession.respawn).
				pos, segment = safe.pos, safe.segment
				state = GliderPhysics.newState(safe.yaw)
				health = GliderPhysics.newHealth()
				clean, sinceSafe = 0, 0
				t += Config.CrashPauseTime + Config.RespawnCountdown
				continue
			end
			if flown.contact then
				clean = 0
			else
				clean += DT
			end
			sinceSafe += DT
			if sinceSafe >= Config.SafePointInterval and clean >= Config.SafePointCleanTime then
				sinceSafe = 0
				local look = flat(ahead(path, segment, pos, 80) - pos)
				safe = { pos = pos, yaw = if look.Magnitude > 1 then GliderMath.yawOf(look.Unit) else state.yaw, segment = segment }
			end
			velocity = flown.velocity
		else
			-- ── Mismo vuelo que GliderSession._fly (GliderPhysics.step, sin viento ni asistencia) ──
			local maxVertical = GliderPhysics.ceilingLimit(state, pos, dims, params)
			GliderPhysics.step(state, liftInput, balanceInput, DT, maxVertical, -math.huge, 0)
			velocity = GliderPhysics.velocity(state)

			-- ── Detección ESTRICTA: ala entera, cualquier contacto o el suelo = choque ──
			local crashed = pos.Y < Config.KillHeight
			if not crashed and workspace:Raycast(pos, Vector3.new(0, -(Config.FeetBelowRoot + Config.GroundClearance), 0), params) then
				crashed = true
				result = string.format("CHOQUE con el suelo a %s", where())
			end
			local center = GliderPhysics.cframe(state, pos) * CFrame.new(0, (wingTop - Config.FeetBelowRoot) / 2, 0)
			if not crashed then
				local sweep = velocity.Unit * (velocity.Magnitude * DT + Config.ObstacleProbeDistance)
				local hit = workspace:Blockcast(center, Vector3.new(span, wingTop + Config.FeetBelowRoot, 2), sweep, params)
				crashed = hit ~= nil and hit.Normal.Y >= -0.5
				if crashed then
					result = string.format("CHOQUE a %s contra %s", where(), hit.Instance:GetFullName():gsub("^Workspace%.Map%.", ""))
				end
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
				closest = string.format(" (%s a %s)", near:GetFullName():gsub("^Workspace%.Map%.Level%d+%.", ""), where())
			end
		end

		if pilot.trace then
			pilot.trace(t, pos, state, level) -- depuración (tools/sim/drivers/trace.luau)
		end
		pos += velocity * DT
		if passed(pos - flat(exit.CFrame.LookVector) * 50, exit) then
			break -- cruzó el plano de salida (+50)
		end
	end
	if t >= MAX_TIME and result == "OK" then
		result = "NO LLEGA a la salida"
	end

	probe:Destroy()
	local detail = if gameMode
		then string.format("golpes %d · alas perdidas %d", hits, losses)
		else string.format("margen mín %s", if minMargin == math.huge then ">32" else string.format("<%d%s", minMargin, closest))
	-- Segundo valor (para checkRules): minMargin = menor inflado del ala que aún tocaba algo (huge = nada a 32).
	return string.format("%s %-8s %-10s %-58s | %5.1fs | %s | balance máx %.2f | lift %.2f–%.2f", levelName, routeName or "", pilot.name, result, t, detail, maxBalance, minLift, maxLift),
		{ ok = result == "OK", minMargin = minMargin, hits = hits, losses = losses, time = t }
end

function FlightTester.runAll(): string
	local lines = {}
	local map = workspace:FindFirstChild("Map")
	local index = 1
	while map and map:FindFirstChild(string.format("Level%02d", index)) do
		for _, pilot in { FlightTester.NOVICE_GAME, FlightTester.CALM, FlightTester.FULL } do
			table.insert(lines, (FlightTester.run(index, nil, pilot)))
		end
		index += 1
	end
	return table.concat(lines, "\n")
end

-- ── Regla de dificultad (para los 50 niveles) ────────────────────────
-- Cada tramo de niveles exige que ciertos pilotos lleguen a la salida:
--   · { piloto estricto, margen }: el ala inflada `margen` studs por cada lado no toca nada (el techo no cuenta).
--   · { piloto de juego, golpes }: llega sin perder el ala y con como mucho esos golpes (corazones perdidos).
--   1-10  (capítulos 1-2, aprender): el novato llega en el juego sin golpes · el tranquilo pasa con ≥ 8
--   11-25 (capítulos 3-5, practicar): el novato llega en el juego (≤ 2 golpes) · el tranquilo pasa con ≥ 4
--   26-50 (capítulos 6-10, dominar): el completo pasa con ≥ 4 (el tranquilo puede fallar)
-- Reglas de diseño que el piloto no mide: ≥ 2 s de vuelo (120 studs) entre dos obstáculos; como mucho una
-- idea nueva por nivel; el último nivel de cada capítulo combina las ideas del capítulo.
FlightTester.RULES = {
	{ upTo = 10, checks = { { FlightTester.NOVICE_GAME, 0 }, { FlightTester.CALM, 8 } } },
	{ upTo = 25, checks = { { FlightTester.NOVICE_GAME, 2 }, { FlightTester.CALM, 4 } } },
	{ upTo = 50, checks = { { FlightTester.FULL, 4 } } },
}

-- Tutorial (Map.Tutorial): es la primera vez que se vuela, así que el novato y el tranquilo pasan con ≥ 8.
FlightTester.TUTORIAL_RULE = { upTo = math.huge, checks = { { FlightTester.NOVICE, 8 }, { FlightTester.CALM, 8 } } }

local function check(map: Instance?, from: number?, to: number?, fixedTier): string
	local lines, failures = {}, 0
	local index = from or 1
	while map and map:FindFirstChild(string.format("Level%02d", index)) and index <= (to or math.huge) do
		local tier = fixedTier
		for _, rule in FlightTester.RULES do
			if not tier and index <= rule.upTo then
				tier = rule
				break
			end
		end
		for _, check in tier.checks do
			local pilot, required = check[1], check[2]
			local line, info = FlightTester.run(index, nil, pilot, map)
			local pass, need
			if pilot.mode == "game" then
				pass = info.ok and info.hits <= required
				need = string.format("≤%d golpes", required)
			else
				pass = info.ok and info.minMargin > required
				need = string.format("margen ≥%d", required)
			end
			if not pass then
				failures += 1
			end
			table.insert(lines, string.format("%s %-12s · %s", if pass then "OK   " else "FALLA", need, line))
		end
		index += 1
	end
	table.insert(lines, if failures == 0 then "Regla de dificultad: todo OK" else string.format("Regla de dificultad: %d fallos", failures))
	return table.concat(lines, "\n")
end

-- from/to (opcionales) limitan los niveles comprobados.
function FlightTester.checkRules(from: number?, to: number?): string
	return check(workspace:FindFirstChild("Map"), from, to, nil)
end

-- Los tres tramos del tutorial.
function FlightTester.checkTutorial(): string
	local map = workspace:FindFirstChild("Map")
	return check(map and map:FindFirstChild("Tutorial"), nil, nil, FlightTester.TUTORIAL_RULE)
end

return FlightTester
