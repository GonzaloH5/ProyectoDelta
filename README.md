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
- Meta: cruzarla muestra "COURSE COMPLETE!" con el tiempo del recorrido y, en cuanto responde la clasificación,
  "NEW DUO RECORD · #N ON THE BOARD" o "NEW PERSONAL BEST!"; al aterrizar en la isla final el dúo vuelve al lobby.
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
require(game.ServerScriptService.Glider.DevTools.FlightTester:Clone()).checkTutorial() -- tutorial: novato y tranquilo ≥ 8
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
  `ridge` (colina: subir), `lintel` (viga colgada: bajar), `promontory` (saliente de pared: apartarse),
  `pillar` (pilar exento en rombo, del suelo al techo: rodearlo por el lado que marca el anillo), `guide` (anillo visual).
  Añadir un nivel = añadir una entrada a la tabla `LEVELS` de `MapBuilder.luau`.
- Estructura: `StartIsland → Level01 → RestIsland01 → … → Level50 → FinishIsland`, más `DevSpawns`.
  Entre corredores hay un valle abierto con la isla de descanso; cada corredor empieza en la boca de un acantilado.
- Cada `LevelNN` tiene `Entry`, `Exit`, `EntryPortal`, `Corridor`, `Features`, `Guides` y `Route` (línea ideal).
- Cada isla tiene `SpawnPoint` y `CheckpointZone` (marcadores listos para checkpoints futuros).
- Colores del blockout: marrón = paredes/acantilados · verde oscuro = suelo · celeste translúcido = techo · rojo = obstáculo · amarillo = guía · blanco = entrada.
- Probar un nivel suelto: atributo `DevStartLevel` (1-50) en `Workspace.Map`; las alas despegan en `DevSpawns.LevelNN`. `0` = recorrido normal.
- **Trazado en filas**: para que 50 niveles no se alejen del origen ni se crucen, los niveles 1-10 van hacia +X y cada
  pareja 11-12, 21-22, 31-32 y 41-42 gira 90° + 90°: cinco filas alternas (+X / -X) separadas ~4.000 studs
  (como mínimo ~2.000 entre paredes de filas vecinas). El resto de niveles acaba con el mismo rumbo con el que empieza.
  Total: ~177.000 studs (~49 min a 60 studs/s sin choques), ~70.000 piezas; el punto más lejano está a ~40.000 del origen.

### Los 50 niveles

