-- Prueba de DuoLeaderboard y PlayerStats con un DataStore / OrderedDataStore falsos (en memoria).
local failures = 0
local function check(name, ok, detail)
	if not ok then
		failures += 1
		print("FALLA", name, detail or "")
	end
end

-- ── Servicios falsos ──────────────────────────────────────────────────
local ordered: { [string]: number } = {}
local writes = 0
local orderedStore = {
	UpdateAsync = function(_, key, transform)
		local new = transform(ordered[key], nil)
		if new ~= nil then
			ordered[key] = new
			writes += 1
		end
		return new
	end,
	GetSortedAsync = function(_, ascending, pageSize)
		local list = {}
		for key, value in ordered do
			table.insert(list, { key = key, value = value })
		end
		table.sort(list, function(a, b)
			if ascending then
				return a.value < b.value
			end
			return a.value > b.value
		end)
		while #list > pageSize do
			table.remove(list)
		end
		return { GetCurrentPage = function()
			return list
		end }
	end,
}
local plain: { [string]: any } = {}
local plainStore = {
	GetAsync = function(_, key)
		return plain[key]
	end,
	UpdateAsync = function(_, key, transform)
		local value = transform(plain[key])
		plain[key] = value
		return value
	end,
}
local dataStoreService = game:GetService("DataStoreService")
dataStoreService._methods = {
	GetOrderedDataStore = function()
		return orderedStore
	end,
	GetDataStore = function()
		return plainStore
	end,
}
local userService = game:GetService("UserService")
userService._methods = {
	GetUserInfosByUserIdsAsync = function(_, ids)
		local out = {}
		for _, id in ids do
			table.insert(out, { Id = id, Username = "user" .. id, DisplayName = "Pilot" .. id })
		end
		return out
	end,
}
local Players = game:GetService("Players")
local added, removing = {}, {}
local function signal(list)
	return { Connect = function(_, f)
		table.insert(list, f)
	end }
end
local playerList = {}
Players._methods = {
	GetPlayers = function()
		return table.clone(playerList)
	end,
	PlayerAdded = signal(added),
	PlayerRemoving = signal(removing),
	GetNameFromUserIdAsync = function(_, id)
		return "user" .. id
	end,
}
local function newPlayer(id, name)
	local p = Instance.new("Folder")
	p.Name = name
	p._methods = { UserId = id, DisplayName = name }
	p.Parent = Players
	table.insert(playerList, p)
	for _, f in added do
		f(p)
	end
	return p
end

-- Lobby mínimo con SpawnLocation (para el tablón por defecto) y suelo.
local lobby = Instance.new("Folder")
lobby.Name = "Lobby"
lobby.Parent = workspace
local spawn = Instance.new("SpawnLocation")
spawn.Name = "SpawnLocation"
spawn.Size = Vector3.new(19, 1.9, 19)
spawn.CFrame = CFrame.new(-918, 266, -4) * CFrame.Angles(0, math.rad(-90), 0)
spawn.Parent = lobby
local island = Instance.new("Part")
island.Size = Vector3.new(400, 10, 400)
island.CFrame = CFrame.new(-918, 260.8, -4)
island.Parent = lobby

-- ── Codificación ──────────────────────────────────────────────────────
local DuoLeaderboard = require(game.ServerScriptService.Glider.DuoLeaderboard)
for _, case in { { 50, 2712.345 }, { 1, 0 }, { 12, 99999.99 }, { 3, 61.5 } } do
	local score = DuoLeaderboard.encode(case[1], case[2])
	local level, time = DuoLeaderboard.decode(score)
	check("codificar " .. case[1], level == case[1] and math.abs(time - case[2]) < 0.006 and score > 0 and score < 2 ^ 31, string.format("%d → %d %.2f", score, level, time))
end
check("más nivel gana aunque sea más lento", DuoLeaderboard.encode(10, 900) > DuoLeaderboard.encode(9, 100))
check("mismo nivel: menos tiempo gana", DuoLeaderboard.encode(10, 400) > DuoLeaderboard.encode(10, 500))

-- ── Tablón y envíos ───────────────────────────────────────────────────
local alice, bob, carol = newPlayer(101, "Alice"), newPlayer(202, "Bob"), newPlayer(303, "Carol")
DuoLeaderboard.start(50)
local panel = workspace:FindFirstChild("DuoLeaderboard", true)
check("tablón por defecto creado", panel ~= nil and panel:FindFirstChild("DuoLeaderboardGui") ~= nil)
if panel then
	local toSpawn = (spawn.Position - panel.Position) * Vector3.new(1, 0, 1)
	check("el tablón mira al spawn", panel.CFrame.LookVector:Dot(toSpawn.Unit) > 0.99)
	check("el tablón está sobre el suelo", panel.Position.Y - panel.Size.Y / 2 > 265 and panel.Position.Y < 290, tostring(panel.Position))
end

local results = {}
local function submit(players, level, time)
	DuoLeaderboard.submit(players, level, time, function(improved, rank)
		table.insert(results, { improved = improved, rank = rank })
	end)
end
submit({ alice, bob }, 3, 150)
check("primer envío mejora", results[1] and results[1].improved and results[1].rank == 1)
submit({ bob, alice }, 2, 100) -- mismo dúo en otro orden, peor marca
check("marca peor no mejora", results[2] and not results[2].improved)
check("clave única del dúo", ordered["101_202"] ~= nil and ordered["202_101"] == nil)
submit({ alice, carol }, 5, 400)
check("otro dúo por delante", results[3] and results[3].improved and results[3].rank == 1)
submit({ alice }, 7, 10) -- solitario: no cuenta
check("solitario no guarda", results[4] and not results[4].improved and ordered["101"] == nil)
submit({ alice, bob }, 50, 2700)
check("terminar el recorrido sube al primer puesto", results[5] and results[5].improved and results[5].rank == 1)
submit({ alice, bob }, 50, 2800)
check("terminar más lento no mejora", results[6] and not results[6].improved)
submit({ alice, bob }, 50, 2650.25)
check("terminar más rápido mejora", results[7] and results[7].improved)

