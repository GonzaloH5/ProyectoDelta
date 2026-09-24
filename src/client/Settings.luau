--!strict
-- Ajustes del jugador (cliente). Los leen la cámara, el audio, los efectos y el HUD; el panel de ajustes
-- (SettingsPanel) los cambia. El servidor los guarda con el resto de la ficha (PlayerStats.Settings) y los
-- devuelve al entrar ("Settings"), así que siguen igual en la próxima partida.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:WaitForChild("Glider"):WaitForChild("GliderRemote") :: RemoteEvent

local Settings = {}

export type Values = {
	masterVolume: number, -- 0-1
	effectsVolume: number, -- 0-1: golpes, viento, avisos
	ambienceVolume: number, -- 0-1: ambiente del bioma
	cameraShake: boolean,
	reduceMotion: boolean, -- sin alabeo de cámara, sin cambios de FOV, sin temblores ni líneas de velocidad
	hudScale: number, -- 0.8-1.25
}

Settings.DEFAULTS = table.freeze({
	masterVolume = 1,
	effectsVolume = 1,
	ambienceVolume = 0.8,
	cameraShake = true,
	reduceMotion = false,
	hudScale = 1,
})

-- Límites de cada ajuste (el servidor aplica los mismos al guardar).
Settings.RANGES = table.freeze({
	masterVolume = { 0, 1 },
	effectsVolume = { 0, 1 },
	ambienceVolume = { 0, 1 },
	hudScale = { 0.8, 1.25 },
})

local values: Values = table.clone(Settings.DEFAULTS) :: any
local changed = Instance.new("BindableEvent")
Settings.Changed = changed.Event -- (key: string, value: any)

local function sanitize(key: string, value: any): any
	local default = (Settings.DEFAULTS :: any)[key]
	if default == nil or typeof(value) ~= typeof(default) then
		return nil
	end
	local range = (Settings.RANGES :: any)[key]
	if range and type(value) == "number" then
		if value ~= value then
			return nil
		end
		return math.clamp(value, range[1], range[2])
	end
	return value
end

function Settings.get(): Values
	return values
end

-- Cambia un ajuste; save = false para no enviarlo al servidor (p. ej. al aplicar los guardados).
function Settings.set(key: string, value: any, save: boolean?)
	local clean = sanitize(key, value)
	if clean == nil or (values :: any)[key] == clean then
		return
	end
	(values :: any)[key] = clean
	changed:Fire(key, clean)
	if save ~= false then
		remote:FireServer("Settings", { [key] = clean })
	end
end

-- Ajustes guardados que manda el servidor al entrar.
function Settings.apply(saved: { [string]: any })
	for key, value in saved do
		if type(key) == "string" then
			Settings.set(key, value, false)
		end
	end
end

return Settings
