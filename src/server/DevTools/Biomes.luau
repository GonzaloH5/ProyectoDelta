--!nonstrict
-- Biomes: paletas y decoración de cada bioma del recorrido (datos para MapDresser). Solo modo edición.
--
-- El recorrido se divide en CAPÍTULOS de CHAPTER_LENGTH niveles; cada capítulo usa un bioma de ORDER
-- (10 biomas × 5 niveles = 50 niveles). Un nivel puede forzar otro bioma con `biome = "Nombre"` en LEVELS.
-- Un bioma que todavía no está definido aquí devuelve nil: ese tramo se queda en blockout.
--
-- Campos de cada bioma:
--   name / title = clave interna / nombre visible (pantalla de checkpoint)
--   rock        = { base de las paredes, estrato A, estrato B }   rockDark = facetas, rocas oscuras
--   ground      = suelo de corredores y valles (mortal)            patches  = manchas del suelo (solo visuales)
--   cap         = remate del borde superior (césped, nieve, arena…)
--   obstacle    = roca de acento de lomas, vigas y salientes       hazardEdge = línea Neon del borde de ataque
--   guide       = anillos guía                                     cloud    = nubes y techo
--   stone, stoneDark = arcos y carteles de entrada                 accent   = franjas de faros y remates
--   trunk, leaves, blossoms, flowers, bush = vegetación            water    = cascadas y charcas (o lava)
--   bushes      = colores de los arbustos (opcional; si no, los de leaves)   snow = nieve en los pinos (opcional)
--   flora       = lista de plantas grandes a sortear ("tree", "cactus", "pine", "palm", "crystal", "deadtree")
--   cactus      = color de los cactus
--   valleyFeature = elemento del fondo del valle: "waterfall" (cascada en una pared) o formaciones del suelo
--                   ("hoodoos" agujas, "mesas" cimas planas, "spires" seracs, "stacks" farallones con hierba,
--                   "crystals" cristales gigantes, "clouds" mar de nubes)
-- Color de acento (accent): franjas de faros, gemas del arco y el color del capítulo en el HUD y en la pantalla
-- de checkpoint. Cada bioma tiene uno distinto del anterior.
--
-- Transición: el valle que precede al primer nivel de un capítulo ya usa el bioma NUEVO (MapBuilder).

local Biomes = {}

Biomes.CHAPTER_LENGTH = 5
Biomes.ORDER = {
	"Pradera",
	"CanonRojo",
	"BosqueOtonal",
	"MesasDesierto",
	"Glaciar",
	"Acantilados",
	"Selva",
	"Volcan",
	"Cristal",
	"CieloFinal",
}

local rgb = Color3.fromRGB

Biomes.Pradera = {
	name = "Pradera",
	title = "Meadow", -- nombre visible (pantalla de checkpoint)
	rock = { rgb(186, 146, 110), rgb(160, 118, 92), rgb(214, 178, 132) },
	rockDark = rgb(128, 94, 78),
	ground = rgb(96, 190, 80),
	patches = { rgb(122, 214, 96), rgb(78, 168, 72), rgb(150, 222, 102) },
	cap = rgb(110, 215, 90),
	obstacle = rgb(240, 150, 82),
	hazardEdge = rgb(255, 84, 60),
	guide = rgb(255, 205, 50),
	cloud = rgb(250, 252, 255),
	stone = rgb(235, 225, 200),
	stoneDark = rgb(110, 75, 52),
	accent = rgb(255, 110, 95),
	trunk = rgb(135, 92, 62),
	leaves = { rgb(95, 200, 85), rgb(60, 170, 80), rgb(145, 225, 80) },
	blossoms = { rgb(255, 140, 190), rgb(255, 160, 70) },
	flowers = { rgb(255, 140, 190), rgb(255, 205, 50), rgb(255, 255, 255), rgb(165, 120, 255), rgb(255, 110, 95) },
	bush = rgb(80, 185, 80),
	water = rgb(80, 190, 255),
	flora = { "tree" },
	cactus = rgb(95, 165, 95),
	valleyFeature = "waterfall",
}