| Capítulo · bioma | Niveles | Idea de cada nivel (el último combina el capítulo) |
|---|---|---|
| 1 · Pradera | 1-5 | subir y bajar · izquierda y derecha · altura + giro · curvas seguidas · subida larga |
| 2 · Cañón rojo | 6-10 | bajada larga · paso estrecho · slalom suave · correcciones rápidas · Final Test |
| 3 · Bosque otoñal | 11-15 | giro largo de 90° · colinas seguidas (+90°) · túnel bajo · slalom rápido · Autumn Trial |
| 4 · Mesetas del desierto | 16-20 | escalones de subida · bajada con vigas · zigzag subiendo y bajando · saliente antes de un paso estrecho · Mesa Run |
| 5 · Glaciar | 21-25 | giro de 90° estrecho · grieta estrecha y alta (+90°) · carámbanos (vigas seguidas) · salientes dentro de las curvas · Glacier Trial |
| 6 · Acantilados | 26-30 | picado y colina al salir · **pilares** (farallones) · colina + viga seguidas · horquillas de radio 180 · Cliff Trial |
| 7 · Selva | 31-35 | giro de 90° con pilares · vigas en curva (+90°) · colina y saliente, viga y pilar · laberinto de pilares · Jungle Trial |
| 8 · Volcán | 36-40 | tubo bajo y estrecho · subida larga con salientes · slalom de magma · espiral bajando · Volcano Trial |
| 9 · Cristal | 41-45 | giro de 90° con pilares · sala de prismas (+90°) · olas con pilares · saliente-pilar cada 250 · Crystal Trial |
| 10 · Cielo final | 46-50 | ascenso con vigas · surf (colina y viga cada ~260) · slalom en curvas · Heaven's Gauntlet · Final Flight |

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
- Los 10 biomas (cada uno con su color de acento en el HUD y en la pantalla de checkpoint):

  | Bioma | Niveles | Paredes / suelo | Obstáculos · peligro | Plantas | Fondo de los valles |
  |---|---|---|---|---|---|
  | Pradera (Meadow) | 1-5 | roca arena / césped | naranja · rojo | árboles | cascada |
  | Cañón rojo (Red Canyon) | 6-10 | terracota / arena ocre | arenisca crema · rosa | cactus y olivos | agujas de roca |
  | Bosque otoñal (Autumn Forest) | 11-15 | gris cálido / hojarasca | abedul crema · azul | árboles naranja, rojo y oro, algún pino | cascada |
  | Mesetas (Desert Mesas) | 16-20 | arenisca a franjas / arena pálida | óxido oscuro · turquesa | cactus | mesetas de cima plana |
  | Glaciar (Glacier) | 21-25 | hielo / nieve | azul glaciar · naranja | pinos nevados | seracs |
  | Acantilados (Sea Cliffs) | 26-30 | creta / mar | ocre · rojo | pinos y árboles | farallones con hierba |
  | Selva (Jungle) | 31-35 | roca con musgo / suelo oscuro | piedra de templo · magenta | palmeras | cascada turquesa |
  | Volcán (Volcano) | 36-40 | basalto / ceniza con grietas de lava | roca rojiza · azul | árboles calcinados con ascuas | cascada de lava |
  | Cristal (Crystal Caverns) | 41-45 | violeta / manchas brillantes | cristal cian · rosa | racimos de cristal | cristales gigantes |
  | Cielo final (Sky Kingdom) | 46-50 | mármol / nubes | oro · azul (anillos guía rosa) | cerezos | mar de nubes |

  El valle que precede al primer nivel de un capítulo ya usa el bioma nuevo (RestIsland05 es la isla de transición
  al Cañón rojo). Plantas y fondos de valle quedan fuera del volumen de vuelo (encima de los muros, bajo las islas).
- `DRESS_LEVELS` (en `MapBuilder.luau`) limita hasta qué nivel se viste (ahora: 50, todo el recorrido).
- Helpers low-poly compartidos con el lobby: `LowPoly.luau` (árbol, cactus, pino, palmera, cristales, árbol calcinado…).
- Regenerar los 50 niveles en Studio tarda un rato (~70.000 piezas): lanzar `build()` y guardar el place al terminar.

## Estructura

| Carpeta | En Studio | Contenido |
|---|---|---|
| `src/shared` | `ReplicatedStorage.Glider` | `GliderConfig` (todos los parámetros), `GliderMath`, `GliderRemote` |
| `src/server` | `ServerScriptService.Glider` | `GliderController` (sesiones, lobby, checkpoints), `GliderSession` (un ala + su dúo + vuelo + reaparición), `Checkpoints` (islas de descanso y meta), `Lobby` (plataformas), `RiderRig` (colgar jugadores + IK), `CollisionGroups`, `PlayerStats` (récords guardados), `DuoLeaderboard` (clasificación de dúos y tablón), `TutorialBot` (bot compañero del tutorial), `LevelStreaming`, `DevTools` (MapBuilder, MapDresser, Biomes, LobbyBuilder, LowPoly, FlightTester: solo edición) |
| `src/client` | `StarterPlayerScripts.GliderClient` | `InputAxis` (teclado/mando/táctil), `FlightHud`, `GliderCamera`, `ResetButton`, `LobbyButton`, `CheckpointBanner`, `TutorialHints` (oferta, indicaciones y SKIP del tutorial), `UiScale`, `OtherDuos` |
| `tools/sim` | — (no se sincroniza) | Imitación de Roblox para probar el mapa y el FlightTester sin Studio (ver abajo) |

## Rendimiento: carga del mapa (streaming)

