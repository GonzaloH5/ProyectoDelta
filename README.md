# ProyectoDelta — ala delta cooperativa

## Sincronizar con Roblox Studio (Rojo 7.7)

```bash
rojo serve
```

En Studio: pestaña **Plugins → Rojo → Connect** (localhost:34872). Todo lo que edites en `src/` se refleja al instante.
El mapa (Workspace, incluidos `AlaDelta` y `Lobby`) vive en el archivo del place, no en esta carpeta: guarda el place desde Studio.

## Ciclo de juego

Lobby → dos jugadores sobre una plataforma `DuoPad` → cuenta atrás → se clona un ala para ese dúo en la salida
→ vuelan → cada **isla de descanso es un checkpoint** → los golpes quitan **corazones** (2); sin corazones el ala se
pierde y el mismo dúo reaparece en su último **punto seguro** → botón **LOBBY** (cualquiera de los dos, con
confirmación) o aterrizar tras la meta → el dúo vuelve al lobby (pantalla de resultados).
Si uno de los dos se va del juego o muere, la partida se cancela y el otro vuelve al lobby (igual que el botón).
El juego está en **inglés** (textos de interfaz, carteles, títulos de nivel y de bioma); el código y sus comentarios, en español.

- **Checkpoints** (`src/server/Checkpoints.luau`): al cruzar la `CheckpointZone` de `RestIslandNN` (o la línea de meta,
  con el ancho de todo el valle) ambos ven la pantalla de checkpoint (`CheckpointBanner`): nivel superado, el siguiente,
  progreso en rombos, color del bioma, aviso de bioma nuevo, **medalla** del nivel y "CHAPTER N CLEAR!" al terminar
  un capítulo. Los corazones se rellenan en cada checkpoint. El botón **RESPAWN (R)** vuelve al último punto seguro.
