# ProyectoDelta — ala delta cooperativa

## Sincronizar con Roblox Studio (Rojo 7.7)

```bash
rojo serve
```

En Studio: pestaña **Plugins → Rojo → Connect** (localhost:34872). Todo lo que edites en `src/` se refleja al instante.
El mapa (Workspace, incluidos `AlaDelta` y `Lobby`) vive en el archivo del place, no en esta carpeta: guarda el place desde Studio.

## Ciclo de juego

Lobby → dos jugadores sobre una plataforma `DuoPad` → cuenta atrás → se clona un ala para ese dúo en la salida
→ vuelan → cada **isla de descanso es un checkpoint** → al chocar, el mismo dúo reaparece en su último checkpoint
→ botón **LOBBY** (cualquiera de los dos, con confirmación) o aterrizar tras la meta → el dúo vuelve al lobby.
Si uno de los dos se va del juego o muere, la partida se cancela y el otro vuelve al lobby (igual que el botón).
El juego está en **inglés** (textos de interfaz, carteles, títulos de nivel y de bioma); el código y sus comentarios, en español.

- **Checkpoints** (`src/server/Checkpoints.luau`): al cruzar la `CheckpointZone` de `RestIslandNN` (o la línea de meta,
  con el ancho de todo el valle) ambos ven la pantalla de checkpoint (`CheckpointBanner`): nivel superado, el siguiente,
  progreso en rombos, color del bioma y aviso de bioma nuevo. Desde ahí reaparecen tras chocar, a la altura de vuelo
  sobre la isla. El botón **RESET (R)** (pruebas) también vuelve al último checkpoint.
- Meta: cruzarla muestra "COURSE COMPLETE!"; al aterrizar en la isla final el dúo vuelve al lobby.
- Los atributos `BiomeTitle` y `BiomeColor` de cada isla los escribe `MapBuilder`: tras cambiar biomas, regenerar el mapa.

- `Workspace.AlaDelta` es la **plantilla**: marca dónde y con qué forma sale cada ala. Al empezar el juego se guarda en ServerStorage.
- `Workspace.Lobby` contiene las plataformas (Parts llamadas `DuoPad`) y el `SpawnLocation`. Lo genera `LobbyBuilder` (ver abajo).

## Lobby (blockout low-poly)

`Workspace.Lobby` se genera con `src/server/DevTools/LobbyBuilder.luau`. En Studio, modo edición, barra de comandos:

```lua
require(game.ServerScriptService.Glider.DevTools.LobbyBuilder:Clone()).build()    -- regenera el lobby
```

- Se diseña en un marco propio (`CENTER`, `LOOK_AT`, escala 1) y al final se escala `SCALE` y se lleva a `PLACEMENT`:
  la colocación elegida a mano en Studio (medida con error 0). `SPAWN_SIZE` y `DROP_DECOR` reproducen los retoques
  a mano (spawn más grande; árboles, arbustos y rocas sustituidos por modelos propios sueltos en Workspace).
- **No pisa trabajo a mano:** si `Workspace.Lobby` no está exactamente como se generó (atributo `GeneratedParts`),
  `build()` se niega; `build({ force = true })` lo reemplaza y guarda el anterior en `ServerStorage.DevReferencias.LobbyViejo`.
  Los modelos sueltos en Workspace (decoración propia) no se tocan nunca.
- Estructura: `Island`, `Plaza` (`SpawnLocation` + molino `Landmark`), `DuoTerrace` (4 `DuoPad` con arco y mini ala),
  `Paths`, `Decor` (árboles, rocas, arbustos, flores, farolillos, manga de viento), `Satellites` (3 islitas, puentes, cascada), `Clouds`.
- Las plataformas siguen llamándose `DuoPad`: `Lobby.luau` no cambia. Las mini alas son clones de `AlaDelta` a escala 0.6, sin colisión.
- Semilla fija: regenerar da siempre el mismo lobby. Se cambia editando los números del archivo, no a mano.
- Un `Lobby` antiguo (sin atributo `Generated`) y los `SpawnLocation` sueltos en Workspace se guardan en
  `ServerStorage.DevReferencias.LobbyViejo` en vez de borrarse.
- También aplica la iluminación global: `Lighting.LobbyVibrance` (saturación +0.15, contraste +0.05) y `Atmosphere.Density = 0.2`.
- Alas y jugadores de distintos dúos no chocan entre sí; cada cliente ve a los otros dúos semitransparentes.

## Mapa (blockout)

`Workspace.Map` se genera con `src/server/DevTools/MapBuilder.luau` (no se edita a mano mientras sea blockout).
En Studio, modo edición, barra de comandos:

```lua
require(game.ServerScriptService.Glider.DevTools.MapBuilder:Clone()).build()      -- regenera el mapa
require(game.ServerScriptService.Glider.DevTools.FlightTester:Clone()).runAll()   -- piloto automático (novato / tranquilo / completo)
require(game.ServerScriptService.Glider.DevTools.FlightTester:Clone()).checkRules() -- regla de dificultad (from, to opcionales)
```

**Regla de dificultad** (`FlightTester.RULES`, la comprueba `checkRules()`): cada tramo exige que ciertos pilotos
lleguen a la salida sin que el ala, inflada N studs por cada lado, toque nada (el techo no cuenta).