Con StreamingEnabled, los niveles e islas del mapa son modelos con `ModelStreamingMode = Default`: cada cliente
recibe sus piezas poco a poco, por distancia, nunca un nivel entero de golpe. (Con `PersistentPerPlayer` o
`Atomic`, al entrar en radio llegaba el modelo completo —1.000-1.500 piezas con el vestido— y el cliente daba un
tirón al acercarse al mapa desde el lobby y en cada checkpoint.) `LevelStreaming.load` pasa a `Default` los
modelos de un mapa guardado antes de este cambio; regenerar con `MapBuilder` ya los crea así.
Cuando el ala salta de sitio (despegue o reaparición en el checkpoint), `LevelStreaming.prepare` pide cargar la
zona de destino (`RequestStreamAroundAsync`) durante la cuenta atrás. La colisión es del servidor, que siempre
tiene el mapa entero.
Recomendado en Workspace: `StreamingTargetRadius` ≈ 1024, `StreamingMinRadius` ≈ 256, `StreamOutBehavior = Opportunistic`.

## Estadísticas guardadas (DataStore)

`PlayerStats` (servidor) guarda por jugador solo **récords y contadores**, nunca por dónde iba: cada vuelo empieza
siempre en la salida.

| Dato | Qué es |
|---|---|
| `HighestLevel` | mayor nivel superado (checkpoint más alto cruzado; el total = llegó a la meta) |
| `BestTime` | mejor tiempo del recorrido completo (cronómetro `RunTime`, choques incluidos) |
| `Completions` · `Runs` · `Crashes` | recorridos terminados · vuelos empezados · choques |

- Se ven en la lista de jugadores (`leaderstats`: **Level** y **Best**) y como atributos del `Player` para la interfaz.
- Los vuelos de prueba con `DevStartLevel` no cuentan.
- Se guarda al salir, cada 2 minutos si hay cambios y al cerrar el servidor. El guardado fusiona con lo que ya hay
  (máximo, mínimo y suma), así que no se pierde nada aunque la carga falle o el jugador esté en dos servidores.
- DataStore `PlayerStats_v1`, clave `Player_<UserId>`.
- Para probarlo en Studio: *Game Settings → Security → Enable Studio Access to API Services* (el place tiene que
  estar publicado). Sin eso, el juego funciona igual y solo avisa de que no guarda.

## Tutorial con bot

- **Solo la primera vez** que alguien entra (sin `TutorialDone` en `PlayerStats`), a los pocos segundos de aparecer en el
  lobby sale una ventana: *First time flying?* → **PLAY TUTORIAL** / **NO THANKS**. Responda lo que responda, se
  guarda `TutorialDone` y no vuelve a salir. (En Studio sin API Services no se guarda: sale en cada Play.)
- **Recorrido** `Map.Tutorial` (lo genera `MapBuilder.build()`, lejos del lobby y del recorrido): tres tramos cortos
  vestidos de Pradera, cada uno con su checkpoint: **Climb** (una loma), **Dive** (una viga) y **Turn** (izquierda y
  derecha). Si chocas, repites el tramo. Al terminar: "TUTORIAL COMPLETE!" y vuelves al lobby.
- **Bot compañero** (`TutorialBot`): un personaje R15 colgado en el otro extremo de la barra.
  - Al subir y bajar hace de **espejo**: la maniobra depende de ti.
  - En los giros se **inclina** hacia el lado de la curva y tú tienes que acompañarlo.
- **Indicaciones grandes en pantalla** (`TutorialHints`, atributo `TutorialHint` del ala) y botón **SKIP TUTORIAL**.
- No cuenta para estadísticas, choques ni clasificación. La imagen de tutorial antigua queda desactivada
  (`ShowTutorialOnJoin = false`).
- Las indicaciones de cada tramo (`coach` en `TUTORIAL_LEVELS` de `MapBuilder`) se guardan en el atributo `Coach`
  del nivel: el juego no necesita los DevTools.

## Clasificación de dúos (tablón del lobby)

`DuoLeaderboard` (servidor) guarda en un OrderedDataStore la mejor marca de cada **pareja** de jugadores (vuelos de
dos desde la salida; las pruebas con `DevStartLevel` y los vuelos en solitario no cuentan):

- Puntuación = el nivel más lejano superado y, a igualdad, el menor tiempo del cronómetro al cruzarlo
  (`nivel × 10.000.000 − centésimas`). Mientras nadie termine el recorrido, manda hasta dónde llegó cada dúo; al
  terminarlo, el mejor tiempo del recorrido completo (**FINISHED**).