-- Cañón rojo: paredes terracota con estratos rojo oscuro/salmón, suelo de arena ocre. Los obstáculos pasan a
-- arenisca crema (resaltan contra el rojo) y el peligro a rosa Neon (no se confunde con muros ni con guías).
-- Acento turquesa (complementario). Cactus y olivos; en el fondo de los valles, agujas de roca (hoodoos).
Biomes.CanonRojo = {
	name = "CanonRojo",
	title = "Red Canyon",
	rock = { rgb(200, 98, 64), rgb(162, 66, 46), rgb(232, 148, 98) },
	rockDark = rgb(118, 52, 40),
	ground = rgb(226, 168, 98),
	patches = { rgb(242, 198, 128), rgb(204, 136, 82), rgb(172, 176, 98) },
	cap = rgb(176, 192, 86),
	obstacle = rgb(244, 214, 156),
	hazardEdge = rgb(255, 60, 120),
	guide = rgb(255, 222, 60),
	cloud = rgb(255, 249, 240),
	stone = rgb(242, 224, 192),
	stoneDark = rgb(92, 52, 38),
	accent = rgb(40, 210, 200),
	trunk = rgb(118, 80, 56),
	leaves = { rgb(140, 170, 80), rgb(105, 150, 75), rgb(178, 192, 92) },
	blossoms = { rgb(255, 120, 170), rgb(255, 190, 60) },
	flowers = { rgb(255, 120, 170), rgb(255, 200, 60), rgb(255, 255, 255), rgb(255, 140, 60) },
	bush = rgb(130, 160, 75),
	water = rgb(70, 200, 230),
	flora = { "cactus", "cactus", "tree" },
	cactus = rgb(92, 158, 92),
	valleyFeature = "hoodoos",
}

-- Bosque otoñal: roca gris cálida, suelo de hojarasca, árboles naranja/rojo/oro con algún pino. Obstáculos de
-- abedul crema con peligro azul (frío contra la paleta cálida). Acento ámbar.
Biomes.BosqueOtonal = {
	name = "BosqueOtonal",
	title = "Autumn Forest",
	rock = { rgb(150, 118, 96), rgb(126, 96, 80), rgb(176, 142, 110) },
	rockDark = rgb(98, 74, 62),
	ground = rgb(150, 120, 60),
	patches = { rgb(214, 120, 48), rgb(196, 70, 42), rgb(232, 176, 60) },
	cap = rgb(186, 160, 72),
	obstacle = rgb(238, 226, 200),
	hazardEdge = rgb(60, 200, 255),
	guide = rgb(255, 222, 60),
	cloud = rgb(255, 244, 230),
	stone = rgb(238, 222, 196),
	stoneDark = rgb(96, 64, 46),
	accent = rgb(235, 145, 35),
	trunk = rgb(104, 70, 50),
	leaves = { rgb(226, 118, 40), rgb(200, 60, 40), rgb(240, 180, 50) },
	blossoms = { rgb(170, 60, 90), rgb(250, 140, 60) },
	flowers = { rgb(255, 170, 60), rgb(220, 60, 60), rgb(255, 230, 120), rgb(150, 90, 200) },
	bush = rgb(190, 90, 40),
	water = rgb(90, 170, 220),
	flora = { "tree", "tree", "tree", "pine" },
	cactus = rgb(95, 165, 95),
	valleyFeature = "waterfall",
}

-- Mesetas del desierto: arenisca clara a franjas, arena pálida, cactus. Obstáculos de roca óxido oscura (resaltan
-- contra paredes claras) con peligro turquesa. En los valles, mesetas de cima plana. Acento violeta (atardecer).
Biomes.MesasDesierto = {
	name = "MesasDesierto",
	title = "Desert Mesas",
	rock = { rgb(214, 156, 102), rgb(190, 120, 80), rgb(236, 196, 140) },
	rockDark = rgb(150, 90, 62),
	ground = rgb(238, 206, 150),
	patches = { rgb(246, 222, 172), rgb(220, 180, 120), rgb(200, 170, 110) },
	cap = rgb(170, 150, 90),
	obstacle = rgb(128, 72, 58),
	hazardEdge = rgb(60, 230, 200),
	guide = rgb(255, 222, 60),
	cloud = rgb(255, 250, 238),
	stone = rgb(244, 228, 196),
	stoneDark = rgb(110, 70, 50),
	accent = rgb(165, 95, 210),
	trunk = rgb(130, 96, 64),
	leaves = { rgb(150, 160, 80), rgb(120, 140, 70), rgb(180, 180, 100) },
	blossoms = { rgb(255, 120, 170), rgb(255, 200, 80) },
	flowers = { rgb(255, 120, 170), rgb(255, 210, 80), rgb(255, 140, 60), rgb(255, 255, 255) },
	bush = rgb(160, 150, 80),
	water = rgb(70, 200, 230),
	flora = { "cactus", "cactus", "cactus", "tree" },
	cactus = rgb(100, 150, 90),
	valleyFeature = "mesas",
}

