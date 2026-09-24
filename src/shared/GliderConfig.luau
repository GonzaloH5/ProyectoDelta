--!strict
-- Todos los parámetros ajustables del ala delta cooperativa.
-- Servidor y cliente leen de aquí: no hay números mágicos en los scripts.

local GliderConfig = {
	-- ── Modelo ─────────────────────────────────────────────────────────
	GliderName = "AlaDelta", -- Model en Workspace
	BarPartName = "Agarre", -- barra horizontal a la que se agarran
	NosePartName = "AlaPunta", -- opcional: pieza que marca "hacia adelante" (si no existe, se deduce del modelo)

	GliderFolderName = "Gliders", -- carpeta de Workspace donde se crea un ala por dúo

	-- ── Lobby y dúos ───────────────────────────────────────────────────
	LobbyFolderName = "Lobby", -- carpeta de Workspace con las plataformas de dúo
	DuoPadName = "DuoPad", -- nombre de cada plataforma (Part) dentro de esa carpeta
	PadCountdown = 3, -- segundos con el dúo sobre la plataforma antes de ir a volar
	PadDetectHeight = 8, -- studs por encima de la plataforma que cuentan como "estar encima"
	LobbyTickInterval = 0.1, -- segundos entre revisiones de las plataformas
	OtherDuoTransparency = 0.35, -- transparencia con la que ves alas y jugadores de otros dúos

	-- ── Tutorial ───────────────────────────────────────────────────────
	ShowTutorialOnJoin = false, -- imagen de tutorial al unirse (la sustituye el tutorial jugable con bot)
	TutorialImageId = "rbxassetid://102857509779424",
	TutorialImageAspect = 1023 / 576, -- ancho / alto de la imagen

	-- ── Estelas de viento en las puntas del ala ────────────────────────
	TrailEnabled = true,
	TrailWidth = 0.7, -- studs de ancho de cada estela
	TrailLifetime = 0.6, -- segundos que dura la estela detrás del ala
	TrailColor = Color3.fromRGB(235, 245, 255),
	TrailCalmTransparency = 0.35, -- vuelo tranquilo: estela suave
	TrailIntenseTransparency = 0, -- giro fuerte o picado: estela marcada

	-- ── Sesión de vuelo ────────────────────────────────────────────────
	RequireBothPlayers = true, -- false = permite volar con 1 solo jugador (pruebas)
	CountdownTime = 2, -- segundos colgados en la salida antes de despegar
	CrashPauseTime = 1.5, -- segundos congelados tras chocar antes de volver al lobby
	ResetCooldown = 1, -- segundos mínimos entre dos pulsaciones del botón Reset (de cualquier jugador)
	ShowDebug = false, -- true = muestra valores de Lift/Balance/velocidad en pantalla

	-- ── Avance (nunca desaparece durante el vuelo) ─────────────────────
	ForwardSpeed = 60, -- studs/s

	-- ── Sustentación (sale de la separación entre ambos jugadores) ─────
	-- LiftInput = 0 juntos en el mínimo de separación … 1 cada uno en un extremo
	MaxFallSpeed = 30, -- studs/s de caída con LiftInput = 0 (ambos en el centro)
	MaxClimbSpeed = 26, -- studs/s de subida con LiftInput = 1 (ambos en los extremos)
	NeutralLiftPoint = 0.5, -- LiftInput que mantiene la altura
	LiftCurve = 0.55, -- <1 = arcade: un pequeño cambio de separación ya da mucha subida/bajada
	VerticalResponse = 5, -- rapidez con que la velocidad vertical persigue su objetivo (1/s)

	-- ── Balance / giro (sale del centro de masa de ambos jugadores) ────
	-- BalanceInput > 0: el peso está desplazado a la izquierda; < 0: a la derecha
	BalanceCurve = 0.7, -- <1 = arcade: un desequilibrio pequeño ya se nota
	MaxRoll = 45, -- grados de alabeo con desequilibrio total
	RollResponse = 8, -- frecuencia del muelle de alabeo (rad/s): más alto = más rápido
	RollDamping = 0.45, -- <1 = rebote al llegar y al soltar (tambaleo divertido)
	MaxTurnRate = 68, -- grados/s de giro de rumbo con alabeo máximo
	TurnResponse = 6, -- rapidez con que el giro sigue al alabeo (1/s)

	-- ── Pitch (feedback visual de subir/bajar) ─────────────────────────
	MaxPitch = 24, -- grados de nariz arriba/abajo con subida/caída máxima
	PitchResponse = 7, -- frecuencia del muelle de pitch (rad/s)
	PitchDamping = 0.45, -- rebote de la nariz al cambiar de subir a bajar

	-- ── Corrientes de aire suaves (math.noise) ─────────────────────────
	WindFlowStrength = 1, -- 0 = sin viento; multiplica todas las amplitudes
	WindFlowSpeed = 0.3, -- frecuencia del ruido (lento = corriente, rápido = vibración)
	WindPitchAmplitude = 1.5, -- grados
	WindRollAmplitude = 2, -- grados
	WindVerticalAmplitude = 1, -- studs/s

	-- ── Jugadores en la barra ──────────────────────────────────────────
	-- Cada jugador puede recorrer toda la barra, de extremo a extremo, y no chocan entre sí.
	PlayerSlideSpeed = 10, -- studs/s de desplazamiento por la barra
	PlayerSlideResponse = 20, -- aceleración del deslizamiento (alto = arranca y frena en seco)
	StartOutward = 0.5, -- separación inicial de cada uno hacia su lado (0.5 = vuelo nivelado)
	BarInnerOffset = 1.1, -- cada uno a menos de esto del centro ya cuenta como "centrado" (studs)
	BarOuterOffset = 4.9, -- distancia máxima al centro de la barra (studs)
	HangDepth = 3.3, -- studs entre la barra y el HumanoidRootPart
	HangBack = 0.35, -- studs que el cuerpo queda detrás de la barra
	HangLean = 6, -- grados que el torso se inclina hacia adelante
	HandSpacing = 0.85, -- distancia de cada mano al centro del jugador sobre la barra

	-- ── Colisión mínima (fin del vuelo) ────────────────────────────────
	GroundClearance = 2.5, -- studs bajo los pies que cuentan como "tocar suelo"
	FeetBelowRoot = 6.3, -- aprox. distancia barra→pies de un personaje colgado
	ObstacleProbeDistance = 3, -- studs extra de detección hacia delante
	KillHeight = -40, -- si el ala baja de esta Y, el vuelo termina

	-- ── Techo (se roza, nunca es choque) ───────────────────────────────
	CeilingClearance = 1, -- studs que el punto más alto del ala queda por debajo del techo
	CeilingProbeDistance = 15, -- studs por encima del ala en los que se busca techo
	CeilingStiffness = 10, -- rapidez con que frena la subida al acercarse (alto = tope más seco)

	-- ── Estabilidad física ─────────────────────────────────────────────
	AlignResponsiveness = 120,
	MaxDeltaTime = 1 / 30, -- el paso de simulación nunca supera esto

	-- ── Cámara ─────────────────────────────────────────────────────────
	CameraDistance = 22, -- studs detrás del ala
	CameraHeight = 7, -- studs por encima del ala
	CameraLookAhead = 30, -- studs por delante a los que mira
	CameraFocusDrop = 2, -- baja el foco para encuadrar ala + jugadores
	CameraSmoothness = 6, -- rapidez con que la cámara sigue el rumbo (1/s)
	CameraVerticalSmoothness = 4, -- rapidez con que sigue la altura (1/s): deja ver el tirón
	CameraRollFactor = 0.2, -- fracción del alabeo del ala que copia la cámara
	CameraMaxRoll = 7, -- grados máximos de alabeo de cámara
	CameraRollResponse = 5, -- suavizado del alabeo de cámara (1/s)
	CameraFieldOfView = 72,
	CameraDiveFovBoost = 0.5, -- grados de FOV extra por cada stud/s de caída (sensación de picado)
	CameraClimbFovDrop = 0.2, -- grados de FOV menos por cada stud/s de subida
	CameraFovResponse = 4, -- suavizado del cambio de FOV (1/s)
	CameraTrackCorrection = 6, -- rapidez con que la predicción local se corrige hacia la posición real (1/s)
	CameraSnapDistance = 25, -- si la predicción se aleja más que esto (reset), la cámara salta

	-- ── Red ────────────────────────────────────────────────────────────
	MaxInputsPerSecond = 30, -- el servidor ignora mensajes por encima de esto
	StateBroadcastInterval = 0.1, -- s entre actualizaciones de atributos de depuración
}

return table.freeze(GliderConfig)