- Se envía en cada checkpoint (solo escribe si mejora). Clave `<UserId menor>_<UserId mayor>`: el mismo dúo cuenta
  igual vuele en el orden que vuele. OrderedDataStore `DuoBest_v1`.
- **Tablón "TOP DUOS"** con los 10 mejores (puesto, nombres, nivel, tiempo), se actualiza cada minuto y al momento
  cuando un dúo de este servidor mejora. Por defecto se crea detrás a la izquierda de la plaza, mirando al
  `SpawnLocation`. **Para colocarlo a mano:** pon en Workspace una `Part` llamada `DuoLeaderboard` donde quieras; la
  tabla sale en su cara **Front** y se adapta a su tamaño (por ejemplo 22 × 14 studs).
- En Studio necesita *Enable Studio Access to API Services*; sin eso el tablón sale vacío y lo indica.

## Controles e interfaz

| Acción | Teclado | Mando | Móvil |
|---|---|---|---|
| Moverse por la barra | A / D o flechas | gatillos L2 / R2 (también cruceta y stick) | botones grandes `<` `>` abajo a los lados |
| Volver al último checkpoint (pruebas) | R | Y | botón RESET (arriba a la derecha) |
| Volver al lobby (con confirmación) | botón LOBBY | X dos veces | botón LOBBY |

- **HUD** (`FlightHud`): nivel `LEVEL NN / total` con título, franja del color del bioma y barra de progreso
  (atributo `LevelProgress`: el servidor proyecta el ala sobre la `Route` del nivel), cronómetro del recorrido
  (`RunTime`: desde el primer despegue hasta la meta, choques incluidos), barra del ala con tu marca y la del compañero
  e indicadores CLIMB / DIVE / GLIDE y de giro, cuenta atrás "2 · 1 · GO!" y avisos de choque / meta.
  Los valores internos solo con `ShowDebug = true` en `GliderConfig`.
- **Interfaz adaptable** (`UiScale`): cada pantalla se escala respecto a 1280×720 (entre 0.6 y 1.2).

## Probar

Studio → pestaña **Test** → *Clients and Servers* → N jugadores → **Start**. Cada pareja se sube a una plataforma.
Para probar solo: `RequireBothPlayers = false` en `GliderConfig` (una persona sola en una plataforma ya despega).

### Sin Studio (`tools/sim`)

Una imitación mínima de Roblox (tipos, instancias y consultas físicas exactas para bloques, cuñas y bolas) ejecuta el
código real de `src/` fuera de Studio. Necesita Python 3 y el ejecutable `luau`
([releases de Luau](https://github.com/luau-lang/luau/releases)):

```bash
python3 tools/sim/run.py drivers/check.luau              # genera el mapa y pasa FlightTester.checkRules()
python3 tools/sim/run.py drivers/check.luau fine=true    # márgenes finos (1, 2, 3… studs) para ver la holgura
python3 tools/sim/run.py drivers/pilots.luau from=11     # los 3 pilotos en cada nivel (perfil de dificultad)
python3 tools/sim/run.py drivers/audit.luau              # regla de oro (MapDresser.audit) en todos los niveles
python3 tools/sim/run.py drivers/layout.luau             # trazado: extensión, separación entre filas y SVG
python3 tools/sim/run.py drivers/leaderboard.luau        # DuoLeaderboard y PlayerStats con DataStores falsos
python3 tools/sim/run.py drivers/tutorial.luau           # Map.Tutorial y el bot (indicaciones, espejo, giros)
python3 tools/sim/run.py drivers/selftest.luau           # pruebas de la propia imitación
```

Límites: el `Random` no es el de Roblox (el vestido aleatorio sale distinto que en Studio) y la plantilla `AlaDelta`
no está en el repo, así que se usa un ala de 32 de envergadura y 4 de alto (`span=`, `wingTop=` para cambiarla). Los
niveles 1-10, ajustados en Studio, también pasan la regla en la imitación (varios justo en el límite). Lo que decide
es `checkRules()` en Studio.
