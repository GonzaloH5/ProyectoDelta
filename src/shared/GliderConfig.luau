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
	RespawnCountdown = 1, -- segundos colgados al reaparecer tras perder el ala (o con Respawn)
	CrashPauseTime = 0.6, -- segundos de caída (voltereta) tras perder el ala antes de reaparecer
	LandingTime = 2.5, -- segundos que el ala se desliza sobre la isla de meta antes de volver al lobby
	ResetCooldown = 1, -- segundos mínimos entre dos pulsaciones del botón Respawn (de cualquier jugador)
	ShowDebug = false, -- true = muestra valores de Lift/Balance/velocidad en pantalla

	-- ── Avance (nunca desaparece durante el vuelo) ─────────────────────
	ForwardSpeed = 60, -- studs/s
	-- Inercia suave: en picado se gana algo de velocidad, subiendo se pierde un poco (false = siempre 60).
	MomentumEnabled = true,
	MomentumDive = 0.15, -- +15 % de avance con la caída máxima
	MomentumClimb = 0.08, -- −8 % con la subida máxima
	SpeedResponse = 1.5, -- rapidez con que el avance vuelve a su objetivo (1/s), también tras un golpe

	-- ── Balanceo (impulso con Espacio / A / botón PUMP) ────────────────
	-- Balancearse gasta energía (compartida por el dúo) y da avance extra: uno +35 %, los dos a la vez +70 %.
	-- Más rápido = curvas más abiertas y golpes más fuertes: es un riesgo que se elige.
	PumpBoostOne = 0.35,
	PumpBoostBoth = 0.70,
	BoostResponse = 3, -- rapidez con que se gana el avance extra (1/s)
	EnergyDrainPerRider = 0.2, -- energía/s que gasta cada uno que se balancea (llena = 1)
	EnergyRecharge = 0.08, -- energía/s que se recupera sin balancearse
	EnergyRingBonus = 0.35, -- energía que da cada anillo de impulso
	RingBurst = 0.2, -- impulso extra durante RingBurstTime al cruzar un anillo
	RingBurstTime = 1,
	FeatherRadius = 12, -- studs del ala a los que se recoge una pluma
	RiderPumpSwing = 20, -- grados de balanceo del cuerpo al impulsarse
	RiderPumpRate = 6, -- rad/s del columpio

	-- ── Corrientes del mapa (updraft, downdraft, viento lateral) ───────
	WindEdge = 25, -- studs de cada borde de la zona en los que la corriente entra y sale suave

	-- ── Sustentación (sale de la separación entre ambos jugadores) ─────
	-- LiftInput = 0 juntos en el mínimo de separación … 1 cada uno en un extremo
	MaxFallSpeed = 30, -- studs/s de caída con LiftInput = 0 (ambos en el centro)
	MaxClimbSpeed = 26, -- studs/s de subida con LiftInput = 1 (ambos en los extremos)
	NeutralLiftPoint = 0.5, -- LiftInput que mantiene la altura
	LiftDeadzone = 0.06, -- alrededor del punto neutro no se sube ni se baja ("más o menos" = nivelado)
	LiftCurve = 1.0, -- 1 = lineal (antes 0,55: muy brusco cerca del punto neutro); >1 = aún más tranquilo
	VerticalResponse = 5, -- rapidez con que la velocidad vertical persigue su objetivo (1/s)

	-- ── Balance / giro (sale del centro de masa de ambos jugadores) ────
	-- BalanceInput > 0: el peso está desplazado a la izquierda; < 0: a la derecha
	BalanceDeadzone = 0.08, -- un desequilibrio pequeño no gira (hace de compensador: nadie tiene que estar exacto)
	BalanceCurve = 1.15, -- >1 = giros suaves con poco desequilibrio, completos al irse los dos a un lado (antes 0,7)
	MaxRoll = 45, -- grados de alabeo con desequilibrio total
	RollResponse = 8, -- frecuencia del muelle de alabeo (rad/s): más alto = más rápido
	RollDamping = 0.6, -- <1 = algo de rebote al llegar y al soltar, sin el tambaleo de antes (0,45)
	MaxTurnRate = 68, -- grados/s de giro de rumbo con alabeo máximo
	TurnResponse = 8, -- rapidez con que el giro sigue al alabeo (1/s)

	-- ── Pitch (feedback visual de subir/bajar) ─────────────────────────
	MaxPitch = 24, -- grados de nariz arriba/abajo con subida/caída máxima
	PitchResponse = 7, -- frecuencia del muelle de pitch (rad/s)
	PitchDamping = 0.45, -- rebote de la nariz al cambiar de subir a bajar

	-- ── Corrientes de aire suaves (math.noise) ─────────────────────────
	WindFlowStrength = 1, -- 0 = sin viento; multiplica todas las amplitudes
	WindFlowSpeed = 0.3, -- frecuencia del ruido (lento = corriente, rápido = vibración)
	WindPitchAmplitude = 0.75, -- grados
	WindRollAmplitude = 1, -- grados
	WindVerticalAmplitude = 0.5, -- studs/s

	-- ── Jugadores en la barra ──────────────────────────────────────────
	-- Cada jugador puede recorrer toda la barra, de extremo a extremo, y no chocan entre sí.
	PlayerSlideSpeed = 13, -- studs/s de desplazamiento por la barra
	PlayerSlideResponse = 20, -- aceleración del deslizamiento (alto = arranca y frena en seco)
	StartOutward = 0.5, -- separación inicial de cada uno hacia su lado (0.5 = vuelo nivelado)
	BarInnerOffset = 1.1, -- cada uno a menos de esto del centro ya cuenta como "centrado" (studs)
	BarOuterOffset = 4.9, -- distancia máxima al centro de la barra (studs)
	HangDepth = 3.3, -- studs entre la barra y el HumanoidRootPart
	HangBack = 0.35, -- studs que el cuerpo queda detrás de la barra
	HangLean = 6, -- grados que el torso se inclina hacia adelante
	HandSpacing = 0.85, -- distancia de cada mano al centro del jugador sobre la barra
	RiderSlideSwing = 12, -- grados que el cuerpo se balancea hacia atrás al deslizarse a toda velocidad
	RiderRollSwing = 0.5, -- fracción del alabeo del ala que el cuerpo compensa (cuelga más vertical)

	-- ── Contactos (GliderPhysics): tocar algo no es morir ──────────────
	-- El ala resbala por la superficie. Un golpe fuerte o un roce largo quitan un corazón; sin corazones se pierde
	-- el ala y se reaparece en el último punto seguro. Suelos y tops nunca quitan corazones.
	WingHearts = 2,
	ImpactSpeed = 18, -- studs/s de velocidad CONTRA la superficie que cuentan como golpe (≈17° a 60 studs/s)
	ScrapeDamageTime = 1.2, -- segundos de roce seguidos que cuestan un corazón
	InvulnerableTime = 1.5, -- segundos sin daño tras perder un corazón (el ala parpadea)
	ContactPush = 10, -- studs/s de empujón de separación al tocar
	ContactPushDecay = 4, -- rapidez con que se desvanece ese empujón (1/s)
	ContactSteer = 0.5, -- fracción del giro hacia la dirección de la superficie en cada contacto
	HarmlessNormalY = 0.7, -- superficies con la normal más vertical que esto son "suelo" (sin daño)
	HitboxSpanFactor = 0.75, -- el núcleo que choca es más estrecho que el ala (las puntas perdonan)
	HitboxFeetFactor = 0.7, -- y más corto por debajo (los pies de los jugadores perdonan)
	FloorCushion = 3, -- studs sobre el suelo a los que el ala empieza a levantarse sola
	FloorCushionStiffness = 4, -- fuerza del cojín (studs/s de subida por stud de hundimiento)
	SkimGap = 8, -- studs sobre el suelo que cuentan como "rasante" (polvo en el cliente)
	GroundClearance = 2.5, -- studs bajo los pies que cuentan como "tocar suelo" (aterrizaje en la meta)
	FeetBelowRoot = 6.3, -- aprox. distancia barra→pies de un personaje colgado
	ObstacleProbeDistance = 3, -- studs extra de detección hacia delante
	KillHeight = -40, -- si el ala baja de esta Y, se pierde

	-- ── Puntos seguros (reaparición) ───────────────────────────────────
	SafePointInterval = 8, -- cada cuántos segundos de vuelo se guarda un punto seguro
	SafePointCleanTime = 3, -- segundos sin tocar nada necesarios para guardarlo
	SafePointMargin = 10, -- studs libres alrededor del ala para que el punto sea seguro

	-- ── Asistencia (el servidor ayuda a seguir la línea ideal) ─────────
	-- Solo actúa cuando nadie gira fuerte: se suma al giro de los jugadores, nunca lo anula.
	AssistTurnFraction = 0.35, -- fracción del giro necesario que aporta la asistencia
	AssistInputThreshold = 0.3, -- con un giro de los jugadores por encima de esto, la asistencia se retira
	AssistLookahead = 120, -- studs por delante sobre la línea ideal a los que apunta
	AssistFullUntilLevel = 10, -- capítulos 1-2: asistencia completa
	AssistEndLevel = 26, -- desde el capítulo 6: sin asistencia (se desvanece entre medias)
	WindAssistAfterCrashes = 3, -- alas perdidas en el mismo nivel para activar el "viento a favor"
	WindAssistTurnFraction = 0.6, -- asistencia de giro con viento a favor
	WindAssistVertical = 6, -- studs/s de ayuda vertical hacia la línea ideal con viento a favor

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
	CameraRouteLookahead = 150, -- studs de línea ideal por delante que el servidor publica (RouteAhead)
	CameraRouteBlend = 0.35, -- fracción del ángulo hacia la línea ideal que la cámara mira de más (anticipa curvas)
	CameraRouteMaxAngle = 20, -- grados máximos de esa anticipación
	CameraVerticalLead = 0.45, -- studs que el punto de mira se adelanta por cada stud/s de subida o bajada
	CameraMaxFovBoost = 8, -- grados máximos de FOV extra (el picado ya no abre la cámara sin límite)
	CameraMaxFovDrop = 4, -- grados máximos de FOV menos al subir
	CameraBoostFov = 12, -- grados máximos de FOV extra con el impulso
	CameraCollisionRadius = 2, -- studs de separación con paredes y techos entre la cámara y el ala
	CameraPullInResponse = 20, -- rapidez al acercarse por una pared (alta: nunca se ve a través)
	CameraReleaseResponse = 3, -- rapidez al volver a su distancia
	CameraShakeImpact = 0.8, -- studs de temblor al perder un corazón
	CameraShakeScrape = 0.2, -- studs de temblor mientras roza
	CameraShakeDecay = 6, -- rapidez con que se calma el temblor (1/s)

	-- ── Avisos rápidos al compañero (teclas 1-5) ───────────────────────
	Callouts = table.freeze({ "Climb!", "Dive!", "Left!", "Right!", "Nice!" }),
	CalloutCooldown = 0.8, -- segundos mínimos entre dos avisos del mismo jugador

	-- ── Ajustes del jugador (panel de ajustes; se guardan en PlayerStats.Settings) ─────────
	SettingsDefaults = table.freeze({
		masterVolume = 1, -- 0-1
		effectsVolume = 1, -- 0-1: golpes, viento, avisos
		ambienceVolume = 0.8, -- 0-1: ambiente del bioma
		cameraShake = true,
		reduceMotion = false, -- sin alabeo de cámara, cambios de FOV, temblores ni líneas de velocidad
		hudScale = 1,
	}),
	SettingsRanges = table.freeze({
		masterVolume = { 0, 1 },
		effectsVolume = { 0, 1 },
		ambienceVolume = { 0, 1 },
		hudScale = { 0.8, 1.25 },
	}),

	-- ── Red ────────────────────────────────────────────────────────────
	MaxInputsPerSecond = 30, -- el servidor ignora mensajes por encima de esto
	StateBroadcastInterval = 0.1, -- s entre actualizaciones de atributos de depuración
}

return table.freeze(GliderConfig)
