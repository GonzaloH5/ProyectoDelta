-- Medidor de RITMO: vuela cada nivel con el piloto completo en modo juego (corrientes, contactos que resbalan) y
-- mide qué tienen que hacer los dos jugadores y cada cuánto:
--   · activo = hace falta algo (subir/bajar más de un 30 % o girar con balance > 0.25)
--   · muerto = tramo más largo seguido sin tener que hacer nada (s)
--   · avisos/min = gestos por minuto; cada gesto se clasifica por quién se mueve:
--       igual (los dos hacia el mismo lado: subir/bajar) · opuesto (uno fuera y otro dentro: girar/cambio) ·
--       uno (se mueve uno solo: giro subiendo/bajando, ventanas)
-- Después, la cronología de los primeros minutos (dúo nuevo con tutorial y dúo veterano).
-- Argumentos: from, to (niveles del recorrido principal, 1-10 por defecto), dress (false por defecto), minutes (5).
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Glider.GliderConfig)

local template = Instance.new("Model")
template.Name = "AlaDelta"
local bar = Instance.new("Part")
bar.Name = "Agarre"
bar.Size = Vector3.new(1, 0.5, 10)
bar.CFrame = CFrame.new(0, 400, 0)
bar.Parent = template
local wing = Instance.new("Part")
wing.Size = Vector3.new(14, 1, ARGS.span or 32)
wing.CFrame = CFrame.new(0, 400 + (ARGS.wingTop or 4) - 0.5, 0)
wing.Parent = template
template.Parent = workspace

local MapBuilder = require(ServerScriptService.Glider.DevTools.MapBuilder:Clone())
MapBuilder.build({ dress = ARGS.dress == true })
local FlightTester = require(ServerScriptService.Glider.DevTools.FlightTester:Clone())
local map = workspace.Map
local tutorial = map:FindFirstChild("Tutorial")

local inner, outer = Config.BarInnerOffset, Config.BarOuterOffset
local function outwardness(position: number): number
	return math.clamp((math.abs(position) - inner) / (outer - inner), 0, 1)
end

-- Vuela un nivel y devuelve sus medidas de ritmo.
local function measure(index: number, root: Instance)
	local samples = {}
	local pilot = table.clone(FlightTester.FULL)
	pilot.mode = "game"
	pilot.stopOnLoss = false
	pilot.inputs = function(t, lift, balance, a, b)
		table.insert(samples, { t = t, lift = lift, balance = balance, o = { outwardness(a), outwardness(b) } })
	end
	local _, info = FlightTester.run(index, nil, pilot, root)
	local duration = info.time
	-- Activo / tramo muerto.
	local activeTime, idle, longestIdle, idleFrom, longestAt = 0, 0, 0, 0, 0
	local previousT = 0
	local approach = 150 / Config.ForwardSpeed -- el piloto sale 150 studs antes de la entrada (DevSpawns)
	for _, sample in samples do
		local dt = sample.t - previousT
		previousT = sample.t
		if sample.t < approach then
			continue
		end
		if math.abs(sample.lift - 0.5) > 0.15 or math.abs(sample.balance) > 0.25 then
			activeTime += dt
			idle = 0
		else
			if idle == 0 then
				idleFrom = sample.t
			end
			idle += dt
			if idle > longestIdle then
				longestIdle, longestAt = idle, idleFrom
			end
		end
	end
	-- Gestos: tramos de movimiento de cada jugador (≥ 20 % de la barra), agrupados si empiezan a < 0,45 s.
	local moves = {}
	for player = 1, 2 do
		local startT, startO, lastO, direction, stillFor = nil, 0, nil, 0, 0
		for _, sample in samples do
			local o = sample.o[player]
			if lastO then
				local d = o - lastO
				if math.abs(d) > 0.004 then
					local dir = if d > 0 then 1 else -1
					if startT and dir ~= direction then
						if math.abs(lastO - startO) >= 0.2 then
							table.insert(moves, { t = startT, player = player, dir = direction })
						end
						startT = nil
					end
					if not startT then
						startT, startO, direction = sample.t, lastO, dir
					end
					stillFor = 0
				elseif startT then
					stillFor += 1 / 60
					if stillFor > 0.15 then
						if math.abs(o - startO) >= 0.2 then
							table.insert(moves, { t = startT, player = player, dir = direction })
						end
						startT = nil
					end
				end
			end
			lastO = o
		end
	end
	table.sort(moves, function(x, y)
		return x.t < y.t
	end)
	local counts = { igual = 0, opuesto = 0, uno = 0 }
	local i = 1
	while i <= #moves do
		local first, second = moves[i], moves[i + 1]
		if second and second.player ~= first.player and second.t - first.t < 0.45 then
			if second.dir == first.dir then
				counts.igual += 1
			else
				counts.opuesto += 1
			end
			i += 2
		else
			counts.uno += 1
			i += 1
		end
	end
	local calls = counts.igual + counts.opuesto + counts.uno
	return {
		duration = duration,
		active = activeTime / math.max(duration - approach, 1e-3),
		idle = longestIdle,
		idleAt = longestAt,
		callsPerMinute = calls / math.max(duration, 1e-3) * 60,
		counts = counts,
		hits = info.hits,
		losses = info.losses,
	}
