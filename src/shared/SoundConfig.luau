--!strict
-- Sonidos del vuelo (los reproduce FlightAudio en el cliente). Cada hueco lleva un id de sonido:
--   · "rbxasset://sounds/…" = sonidos que vienen con Roblox (sirven de provisional y funcionan ya);
--   · "" = hueco vacío: no suena nada hasta que pongas uno tuyo ("rbxassetid://123456789", de la Toolbox
--     o subido por ti; tiene que ser público o tuyo/del grupo del juego).
-- volume = volumen base (0-1, luego se multiplica por los ajustes del jugador) · pitch = tono base.
-- loop = suena sin parar mientras dura (el viento sube con la velocidad; el roce solo mientras roza).

export type Slot = { id: string, volume: number, pitch: number?, loop: boolean? }

local SoundConfig: { [string]: Slot } = {
	-- Continuos
	Wind = { id = "rbxasset://sounds/action_falling.mp3", volume = 0.35, pitch = 0.8, loop = true }, -- sube con la velocidad y el picado
	Scrape = { id = "", volume = 0.5, loop = true }, -- mientras el ala roza una pared
	Skim = { id = "", volume = 0.35, loop = true }, -- rasante sobre el suelo

	-- Vuelo
	Countdown = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5, pitch = 1 }, -- 3 · 2 · 1
	Go = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.6, pitch = 1.5 }, -- ¡despegue!
	Impact = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.9, pitch = 0.7 }, -- pierde un corazón
	Bounce = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.7, pitch = 0.6 }, -- rebote contra arenisca ("boing")
	CueUp = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.3, pitch = 1.6 }, -- aviso: hay que subir
	CueDown = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.3, pitch = 0.9 }, -- aviso: hay que bajar
	CueSide = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.25, pitch = 1.25 }, -- aviso: hay que girar
	GateBeep = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.25, pitch = 2.1 }, -- compuerta: bip… bip… ¡ya!
	WingLost = { id = "", volume = 0.8 }, -- sin corazones: el ala se pierde
	Respawn = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.35, pitch = 0.75 }, -- reaparece
	NearMiss = { id = "rbxasset://sounds/swordlunge.wav", volume = 0.5, pitch = 1.1 }, -- "Close!"
	InSync = { id = "", volume = 0.4 }, -- los dos se mueven a la vez
	Boost = { id = "rbxasset://sounds/swordlunge.wav", volume = 0.5, pitch = 0.8 }, -- empieza el impulso (más agudo con ×2)
	Ring = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5, pitch = 1.8 }, -- anillo de impulso
	Feather = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.35, pitch = 2.4 }, -- pluma recogida
	Callout = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.3, pitch = 2 }, -- aviso del compañero

	-- Logros
	Checkpoint = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.7, pitch = 1.25 },
	Medal = { id = "", volume = 0.7 }, -- medalla de oro/plata/bronce en el checkpoint
	ChapterClear = { id = "", volume = 0.8 }, -- último nivel de un capítulo
	Finish = { id = "", volume = 0.9 }, -- meta
	Landing = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.6, pitch = 1 }, -- toca la isla de meta

	-- Interfaz
	Click = { id = "", volume = 0.4 },
}

return SoundConfig