| Niveles | Tiene que pasar | Margen mínimo |
|---|---|---|
| 1-10 (capítulos 1-2: aprender) | novato y tranquilo | novato ≥ 4 · tranquilo ≥ 8 |
| 11-25 (capítulos 3-5: practicar) | tranquilo | ≥ 4 |
| 26-50 (capítulos 6-10: dominar) | completo (el tranquilo puede fallar) | ≥ 4 |

Además (de diseño, no lo mide el piloto): ≥ 2 s de vuelo (120 studs) entre dos obstáculos, como mucho una idea nueva
por nivel, y el último nivel de cada capítulo combina las ideas del capítulo.

- Cada nivel es un **corredor guiado**: paredes laterales y suelo (mortales) + techo semitransparente (se roza, limita la altura).
- El trazado se escribe como órdenes (`straight`, `arc`, `rise`, `width`, `height`, `mark`) y los obstáculos van dentro:
  `ridge` (colina: subir), `lintel` (viga colgada: bajar), `promontory` (saliente de pared: apartarse), `guide` (anillo visual).
  Añadir un nivel = añadir una entrada a la tabla `LEVELS` de `MapBuilder.luau`.
- Estructura: `StartIsland → Level01 → RestIsland01 → … → Level10 → FinishIsland`, más `DevSpawns`.
  Entre corredores hay un valle abierto con la isla de descanso; cada corredor empieza en la boca de un acantilado.
- Cada `LevelNN` tiene `Entry`, `Exit`, `EntryPortal`, `Corridor`, `Features`, `Guides` y `Route` (línea ideal).
- Cada isla tiene `SpawnPoint` y `CheckpointZone` (marcadores listos para checkpoints futuros).
- Colores del blockout: marrón = paredes/acantilados · verde oscuro = suelo · celeste translúcido = techo · rojo = obstáculo · amarillo = guía · blanco = entrada.
- Probar un nivel suelto: atributo `DevStartLevel` (1-10) en `Workspace.Map`; las alas despegan en `DevSpawns.LevelNN`. `0` = recorrido normal.

### Vestido visual (biomas)

`MapBuilder.build()` viste cada nivel/valle con `MapDresser` usando el bioma de su capítulo (`Biomes.luau`):
capítulos de 5 niveles, 10 biomas → 50 niveles. Un nivel puede forzar su bioma con `biome = "Nombre"` en `LEVELS`.
Todo lo añadido va en la carpeta `Dressing` de cada modelo (atributo `Dressing = true`); el trazado y los obstáculos no cambian.

```lua
require(game.ServerScriptService.Glider.DevTools.MapBuilder:Clone()).build({ dress = false })  -- blockout puro
require(game.ServerScriptService.Glider.DevTools.MapDresser:Clone()).audit(workspace.Map.Level01) -- regla de oro
```

- **Regla de oro: lo que se ve sólido, choca.** Estratos y facetas de paredes/obstáculos son sólidos y sobresalen
  ≤ `SKIN_MAX` (4 studs); rocas y arbustos del suelo del corredor solo en la franja de 20 studs junto a las
  paredes (≤ 12 de alto).
  Nubes del techo, manchas del suelo, agua y líneas de peligro son solo visuales. `audit` lo mide desde la `Route`.
- Techo = capa de nubes: la losa (la colisión que se roza) brilla suave como base del mar de nubes, y cada
  ~150 studs de recorrido cuelga una nube grande low-poly (3 placas giradas en dos pisos, panza azulada). Obstáculos en roca de acento + línea Neon
  en el borde de ataque. Entrada con arco de piedra y cartel "NIVEL NN". Islas hexagonales con faro.
- Biomas definidos: **Pradera** (niveles 1-5) y **Cañón rojo** (6-10: paredes terracota, arenisca crema en los
  obstáculos, peligro en rosa Neon, cactus y agujas de roca en los valles). El valle que precede al primer nivel
  de un capítulo ya usa el bioma nuevo (RestIsland05 es la isla de transición al Cañón rojo).
- `DRESS_LEVELS` (en `MapBuilder.luau`) limita hasta qué nivel se viste (ahora: 10, todo el recorrido).
- Helpers low-poly compartidos con el lobby: `LowPoly.luau`.

## Estructura

| Carpeta | En Studio | Contenido |
|---|---|---|
| `src/shared` | `ReplicatedStorage.Glider` | `GliderConfig` (todos los parámetros), `GliderMath`, `GliderRemote` |
| `src/server` | `ServerScriptService.Glider` | `GliderController` (sesiones, lobby, checkpoints), `GliderSession` (un ala + su dúo + vuelo + reaparición), `Checkpoints` (islas de descanso y meta), `Lobby` (plataformas), `RiderRig` (colgar jugadores + IK), `CollisionGroups`, `DevTools` (MapBuilder, MapDresser, Biomes, LobbyBuilder, LowPoly, FlightTester: solo edición) |
| `src/client` | `StarterPlayerScripts.GliderClient` | input A/D, `GliderCamera`, `StatusLabel`, `ResetButton`, `LobbyButton`, `CheckpointBanner`, `OtherDuos` |

## Probar

Studio → pestaña **Test** → *Clients and Servers* → N jugadores → **Start**. Cada pareja se sube a una plataforma.
Para probar solo: `RequireBothPlayers = false` en `GliderConfig` (una persona sola en una plataforma ya despega).