- Meta: cruzarla muestra "COURSE COMPLETE!" con el tiempo del recorrido y, en cuanto responde la clasificación,
  "NEW DUO RECORD · #N ON THE BOARD" o "NEW PERSONAL BEST!"; el ala **aterriza** en la pista de la isla final, se
  desliza hasta pararse y el dúo vuelve al lobby, donde ve la **pantalla de resultados** (tiempo, medallas, alas
  perdidas, golpes y puesto) con botón CONTINUE. Tras la meta el HUD pide aterrizar; si en 12 s
  (`FinishLandTimeout`) no han aterrizado, vuelven al lobby igualmente.
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
require(game.ServerScriptService.Glider.DevTools.FlightTester:Clone()).runAll()   -- piloto automático (novato·juego / tranquilo / completo)
require(game.ServerScriptService.Glider.DevTools.FlightTester:Clone()).checkRules() -- regla de dificultad (from, to opcionales)
require(game.ServerScriptService.Glider.DevTools.FlightTester:Clone()).checkTutorial() -- tutorial: novato y tranquilo ≥ 8
```

**Regla de dificultad** (`FlightTester.RULES`, la comprueba `checkRules()`). El piloto vuela con las mismas
ecuaciones que el juego (`GliderPhysics`) en dos modos:
- **estricto**: el ala entera, inflada N studs por cada lado, no puede tocar nada (el techo no cuenta); sin
  corazones, sin asistencia y sin viento. Mide la holgura de diseño.
- **juego** (`·j`): como en el juego de verdad (contactos que resbalan, 3 corazones, asistencia del nivel, puntos
  seguros). Mide si un dúo llega sin perder el ala y con cuántos golpes.

| Niveles | Tiene que pasar |
|---|---|
| 1-10 (capítulos 1-2: aprender) | completo estricto ≥ 8 · novato en el juego con ≤ 1 golpe (sin perder el ala) |
| 11-25 (capítulos 3-5: practicar) | novato en el juego con ≤ 1 golpe · tranquilo estricto ≥ 4 |
| 26-50 (capítulos 6-10: dominar) | completo estricto ≥ 4 · tranquilo en el juego sin golpes |

Los pilotos vuelan con las corrientes del nivel, y en los niveles con obstáculos móviles cada piloto vuela con
**4 desfases** del reloj: tiene que pasar con todos (ningún móvil mata sin remedio).

En las **bifurcaciones** (`RouteB`) cada piloto vuela los dos carriles. El **ritmo** (algo que hacer cada 2,5-5 s,
nunca más de ~5 s sin nada en los capítulos 1-2) lo mide `tools/sim/drivers/pacing.luau`. La gramática completa
(verbos de la barra, piezas, estructura de un nivel, fichas de los niveles 1-10) está en
**[docs/DISENO_NIVELES.md](docs/DISENO_NIVELES.md)**: es la base para rehacer los niveles 11-50.

- Cada nivel es un **corredor guiado**: paredes laterales y suelo + techo translúcido (se roza, limita la altura).
  Antes de cada obstáculo, dos **chevrones** luminosos apuntan hacia donde hay que ir; la salida tiene un marco luminoso.
- El trazado se escribe como órdenes (`straight`, `arc`, `rise`, `width`, `height`, `mark`) y los obstáculos van dentro:
  `lintel` (viga colgada: bajar), `barrier` (muro desde el suelo: subir), `window` (pared con un hueco desplazado:
  apuntar a un cuadrante), `divider` (bifurcación en dos carriles válidos), `promontory` (saliente de pared: apartarse),
  `pillar` (pilar exento en rombo: rodearlo), `ridge` (rampa: el suelo te sube, inofensiva) y `guide` (anillo visual).
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
  Total: ~174.000 studs (~48 min a 60 studs/s sin choques ni impulso), ~77.000 piezas; el punto más lejano está a ~38.000 del origen.

### Los 50 niveles

| Capítulo · bioma | Niveles | Idea de cada nivel (el último combina el capítulo) |
|---|---|---|
| 1 · Pradera ("Juntos") | 1-5 | Up & Under (vigas y muros) · Swap (curvas y chicane) · Windows (¿quién se mueve?) · The Chimney (corriente gigante) · Split Decision (bifurcación) |
| 2 · Cañón rojo ("El cañón empuja") | 6-10 | The Big Drop (caída y túnel; llega el impulso) · Crosswind (viento y ráfagas) · Swinging Logs · Heavy Air (descendentes) · Canyon Trial |
| 3 · Bosque otoñal | 11-15 | giro largo de 90° · colinas seguidas (+90°) · **compuertas** · slalom rápido · Autumn Trial |
| 4 · Mesetas del desierto | 16-20 | escalones con corriente · bajada con vigas y **corrientes descendentes** · zigzag · saliente antes de un paso estrecho · Mesa Run |
| 5 · Glaciar | 21-25 | giro de 90° con viento · grieta con corriente (+90°) · carámbanos y **aspas** · salientes dentro de las curvas · Glacier Trial |
| 6 · Acantilados | 26-30 | picado y colina al salir · **pilares** (farallones) · colina + viga seguidas · horquillas de radio 180 · Cliff Trial |
| 7 · Selva | 31-35 | giro de 90° con pilares · vigas en curva (+90°) · colina y saliente, viga y pilar · laberinto de pilares · Jungle Trial |
| 8 · Volcán | 36-40 | tubo bajo y estrecho · subida larga con salientes · slalom de magma · espiral bajando · Volcano Trial |
| 9 · Cristal | 41-45 | giro de 90° con pilares · sala de prismas (+90°) · olas con pilares · saliente-pilar cada 250 · Crystal Trial |
| 10 · Cielo final | 46-50 | ascenso con vigas · surf (colina y viga cada ~260) · slalom en curvas · Heaven's Gauntlet · Final Flight |

Capítulos 6-10: además, 2-4 elementos nuevos por nivel (`CHAPTER_EXTRAS`: troncos, compuertas, aspas, corrientes, anillos y plumas).

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
- Regenerar los 50 niveles en Studio tarda un rato (~77.000 piezas): lanzar `build()` y guardar el place al terminar.

## Estructura

| Carpeta | En Studio | Contenido |
|---|---|---|
| `src/shared` | `ReplicatedStorage.Glider` | `GliderConfig` (todos los parámetros), `GliderPhysics` (ecuaciones de vuelo, contactos y corazones: servidor, FlightTester y sim), `GliderMath`, `SoundConfig` (huecos de sonido), `GliderRemote` |
| `src/server` | `ServerScriptService.Glider` | `GliderController` (sesiones, lobby, checkpoints), `GliderSession` (un ala + su dúo + vuelo + reaparición), `Checkpoints` (islas de descanso y meta), `Lobby` (plataformas), `RiderRig` (colgar jugadores + IK), `CollisionGroups`, `PlayerStats` (récords, medallas y ajustes guardados), `DuoLeaderboard` (clasificación de dúos y tablón), `TutorialBot` (bot compañero del tutorial), `LevelStreaming`, `Analytics` (eventos del Creator Dashboard), `DevTools` (MapBuilder, MapDresser, Biomes, LobbyBuilder, LowPoly, FlightTester: solo edición) |
| `src/client` | `StarterPlayerScripts.GliderClient` | `InputAxis` (teclado/mando/táctil), `FlightHud`, `GliderCamera`, `ResetButton` (Respawn), `LobbyButton`, `CheckpointBanner`, `ResultsScreen`, `Callouts` (avisos al compañero), `FlightAudio`, `FlightEffects`, `BiomeLighting`, `Backdrop`, `Ambient`, `ScreenFade`, `Settings` + `SettingsPanel`, `TutorialHints` (oferta, indicaciones y SKIP del tutorial), `UiScale`, `OtherDuos` |
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
| `BestTime` | mejor tiempo del recorrido completo (cronómetro `RunTime`, reapariciones incluidas) |
| `Completions` · `Runs` · `Crashes` | recorridos terminados · vuelos empezados · alas perdidas |
| `Medals` | mejor medalla de cada nivel (oro = sin golpes · plata = sin perder el ala · bronce = superado) |
| `Settings` | ajustes del jugador (volúmenes, temblor de cámara, reducir movimiento, tamaño del HUD) |

- Se ven en la lista de jugadores (`leaderstats`: **Level** y **Best**) y como atributos del `Player` para la interfaz.
- Los vuelos de prueba con `DevStartLevel` no cuentan.
- Se guarda al salir, cada 2 minutos si hay cambios y al cerrar el servidor. El guardado fusiona con lo que ya hay
  (máximo, mínimo y suma; medallas con máximo por nivel; ajustes: el último cambio gana), así que no se pierde nada
  aunque la carga falle o el jugador esté en dos servidores.
- DataStore `PlayerStats_v1`, clave `Player_<UserId>`.
- Para probarlo en Studio: *Game Settings → Security → Enable Studio Access to API Services* (el place tiene que
  estar publicado). Sin eso, el juego funciona igual y solo avisa de que no guarda.

## Flight School (tutorial, ~40 s)

- Es el **nivel 0**. Si alguno de los dos del dúo no tiene `TutorialDone`, el dúo despega en `Map.Tutorial`.
  Al salir, fundido y el ala aparece en la salida del recorrido con una cuenta atrás de 3 s: **nivel 1 sin volver
  al lobby**. El cronómetro, las medallas y la clasificación empiezan en el nivel 1. `TutorialDone` se guarda
  para los dos.
- **Un solo corredor**: bajar (puente) → subir (muro) → izquierda → cambio a la derecha → combo sin ayudas.
- **Indicaciones**: una palabra por tramo ("DIVE!", "CLIMB!"…) y **marcas fantasma** en la barra del HUD, que
  indican dónde ponerse cada uno (`GhostLeft` / `GhostRight`, calculadas con `TutorialBot.ghosts`).
- **Modo práctica** (`session.practice`): los golpes no quitan corazones, son un "BONK!" (atributo `Bonks`). Si el
  ala se queda casi parada más de 2 s (`PracticeStuckTime`), ayuda el viento a favor. Nadie se queda atascado.
- **SKIP** en dúo: hace falta que lo pulsen los dos (`SkipVotes`), y se salta al nivel 1.
- **Solo con el Coach**: la primera vez que alguien entra, mientras busca pareja, se le ofrece "Practice with the
  Coach". Es el mismo nivel: el Coach (`TutorialBot`) hace su mitad y resbala una vez en el combo. Al terminar,
  aterriza y vuelve al lobby.
- Las indicaciones (`coach` en `TUTORIAL_LEVELS` de `MapBuilder`) se guardan en el atributo `Coach` del nivel.
- No cuenta para estadísticas ni clasificación.

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
| Balancearse (impulso) | Espacio | A | botón ⇑ (sobre el botón derecho) |
| Reaparecer en el último punto seguro | R | Y | botón RESPAWN (arriba a la derecha) |
| Avisos al compañero (Climb · Dive · Left · Right · Nice) | 1 · 2 · 3 · 4 · 5 | cruceta ↑ · ↓ · L1 · R1 · B | botón 💬 |
| Volver al lobby (con confirmación) | botón LOBBY | X dos veces | botón LOBBY |
| Ajustes | botón ⚙ (izquierda) | — | botón ⚙ |

- **HUD** (`FlightHud`): tarjeta `LEVEL NN / total` con título, franja del color del bioma y barra de progreso
  (atributo `LevelProgress`), que se encoge unos segundos después de empezar cada nivel; tarjeta grande "LEVEL NN ·
  título" al empezar cada nivel; **corazones** arriba al centro (parpadean al perder uno); cronómetro compacto
  (`RunTime`); barra del ala con tu marca y la del compañero, **flechas de hacia dónde se mueve cada uno** e
  "IN SYNC!" cuando os movéis a la vez; indicadores CLIMB / DIVE / GLIDE y de giro; cuenta atrás "2 · 1 · GO!".
  Los valores internos solo con `ShowDebug = true` en `GliderConfig`.
- **Ajustes** (`SettingsPanel`, botón ⚙): volumen general, efectos y ambiente, temblor de cámara, reducir movimiento
  (sin alabeo de cámara, cambios de FOV, temblores ni líneas de velocidad) y tamaño del HUD. Se guardan en `PlayerStats`.
- **Interfaz adaptable** (`UiScale`): cada pantalla se escala respecto a 1280×720 (entre 0.6 y 1.2) × tamaño del HUD.

## Balanceo, corrientes, anillos, plumas y obstáculos móviles

- **Balanceo (impulso)**: se presenta en el **nivel 6** (`PumpFromLevel`). Antes, y en Flight School, solo cuenta la
  barra: la energía y el botón ⇑ no aparecen. Mientras se mantiene Espacio (A / botón ⇑) el jugador se columpia en
  la barra y el ala acelera: **+35 %** si se balancea uno, **+70 %** si se balancean los dos. Gasta la **energía** del dúo (barra bajo
  los corazones; los dos a la vez ≈ 2,5 s), que se recarga planeando, con los **anillos azules** y en cada checkpoint.
  Más rápido = curvas más abiertas y golpes más fuertes: es un riesgo que se elige (y mejora el tiempo).
- **Corrientes** (`ctx.updraft / downdraft / crosswind` en `MapBuilder`, zonas en `LevelNN.Wind`): la ascendente
  (turquesa) sube y permite pasar lomas más altas de lo que el ala sube sola; la descendente (violeta) hunde; el viento
  lateral (blanco) empuja hacia una pared. Las partículas muestran hacia dónde soplan.
- **Anillos de impulso** (`ctx.boostRing`, aro azul circular): cruzarlos da energía y un empujón corto; van en líneas algo arriesgadas.
- **Plumas** (`ctx.feathers`): gemas doradas en líneas ajustadas; se recogen pasando cerca. Contador en el HUD, en el
  checkpoint (★ con todas) y en los resultados; se guarda el mejor número por nivel (`PlayerStats.Feathers`).
- **Obstáculos móviles** (`Movers.luau`): **troncos** que se balancean (por debajo siempre se pasa), **compuertas** que
  abren y cierran (nunca del todo) y **aspas** giratorias (las esquinas quedan libres). Su posición es una función del
  reloj compartido: el servidor mueve colisionadores invisibles (`MoverService`) y cada cliente dibuja la copia
  visual con la misma fórmula (`MoverVisuals`), así se ven suaves y coinciden con lo que choca.
- **Niveles**: los capítulos 1-2 siguen la gramática de `docs/DISENO_NIVELES.md` (un nivel = una idea con
  identidad). Los capítulos 3-5 van al 75 % de sección. En los capítulos 6-10, `ctx.autoExtras` reparte 2-4
  elementos por nivel según `CHAPTER_EXTRAS`.
- **Valles**: corto (~6 s) entre niveles de un mismo capítulo y largo (~10 s) al cambiar de capítulo.

## Sensación de vuelo (lo que perdona el juego)

Todo el vuelo está en `GliderPhysics` (compartido): el servidor, el `FlightTester` y `tools/sim` usan las mismas
ecuaciones. Los números, en `GliderConfig`.

- **Mandos legibles**: respuesta lineal con zona muerta (estar "más o menos" nivelados = vuelo recto y a la misma
  altura), alabeo sin tambaleo, viento suave, deslizamiento por la barra más rápido.
- **Tocar no es morir**: el ala resbala a lo largo de paredes y obstáculos. Un golpe fuerte (≈23° o más contra la
  superficie) o un roce largo (1,5 s) quitan **1 de 2 corazones** y dan 1,5 s de invulnerabilidad. Suelos y tops de
  obstáculos nunca quitan corazones (el ala se levanta sola sobre el suelo). El núcleo que choca es un 75 % del ala.
- **Sin corazones**: voltereta corta (0,6 s), fundido y reaparición en el último **punto seguro** (checkpoint o un
  tramo de vuelo limpio de los últimos ~8 s, despejado y mirando a la línea ideal) con cuenta atrás de 1 s.
- **Asistencia**: el servidor suma un poco de giro hacia la línea ideal cuando nadie gira fuerte (completa en los
  capítulos 1-2, se desvanece hasta el 6). Tras 3 alas perdidas en un nivel, **viento a favor**: más asistencia y
  ayuda para subir o bajar hasta el siguiente checkpoint.
- **Inercia suave**: en picado se gana algo de velocidad y subiendo se pierde un poco (`MomentumEnabled`).
- **Cámara** (`GliderCamera`): anticipa las curvas (mira un poco hacia la línea ideal que viene, atributo
  `RouteAhead`) y las subidas/bajadas, nunca atraviesa paredes ni techos, FOV con tope y temblor al golpear.
- **Aterrizaje** en la meta: el ala toca la pista de la isla, se desliza y se para.

## Sonido, efectos y ambiente

- **Sonidos** (`SoundConfig` + `FlightAudio`): cada hueco lleva un id. Vienen puestos sonidos de Roblox como
  provisionales (viento, cuenta atrás, golpe, "Close!", checkpoint, aterrizaje); los huecos vacíos (`""`: roce,
  rasante, ala perdida, medalla, capítulo, meta, clic…) no suenan hasta que pongas ids tuyos (`rbxassetid://…`).
