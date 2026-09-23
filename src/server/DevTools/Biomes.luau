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
--   trunk, leaves, blossoms, flowers, bush = vegetación            water    = cascadas y charcas
--   flora       = lista de plantas grandes a sortear ("tree", "cactus")   cactus = color de los cactus
--   valleyFeature = elemento del fondo del valle ("waterfall", "hoodoos")
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

function Biomes.get(name: string?)
	return name and Biomes[name] or nil
end

-- Bioma del capítulo al que pertenece el nivel (1..50).
function Biomes.chapter(levelIndex: number)
	local chapter = math.clamp(math.ceil(levelIndex / Biomes.CHAPTER_LENGTH), 1, #Biomes.ORDER)
	return Biomes.get(Biomes.ORDER[chapter])
end

return Biomes
