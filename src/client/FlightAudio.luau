--!strict
-- Sonido del vuelo (solo en este cliente). Lee los huecos de SoundConfig y los ajustes de volumen (Settings).
--   · continuos: viento (volumen y tono según velocidad y picado), roce y rasante;
--   · sueltos: FlightAudio.play("Impact") desde el HUD, los efectos o los mensajes del servidor.
-- Un hueco con id vacío no suena (se puede rellenar más tarde en SoundConfig sin tocar nada más).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Glider.GliderConfig)
local GliderMath = require(ReplicatedStorage.Glider.GliderMath)
local SoundConfig = require(ReplicatedStorage.Glider.SoundConfig)
local Settings = require(script.Parent:WaitForChild("Settings"))

local FlightAudio = {}

local group = Instance.new("SoundGroup")
group.Name = "GliderSounds"
group.Parent = SoundService

local sounds: { [string]: Sound } = {}
for name, slot in SoundConfig do
	if slot.id == "" then
		continue
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = slot.id
	sound.Volume = slot.volume
	sound.PlaybackSpeed = slot.pitch or 1
	sound.Looped = slot.loop == true
	sound.SoundGroup = group
	sound.Parent = group
	sounds[name] = sound
end

local function effectsVolume(): number
	local values = Settings.get()
	return values.masterVolume * values.effectsVolume
end

-- Sonido suelto (se superpone si ya sonaba). pitch opcional multiplica el tono base.
function FlightAudio.play(name: string, pitch: number?)
	local sound = sounds[name]
	local slot = SoundConfig[name]
	if not (sound and slot) or slot.loop then
		return
	end
	local volume = slot.volume * effectsVolume()
	if volume <= 0.001 then
		return
	end
	local copy = sound:Clone()
	copy.Volume = volume
	copy.PlaybackSpeed = (slot.pitch or 1) * (pitch or 1)
	copy.Parent = group
	copy.Ended:Once(function()
		copy:Destroy()
	end)
	copy:Play()
end

local function setLoop(name: string, level: number, pitch: number?)
	local sound = sounds[name]
	local slot = SoundConfig[name]
	if not (sound and slot) then
		return
	end
	local volume = slot.volume * level * effectsVolume()
	sound.Volume = GliderMath.approach(sound.Volume, volume, 8, 1 / 60)
	sound.PlaybackSpeed = (slot.pitch or 1) * (pitch or 1)
	if volume > 0.01 and not sound.IsPlaying then
		sound:Play()
	elseif volume <= 0.01 and sound.Volume <= 0.02 and sound.IsPlaying then
		sound:Stop()
	end
end

-- Cada fotograma mientras se vuela (glider = ala montada o nil).
function FlightAudio.update(glider: Model?)
	if not glider or glider:GetAttribute("State") ~= "Flying" then
		setLoop("Wind", 0)
		setLoop("Scrape", 0)
		setLoop("Skim", 0)
		return
	end
	local speed = glider:GetAttribute("Speed")
	local vertical = glider:GetAttribute("VerticalSpeed")
	local rush = math.clamp(((if type(speed) == "number" then speed else Config.ForwardSpeed) - 45) / 30, 0, 1)
	local dive = math.clamp(-(if type(vertical) == "number" then vertical else 0) / Config.MaxFallSpeed, 0, 1)
	setLoop("Wind", 0.5 + 0.5 * math.max(rush, dive), 0.9 + 0.35 * dive)
	setLoop("Scrape", if glider:GetAttribute("Scraping") == true then 1 else 0)
	setLoop("Skim", if glider:GetAttribute("Skimming") == true then 1 else 0)
end

return FlightAudio