- **Efectos** (`FlightEffects`): chispas al golpear y rozar, polvo rasante y al aterrizar, "Close!" al pasar muy cerca
  sin tocar, parpadeo del ala invulnerable, burbuja al reaparecer, columna de luz y confeti en cada checkpoint,
  líneas de velocidad al picar y remolinos en las puntas en giros fuertes. Los cuerpos se balancean en la barra.
- **Luz por bioma** (`BiomeLighting`): hora del día, bruma y color del horizonte de cada bioma, con transición; al
  volver al lobby se restaura la del place. Los presets están al principio del archivo.
- **Fondo y vida** (`Backdrop`, `Ambient`): montañas y nubes en el horizonte del color del bioma; polen, hojas,
  nieve, brasas o destellos alrededor de la cámara y pájaros en los valles abiertos (menos con calidad gráfica baja).
- **Mapa** (`MapDresser`): bordes dentados en lo alto de las paredes, puerta de capítulo (estandarte y mástiles) en
  el primer nivel de cada capítulo, un hito con bandera en cada isla y pista de aterrizaje con cartel FINISH en la meta.
  Tras actualizar, **regenera el mapa** con `MapBuilder.build()` para verlos (y los ajustes de los niveles 1, 9, 10 y
  del tramo DIVE del tutorial).