-- Glaciar: hielo blanco-azulado y nieve, pinos nevados y montículos de nieve. Obstáculos azul glaciar profundo con
-- peligro naranja (complementario). En los valles, seracs (agujas de hielo). Acento azul hielo.
Biomes.Glaciar = {
	name = "Glaciar",
	title = "Glacier",
	rock = { rgb(214, 230, 240), rgb(170, 205, 230), rgb(236, 244, 250) },
	rockDark = rgb(120, 150, 180),
	ground = rgb(236, 242, 248),
	patches = { rgb(206, 226, 244), rgb(250, 252, 255), rgb(180, 210, 235) },
	cap = rgb(250, 252, 255),
	obstacle = rgb(70, 120, 190),
	hazardEdge = rgb(255, 120, 40),
	guide = rgb(255, 222, 60),
	cloud = rgb(245, 250, 255),
	stone = rgb(226, 234, 242),
	stoneDark = rgb(70, 90, 120),
	accent = rgb(80, 175, 255),
	trunk = rgb(96, 70, 56),
	leaves = { rgb(40, 100, 70), rgb(30, 80, 60), rgb(60, 120, 80) },
	bushes = { rgb(240, 246, 252), rgb(220, 234, 246) },
	snow = rgb(250, 252, 255),
	blossoms = { rgb(200, 230, 255), rgb(255, 255, 255) },
	flowers = { rgb(180, 220, 255), rgb(255, 255, 255), rgb(150, 190, 255) },
	bush = rgb(230, 240, 250),
	water = rgb(140, 210, 255),
	flora = { "pine" },
	cactus = rgb(95, 165, 95),
	valleyFeature = "spires",
}

-- Acantilados: creta gris y blanca sobre el mar (el suelo es agua: se vuela sobre las olas), cimas verdes y pinos
-- azotados por el viento. Obstáculos ocre con peligro rojo. En los valles, farallones con hierba. Acento verde mar.
Biomes.Acantilados = {
	name = "Acantilados",
	title = "Sea Cliffs",
	rock = { rgb(196, 196, 184), rgb(170, 170, 160), rgb(226, 224, 212) },
	rockDark = rgb(120, 124, 120),
	ground = rgb(40, 110, 150),
	patches = { rgb(230, 245, 250), rgb(60, 140, 170), rgb(90, 170, 190) },
	cap = rgb(110, 185, 80),
	obstacle = rgb(220, 150, 80),
	hazardEdge = rgb(255, 70, 90),
	guide = rgb(255, 222, 60),
	cloud = rgb(250, 252, 255),
	stone = rgb(236, 232, 220),
	stoneDark = rgb(80, 84, 90),
	accent = rgb(20, 175, 140),
	trunk = rgb(110, 90, 70),
	leaves = { rgb(70, 150, 70), rgb(50, 130, 70), rgb(100, 170, 80) },
	blossoms = { rgb(255, 180, 200), rgb(255, 255, 255) },
	flowers = { rgb(255, 255, 255), rgb(255, 200, 60), rgb(180, 140, 255), rgb(255, 120, 150) },
	bush = rgb(80, 160, 80),
	water = rgb(80, 200, 255),
	flora = { "pine", "tree" },
	cactus = rgb(95, 165, 95),
	valleyFeature = "stacks",
}

-- Selva: roca con musgo, suelo oscuro, palmeras y árboles. Obstáculos de piedra de templo ocre con peligro magenta.
-- Cascadas turquesa en los valles. Acento verde lima.
Biomes.Selva = {
	name = "Selva",
	title = "Jungle",
	rock = { rgb(92, 112, 84), rgb(70, 92, 70), rgb(120, 140, 96) },
	rockDark = rgb(52, 70, 56),
	ground = rgb(50, 110, 50),
	patches = { rgb(90, 170, 60), rgb(40, 90, 40), rgb(140, 190, 70) },
	cap = rgb(60, 170, 60),
	obstacle = rgb(214, 170, 90),
	hazardEdge = rgb(255, 60, 200),
	guide = rgb(255, 222, 60),
	cloud = rgb(240, 250, 240),
	stone = rgb(220, 206, 160),
	stoneDark = rgb(80, 70, 50),
	accent = rgb(120, 200, 50),
	trunk = rgb(100, 76, 50),
	leaves = { rgb(40, 160, 60), rgb(20, 130, 60), rgb(110, 200, 60) },
	blossoms = { rgb(255, 80, 140), rgb(255, 160, 40) },
	flowers = { rgb(255, 80, 140), rgb(255, 200, 40), rgb(160, 90, 255), rgb(255, 120, 60) },
	bush = rgb(40, 140, 60),
	water = rgb(70, 210, 200),
	flora = { "palm", "tree", "palm" },
	cactus = rgb(95, 165, 95),
	valleyFeature = "waterfall",
}