end

local function row(name: string, title: string, m)
	print(string.format("%-11s %-20s %5.1fs  activo %3.0f%%  muerto %4.1fs (en %4.1fs)  avisos/min %4.1f  igual %2d · opuesto %2d · uno %2d  golpes %d", name, title, m.duration, m.active * 100, m.idle, m.idleAt, m.callsPerMinute, m.counts.igual, m.counts.opuesto, m.counts.uno, m.hits))
end

local function levelTitle(root: Instance, index: number): string
	local level = root:FindFirstChild(string.format("Level%02d", index))
	return if level then level:GetAttribute("Title") or "" else ""
end

-- Tiempo de vuelo de un tramo entre dos marcadores (valles, despegue → primer nivel), a la velocidad base.
local function glide(from: BasePart?, to: BasePart?): number
	if not (from and to) then
		return 0
	end
	return ((to.Position - from.Position) * Vector3.new(1, 0, 1)).Magnitude / Config.ForwardSpeed
end

print(string.format("%-11s %-20s %6s", "nivel", "título", "tiempo"))
local tutorialRows = {}
if tutorial then
	local index = 1
	while tutorial:FindFirstChild(string.format("Level%02d", index)) do
		local m = measure(index, tutorial)
		row(string.format("Tutorial%02d", index), levelTitle(tutorial, index), m)
		table.insert(tutorialRows, m)
		index += 1
	end
end
local mainRows = {}
local from, to = ARGS.from or 1, ARGS.to or 10
for index = from, to do
	if not map:FindFirstChild(string.format("Level%02d", index)) then
		break
	end
	local m = measure(index, map)
	row(string.format("Level%02d", index), levelTitle(map, index), m)
	mainRows[index] = m
end

-- ── Cronología de los primeros minutos ──
local limit = (ARGS.minutes or 5) * 60
local function clock(t: number): string
	return string.format("%d:%02d", math.floor(t / 60), math.floor(t % 60))
end
local function timeline(label: string, withTutorial: boolean)
	print("\n" .. label)
	local t = Config.PadCountdown + Config.CountdownTime
	local lines = {}
	local function add(name: string, seconds: number)
		if t < limit then
			table.insert(lines, string.format("  %s  %-34s %5.1fs", clock(t), name, seconds))
		end
		t += seconds
	end
	local valleyTotal = 0
	if withTutorial and tutorial and #tutorialRows > 0 then
		add("despegue → tutorial", glide(tutorial.StartIsland:FindFirstChild("LaunchPoint"), tutorial.Level01:FindFirstChild("Entry")))
		for index, m in tutorialRows do
			add(string.format("Tutorial %d · %s", index, levelTitle(tutorial, index)), m.duration)
			local nextLevel = tutorial:FindFirstChild(string.format("Level%02d", index + 1))
			if nextLevel then
				local valley = glide(tutorial[string.format("Level%02d", index)].Exit, nextLevel.Entry)
				valleyTotal += valley
				add("valle", valley)
			end
		end
		add("paso al recorrido (cuenta atrás)", Config.CountdownTime + 1)
	end
	add("despegue → nivel 1", glide(map.StartIsland:FindFirstChild("LaunchPoint"), map.Level01.Entry))
	for index = from, to do
		local m = mainRows[index]
		if not m or t >= limit then
			break
		end
		add(string.format("Nivel %d · %s", index, levelTitle(map, index)), m.duration)
		local nextLevel = map:FindFirstChild(string.format("Level%02d", index + 1))
		if nextLevel then
			local valley = glide(map[string.format("Level%02d", index)].Exit, nextLevel.Entry)
			valleyTotal += valley
			add("valle", valley)
		end
	end
	for _, line in lines do
		print(line)
	end
	print(string.format("  (valles hasta aquí: %.0f s)", valleyTotal))
end
timeline("Primeros minutos · dúo nuevo (con tutorial):", true)
timeline("Primeros minutos · dúo veterano:", false)