## Analytics

`Analytics` (servidor) manda eventos al Creator Dashboard (*Analytics*): embudo de entrada (entra → se le ofrece el
tutorial → responde → lo termina o salta → primer vuelo en dúo → primer checkpoint), progresión por nivel (empieza /
supera, con golpes y alas perdidas), alas perdidas por nivel y recorridos completados. Los vuelos de prueba y el
tutorial no cuentan como progresión. Si el servicio falla, el juego sigue igual.

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
python3 tools/sim/run.py drivers/sloppy.luau             # dúo descuidado en el juego: golpes y alas perdidas por nivel
python3 tools/sim/run.py drivers/sloppy.luau pump=true   # lo mismo balanceándose en las rectas (impulso)
python3 tools/sim/run.py drivers/trace.luau level=10 pilot=novicej offset=0.9   # traza un vuelo (y cada golpe)
python3 tools/sim/run.py drivers/audit.luau              # regla de oro (MapDresser.audit) en todos los niveles
python3 tools/sim/run.py drivers/layout.luau             # trazado: extensión, separación entre filas y SVG
python3 tools/sim/run.py drivers/leaderboard.luau        # DuoLeaderboard y PlayerStats (medallas, ajustes) con DataStores falsos
python3 tools/sim/run.py drivers/tutorial.luau           # Map.Tutorial y el bot (indicaciones, rumbo, colocación)
python3 tools/sim/run.py drivers/tutorialflight.luau     # vuela Flight School con el Coach (player=full|lift|idle) o duo=true
python3 tools/sim/run.py drivers/pacing.luau             # ritmo de cada nivel y cronología de los primeros 5 minutos
python3 tools/sim/run.py drivers/selftest.luau           # pruebas de la propia imitación
```

Límites: el `Random` no es el de Roblox (el vestido aleatorio sale distinto que en Studio) y la plantilla `AlaDelta`
no está en el repo, así que se usa un ala de 32 de envergadura y 4 de alto (`span=`, `wingTop=` para cambiarla).
Lo que decide es `checkRules()` en Studio.
