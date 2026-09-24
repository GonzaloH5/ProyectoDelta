--!strict
-- Luz de cada bioma (solo en este cliente, mientras vuela). El servidor publica el bioma del nivel en curso en
-- el ala (atributo Biome) y aquí se pasa, con una transición suave, a su preset: hora del día, luz ambiente,
-- atmósfera (bruma y color del horizonte) y un toque de color. Al volver al lobby se restaura lo que había.
-- Un bioma sin preset usa DEFAULT. Retocar aquí los valores cambia el aspecto sin regenerar el mapa.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local BiomeLighting = {}

local TRANSITION = TweenInfo.new(4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local rgb = Color3.fromRGB

type Preset = {
	clock: number,
	brightness: number,
	ambient: Color3,
	outdoor: Color3,
	shiftTop: Color3,
	density: number,
	haze: number,
	glare: number,
	offset: number,
	color: Color3, -- color de la atmósfera (horizonte)
	decay: Color3, -- color lejos del sol
	tint: Color3,
	saturation: number,
	contrast: number,
}

local function preset(p: Preset): Preset
	return table.freeze(p)
end

local DEFAULT = preset({ clock = 14, brightness = 2.6, ambient = rgb(120, 128, 140), outdoor = rgb(150, 158, 170), shiftTop = rgb(255, 250, 240), density = 0.28, haze = 1.2, glare = 0.2, offset = 0.1, color = rgb(199, 220, 255), decay = rgb(106, 130, 170), tint = rgb(255, 255, 255), saturation = 0.12, contrast = 0.04 })

local PRESETS: { [string]: Preset } = {
	Pradera = DEFAULT, -- mediodía limpio
	CanonRojo = preset({ clock = 16.4, brightness = 2.7, ambient = rgb(130, 110, 100), outdoor = rgb(170, 138, 118), shiftTop = rgb(255, 225, 190), density = 0.3, haze = 1.8, glare = 0.35, offset = 0.12, color = rgb(255, 212, 172), decay = rgb(178, 112, 84), tint = rgb(255, 242, 230), saturation = 0.16, contrast = 0.06 }),
	BosqueOtonal = preset({ clock = 16, brightness = 2.4, ambient = rgb(125, 112, 100), outdoor = rgb(160, 140, 118), shiftTop = rgb(255, 230, 200), density = 0.33, haze = 2, glare = 0.25, offset = 0.12, color = rgb(255, 226, 190), decay = rgb(150, 110, 90), tint = rgb(255, 240, 222), saturation = 0.14, contrast = 0.05 }),
	MesasDesierto = preset({ clock = 13, brightness = 3.1, ambient = rgb(140, 128, 110), outdoor = rgb(178, 160, 132), shiftTop = rgb(255, 244, 220), density = 0.32, haze = 2.5, glare = 0.45, offset = 0.14, color = rgb(255, 236, 200), decay = rgb(200, 160, 118), tint = rgb(255, 246, 232), saturation = 0.1, contrast = 0.06 }),
	Glaciar = preset({ clock = 11, brightness = 2.8, ambient = rgb(128, 140, 158), outdoor = rgb(150, 166, 188), shiftTop = rgb(230, 242, 255), density = 0.35, haze = 1.5, glare = 0.3, offset = 0.1, color = rgb(212, 230, 255), decay = rgb(122, 150, 200), tint = rgb(236, 246, 255), saturation = 0.05, contrast = 0.05 }),
	Acantilados = preset({ clock = 17.3, brightness = 2.4, ambient = rgb(128, 116, 120), outdoor = rgb(168, 148, 140), shiftTop = rgb(255, 214, 170), density = 0.3, haze = 1.6, glare = 0.6, offset = 0.12, color = rgb(255, 214, 180), decay = rgb(122, 110, 160), tint = rgb(255, 236, 222), saturation = 0.14, contrast = 0.06 }),
	Selva = preset({ clock = 12.5, brightness = 2.5, ambient = rgb(110, 128, 110), outdoor = rgb(140, 162, 138), shiftTop = rgb(235, 255, 225), density = 0.4, haze = 2.4, glare = 0.2, offset = 0.1, color = rgb(202, 236, 202), decay = rgb(92, 130, 102), tint = rgb(242, 255, 240), saturation = 0.2, contrast = 0.05 }),
	Volcan = preset({ clock = 18.2, brightness = 1.9, ambient = rgb(112, 74, 64), outdoor = rgb(142, 92, 80), shiftTop = rgb(255, 150, 100), density = 0.42, haze = 2.8, glare = 0.3, offset = 0.16, color = rgb(255, 142, 104), decay = rgb(92, 42, 40), tint = rgb(255, 226, 212), saturation = 0.1, contrast = 0.1 }),
	Cristal = preset({ clock = 18.8, brightness = 1.7, ambient = rgb(118, 104, 150), outdoor = rgb(140, 122, 180), shiftTop = rgb(210, 180, 255), density = 0.32, haze = 1.4, glare = 0.2, offset = 0.12, color = rgb(202, 172, 255), decay = rgb(92, 72, 150), tint = rgb(242, 232, 255), saturation = 0.18, contrast = 0.06 }),
	CieloFinal = preset({ clock = 9, brightness = 3.1, ambient = rgb(150, 158, 175), outdoor = rgb(180, 190, 210), shiftTop = rgb(255, 250, 235), density = 0.22, haze = 0.8, glare = 0.5, offset = 0.08, color = rgb(240, 246, 255), decay = rgb(170, 190, 230), tint = rgb(250, 250, 255), saturation = 0.1, contrast = 0.03 }),
}

local active = false
local currentBiome: string? = nil
local saved: { [string]: any }? = nil
local atmosphere: Atmosphere? = nil
local createdAtmosphere = false
local grade: ColorCorrectionEffect? = nil

local LIGHTING_KEYS = { "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "ColorShift_Top" }
local ATMOSPHERE_KEYS = { "Density", "Haze", "Glare", "Offset", "Color", "Decay" }

local function begin()
	active = true
	local lighting: { [string]: any } = {}
	for _, key in LIGHTING_KEYS do
		lighting[key] = (Lighting :: any)[key]
	end
	local existing = Lighting:FindFirstChildOfClass("Atmosphere")
	createdAtmosphere = existing == nil
	atmosphere = existing or Instance.new("Atmosphere")
	local air: { [string]: any } = {}
	for _, key in ATMOSPHERE_KEYS do
		air[key] = ((atmosphere :: Atmosphere) :: any)[key]
	end
	saved = { lighting = lighting, air = air }
	if createdAtmosphere then
		(atmosphere :: Atmosphere).Parent = Lighting
	end
	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "GliderBiomeGrade"
	effect.Parent = Lighting
	grade = effect
end

-- Cambia al preset del bioma (con transición). nil = DEFAULT.
local function apply(biome: string?)
	local p = (biome and PRESETS[biome]) or DEFAULT
	TweenService:Create(Lighting, TRANSITION, {
		ClockTime = p.clock,
		Brightness = p.brightness,
		Ambient = p.ambient,
		OutdoorAmbient = p.outdoor,
		ColorShift_Top = p.shiftTop,
	}):Play()
	if atmosphere then
		TweenService:Create(atmosphere, TRANSITION, { Density = p.density, Haze = p.haze, Glare = p.glare, Offset = p.offset, Color = p.color, Decay = p.decay }):Play()
	end
	if grade then
		TweenService:Create(grade, TRANSITION, { TintColor = p.tint, Saturation = p.saturation, Contrast = p.contrast }):Play()
	end
end

local function finish()
	active = false
	currentBiome = nil
	if grade then
		grade:Destroy()
		grade = nil
	end
	local backup = saved
	if backup then
		local quick = TweenInfo.new(1.5)
		TweenService:Create(Lighting, quick, backup.lighting):Play()
		if atmosphere then
			if createdAtmosphere then
				atmosphere:Destroy()
			else
				TweenService:Create(atmosphere, quick, backup.air):Play()
			end
		end
	end
	atmosphere = nil
	saved = nil
end

-- Cada fotograma (glider = ala montada o nil).
function BiomeLighting.update(glider: Model?)
	if not glider then
		if active then
			finish()
		end
		return
	end
	if not active then
		begin()
	end
	local value = glider:GetAttribute("Biome")
	local biome = if type(value) == "string" then value else "Pradera"
	if biome ~= currentBiome then
		currentBiome = biome
		apply(biome)
	end
end

return BiomeLighting