Roblox.sim.run(61) -- una vuelta del refresco
local gui = panel and panel:FindFirstChild("DuoLeaderboardGui")
local texts = {}
if gui then
	for _, d in gui:GetDescendants() do
		if d:IsA("TextLabel") and d.Text ~= "" then
			table.insert(texts, d.Text)
		end
	end
end
local joined = table.concat(texts, " | ")
check("tablón muestra el dúo y su tiempo", joined:find("Alice & Bob", 1, true) and joined:find("44:10.25", 1, true) and joined:find("FINISHED", 1, true), joined)
check("tablón muestra el segundo dúo", joined:find("Alice & Carol", 1, true) and joined:find("LVL 5", 1, true), joined)

-- ── PlayerStats con el DataStore falso ────────────────────────────────
local PlayerStats = require(game.ServerScriptService.Glider.PlayerStats)
PlayerStats.start()
local dave = newPlayer(404, "Dave")
PlayerStats.runStarted(dave)
PlayerStats.levelCleared(dave, 4)
PlayerStats.crashed(dave)
check("récord personal", PlayerStats.courseCompleted(dave, 1000) == true and PlayerStats.courseCompleted(dave, 1200) == false)
for _, f in removing do
	f(dave)
end
Roblox.sim.run(1)
local saved = plain["Player_404"]
check("PlayerStats guardado", saved and saved.HighestLevel == 4 and saved.BestTime == 1000 and saved.Runs == 1 and saved.Crashes == 1 and saved.Completions == 2, saved and string.format("%s %s %s %s %s", tostring(saved.HighestLevel), tostring(saved.BestTime), tostring(saved.Runs), tostring(saved.Crashes), tostring(saved.Completions)))

-- TutorialDone: se guarda y se combina con OR (nunca vuelve a false).
local erin = newPlayer(505, "Erin")
check("tutorial pendiente al entrar", PlayerStats.get(erin).TutorialDone == false)
PlayerStats.markTutorialDone(erin)
for _, f in removing do
	f(erin)
end
Roblox.sim.run(1)
check("TutorialDone guardado", plain["Player_505"] and plain["Player_505"].TutorialDone == true)
local loadedWith = nil
PlayerStats.onLoaded(function(player, stats)
	if player.Name == "Erin2" then
		loadedWith = stats
	end
end)
local erin2 = newPlayer(505, "Erin2")
Roblox.sim.run(1)
check("al volver, TutorialDone cargado", loadedWith and loadedWith.TutorialDone == true)
PlayerStats.runStarted(erin2)
for _, f in removing do
	f(erin2)
end
Roblox.sim.run(1)
check("OR: sigue a true tras otro guardado", plain["Player_505"].TutorialDone == true and plain["Player_505"].Runs == 1)

-- Medallas (mejor por nivel, fusión con max) y ajustes (el último cambio gana, validados).
local fran = newPlayer(606, "Fran")
Roblox.sim.run(1)
check("medalla nueva mejora", PlayerStats.medalEarned(fran, 3, 2) == true)
check("medalla peor no mejora", PlayerStats.medalEarned(fran, 3, 1) == false)
check("oro mejora la plata", PlayerStats.medalEarned(fran, 3, 3) == true)
PlayerStats.medalEarned(fran, 7, 1)
check("plumas: mejor número por nivel", PlayerStats.feathersEarned(fran, 3, 4) == true and PlayerStats.feathersEarned(fran, 3, 2) == false and PlayerStats.feathersEarned(fran, 3, 6) == true)
PlayerStats.setSettings(fran, { masterVolume = 0.3, hudScale = 9, reduceMotion = true, bogus = 1, cameraShake = "no" })
local settings = PlayerStats.get(fran).Settings
check("ajustes validados", settings.masterVolume == 0.3 and settings.hudScale == 1.25 and settings.reduceMotion == true and settings.bogus == nil and settings.cameraShake == nil)
for _, f in removing do
	f(fran)
end
Roblox.sim.run(1)
local franSaved = plain["Player_606"]
check("medallas guardadas", franSaved and franSaved.Medals and franSaved.Medals["3"] == 3 and franSaved.Medals["7"] == 1)
check("ajustes guardados", franSaved and franSaved.Settings and franSaved.Settings.masterVolume == 0.3)
local franLoaded = nil
PlayerStats.onLoaded(function(player, stats)
	if player.Name == "Fran2" then
		franLoaded = stats
	end
end)
local fran2 = newPlayer(606, "Fran2")
Roblox.sim.run(1)
check("al volver, medallas y ajustes cargados", franLoaded and franLoaded.Medals["3"] == 3 and franLoaded.Settings.reduceMotion == true)
PlayerStats.medalEarned(fran2, 7, 2)
PlayerStats.runStarted(fran2)
for _, f in removing do
	f(fran2)
end
Roblox.sim.run(1)
franSaved = plain["Player_606"]
check("plumas guardadas y fusionadas", franSaved.Feathers and franSaved.Feathers["3"] == 6)
check("fusión: medallas con max, ajustes intactos", franSaved.Medals["3"] == 3 and franSaved.Medals["7"] == 2 and franSaved.Settings.masterVolume == 0.3 and franSaved.Runs == 1)

print(if failures == 0 then "leaderboard OK" else string.format("leaderboard: %d fallos", failures))