-- Volcán: basalto casi negro, ceniza con grietas de lava (manchas naranja), árboles calcinados con ascuas y
-- cascadas de lava. Obstáculos de roca rojiza con peligro azul (frío contra lo caliente). Acento rojo lava.
Biomes.Volcan = {
	name = "Volcan",
	title = "Volcano",
	rock = { rgb(70, 64, 66), rgb(54, 50, 52), rgb(96, 86, 84) },
	rockDark = rgb(36, 32, 34),
	ground = rgb(58, 50, 50),
	patches = { rgb(255, 110, 30), rgb(220, 60, 20), rgb(90, 80, 80) },
	cap = rgb(110, 100, 100),
	obstacle = rgb(205, 95, 55),
	hazardEdge = rgb(80, 220, 255),
	guide = rgb(255, 222, 60),
	cloud = rgb(205, 190, 185),
	stone = rgb(120, 110, 105),
	stoneDark = rgb(40, 34, 34),
	accent = rgb(240, 70, 30),
	trunk = rgb(50, 44, 44),
	leaves = { rgb(70, 60, 60), rgb(90, 70, 60), rgb(60, 50, 50) },
	bushes = { rgb(80, 70, 70), rgb(100, 80, 70) },
	blossoms = { rgb(255, 120, 40), rgb(255, 200, 60) },
	flowers = { rgb(255, 120, 40), rgb(255, 200, 60), rgb(255, 80, 40) },
	bush = rgb(70, 60, 60),
	water = rgb(255, 110, 20),
	flora = { "deadtree" },
	cactus = rgb(95, 165, 95),
	valleyFeature = "waterfall",
}

-- Cristal: roca violeta con suelo de manchas brillantes, racimos de cristales cian y rosa. Obstáculos de cristal
-- cian con peligro rosa. En los valles, cristales gigantes. Acento magenta.
Biomes.Cristal = {
	name = "Cristal",
	title = "Crystal Caverns",
	rock = { rgb(88, 70, 130), rgb(70, 56, 110), rgb(120, 96, 170) },
	rockDark = rgb(50, 40, 84),
	ground = rgb(60, 48, 96),
	patches = { rgb(120, 230, 255), rgb(255, 120, 220), rgb(90, 70, 140) },
	cap = rgb(140, 110, 200),
	obstacle = rgb(120, 230, 240),
	hazardEdge = rgb(255, 90, 170),
	guide = rgb(255, 222, 60),
	cloud = rgb(235, 225, 255),
	stone = rgb(210, 200, 240),
	stoneDark = rgb(60, 44, 100),
	accent = rgb(225, 70, 200),
	trunk = rgb(80, 64, 110),
	leaves = { rgb(120, 230, 255), rgb(255, 130, 220), rgb(180, 140, 255) },
	blossoms = { rgb(255, 255, 255), rgb(120, 230, 255) },
	flowers = { rgb(120, 230, 255), rgb(255, 130, 220), rgb(200, 170, 255), rgb(255, 255, 255) },
	bush = rgb(150, 120, 220),
	water = rgb(150, 120, 255),
	flora = { "crystal" },
	cactus = rgb(95, 165, 95),
	valleyFeature = "crystals",
}

-- Cielo final: mármol blanco y oro sobre un mar de nubes, cerezos en flor. Obstáculos dorados con peligro azul y,
-- solo aquí, anillos guía rosa (el oro de los obstáculos se confundiría con el amarillo). Acento oro.
Biomes.CieloFinal = {
	name = "CieloFinal",
	title = "Sky Kingdom",
	rock = { rgb(240, 236, 226), rgb(220, 212, 196), rgb(250, 246, 236) },
	rockDark = rgb(190, 180, 160),
	ground = rgb(230, 240, 255),
	patches = { rgb(255, 255, 255), rgb(210, 225, 250), rgb(245, 235, 210) },
	cap = rgb(160, 220, 130),
	obstacle = rgb(230, 180, 60),
	hazardEdge = rgb(60, 170, 255),
	guide = rgb(255, 110, 200),
	cloud = rgb(255, 255, 255),
	stone = rgb(255, 250, 235),
	stoneDark = rgb(170, 140, 80),
	accent = rgb(240, 190, 40),
	trunk = rgb(150, 120, 100),
	leaves = { rgb(255, 190, 220), rgb(255, 230, 240), rgb(200, 230, 160) },
	blossoms = { rgb(255, 160, 200), rgb(255, 255, 255) },
	flowers = { rgb(255, 200, 230), rgb(255, 255, 255), rgb(200, 180, 255), rgb(255, 230, 150) },
	bush = rgb(220, 240, 200),
	water = rgb(120, 210, 255),
	flora = { "tree" },
	cactus = rgb(95, 165, 95),
	valleyFeature = "clouds",
}

function Biomes.get(name: string?)
	return name and Biomes[name] or nil
end

-- Bioma del capítulo al que pertenece el nivel (1..50).
function Biomes.chapter(levelIndex: number)
	local chapter = math.clamp(math.ceil(levelIndex / Biomes.CHAPTER_LENGTH), 1, #Biomes.ORDER)
	return Biomes.get(Biomes.ORDER[chapter])
end

return Biomes
