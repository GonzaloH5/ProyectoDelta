-- Avisos visuales por capas (MapBuilder ctx.telegraphs / ctx.curveSigns / ctx.guide; los anima
-- src/client/TelegraphVisuals): en todos los niveles y en Flight School comprueba que
--   · cada marcador Cue (paso con aviso cercano) tiene ≥ 2 luces en secuencia y la primera a ≥ 120 studs (2 s;
--     hasta 260 si no hay otro obstáculo justo antes: las luces nunca se ponen dentro de otro obstáculo);
--   · ninguna luz de aviso toca un obstáculo (nunca tapan un hueco ni se confunden con él);
--   · cada curva comprometida (atributo CommittedCurves) tiene ≥ 2 paneles de curva;
--   · las pruebas de capítulo (5, 10, 15…) van con avisos mínimos y el resto, completos;
--   · cada aro guía tiene su velo de luz.
local MapBuilder = require(game.ServerScriptService.Glider.DevTools.MapBuilder:Clone())
MapBuilder.build({ dress = ARGS.dress == true })
local map = workspace.Map
local failures, checked = 0, 0
local function fail(level: Instance, message: string)
	failures += 1
	print("FALLA", level:GetFullName():gsub("^Workspace%.Map%.", ""), message)
end

local overlap = OverlapParams.new()
local function checkLevel(level: Instance, index: number?)
	checked += 1
	local telegraphs = level:FindFirstChild("Telegraphs")
	local lights, cues, signs = {}, {}, 0
	if telegraphs then
		for _, part in telegraphs:GetChildren() do
			local group = part:GetAttribute("TelegraphGroup")
			if group then
				lights[group] = lights[group] or {}
				table.insert(lights[group], part)
			elseif part:GetAttribute("CueU") ~= nil then
				cues[tonumber(part.Name:match("%d+"))] = part
			elseif part.Name == "CurveSign" then
				signs += 1
			end
		end
	end
	for group, cue in cues do
		local list = lights[group] or {}
		local orders, farthest = {}, 0
		for _, light in list do
			orders[light:GetAttribute("TelegraphOrder")] = true
			local flat = (light.Position - cue.Position) * Vector3.new(1, 0, 1)
			farthest = math.max(farthest, flat.Magnitude)
		end
		local count = 0
		for _ in orders do
			count += 1
		end
		if count < 2 or farthest < 115 then
			fail(level, string.format("Cue%02d: %d luces, la más lejana a %.0f studs", group, count, farthest))
		end
		for _, light in list do
			for _, hit in workspace:GetPartsInPart(light, overlap) do
				if hit:GetAttribute("Kind") == "Obstacle" then
					fail(level, string.format("Cue%02d: una luz toca %s", group, hit.Name))
					break
				end
			end
		end
	end
	local curves = level:GetAttribute("CommittedCurves") or 0
	if signs < 2 * curves then
		fail(level, string.format("%d curvas comprometidas y solo %d paneles", curves, signs))
	end
	if index then
		local want = if index % 5 == 0 then "minimal" else "full"
		if level:GetAttribute("TelegraphLevel") ~= want then
			fail(level, string.format("TelegraphLevel %s (se esperaba %s)", tostring(level:GetAttribute("TelegraphLevel")), want))
		end
	end
	local guides = level:FindFirstChild("Guides")
	local rings, veils = 0, 0
	if guides then
		for _, child in guides:GetChildren() do
			if child.Name:match("^GapVeil") then
				veils += 1
			elseif child.Name:match("^Ring%d") then
				rings += 1
			end
		end
	end
	if veils < rings then
		fail(level, string.format("%d aros guía y %d velos", rings, veils))
	end
	return #(function()
		local t = {}
		for k in cues do
			table.insert(t, k)
		end
		return t
	end)(), signs
end

local totalCues, totalSigns = 0, 0
local index = 1
while map:FindFirstChild(string.format("Level%02d", index)) do
	local cues, signs = checkLevel(map[string.format("Level%02d", index)], index)
	totalCues += cues
	totalSigns += signs
	index += 1
end
if map:FindFirstChild("Tutorial") then
	checkLevel(map.Tutorial.Level01, nil)
end
print(string.format("%d niveles · %d pasos con aviso · %d paneles de curva", checked, totalCues, totalSigns))
print(if failures == 0 then "Avisos: todo OK" else string.format("Avisos: %d fallos", failures))
