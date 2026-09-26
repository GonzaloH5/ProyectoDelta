# Wingmates — guía de diseño de niveles

La mecánica central: **dos personas, un ala**. Cada nivel existe para crear situaciones en las que los dos
tengan que coordinarse, hablar y reaccionar. Prioridades: **divertido > difícil · coordinación > complejidad ·
situaciones nuevas > mecánicas nuevas · identidad > cantidad de obstáculos**.

Esta guía es la base para rehacer los niveles 11-50 con el mismo estándar que Flight School y los niveles 1-10.

## 1. Los verbos (posición de cada jugador: 0 = centro, ½ = medio, 1 = extremo)

| Verbo | Izq | Der | Resultado | Lo que se grita |
|---|---|---|---|---|
| Planear | ½ | ½ | recto, misma altura | "¡quietos!" |
| Bajar | 0 | 0 | picado de 30 studs/s | "¡al centro!" |
| Subir | 1 | 1 | subida de 26 studs/s | "¡fuera los dos!" |
| Girar fuerte | 1 | 0 | giro máximo (radio ~50) **sin cambiar de altura** | "¡todo a la izquierda!" |
| Giro subiendo (izq.) | 1 | ½ | medio giro + media subida: **se mueve uno solo** | "¡tú no te muevas!" |
| Giro bajando (izq.) | ½ | 0 | medio giro + medio picado: **se mueve el otro** | "¡ahora tú!" |

- **¿Quién se mueve?** Arriba-izquierda: el izquierdo fuera. Abajo-izquierda: el derecho dentro.
  Arriba-derecha: el derecho fuera. Abajo-derecha: el izquierdo dentro.
- **Moverse en diagonal hace girar el ala**, porque no se desplaza de lado. Para acabar recto hay que corregir
  después: "primero tú, luego yo".
- **Cambio de lado** (izquierda → derecha): los dos cruzan a la vez. Sin sincronía, el ala da un bache: los dos
  al centro la hunden, los dos fuera la suben.

## 2. Vocabulario de piezas (`MapBuilder`, `makeContext`)

| Pieza | Función | Exige |
|---|---|---|
| Viga | `ctx.lintel(s, reach, below, lane?)` | bajar (pasar por debajo) |
| Muro | `ctx.barrier(s, reach, above, lane?)` | subir (pasar por encima). **Las lomas no obligan**: son suelo, el ala resbala por encima |
| Rampa | `ctx.ridge(...)` | nada: el suelo te sube. Solo para diversión (surf) |
| Saliente / pilar | `ctx.promontory`, `ctx.pillar` | apartarse (girar) |
| Ventana | `ctx.window(s, u, v, w, h, extent?)` | apuntar a un cuadrante ("¿quién se mueve?") |
| Bifurcación | `ctx.divider(s0, s1, u, width, pass)` → carriles A/B | decidir juntos; los dos carriles valen (`Route` y `RouteB`) |
| Túnel bajo / sala abierta | `height` / `width` en las órdenes del trazado | aguantar quietos / respiro y espectáculo |
| Curva suave (r ≥ 300) | `arc` | casi nada (la asistencia ayuda): solo para fluir |
| Curva comprometida (r 120-180) | `arc` | uno fuera del todo |
| Chicane (r ≤ 120, alternas) | `arc` | los dos a tope y cambiar a la vez |
| Ascendente / descendente | `ctx.updraft` / `ctx.downdraft (s0, len, fuerza, u?, ancho?)` | leer el aire, anticiparse |
| Viento lateral / ráfagas | `ctx.crosswind(...)`, `ctx.gusts(s0, n, cada, largo, fuerza, lado)` | inclinarse, corregir |
| Troncos / compuertas / aspas | `ctx.swingLog`, `ctx.gate`, `ctx.spinner` | elegir el momento |
| Anillos / plumas | `ctx.boostRing`, `ctx.feathers` | recompensa en una línea arriesgada, nunca el contenido |

## 3. Estructura de un nivel

1. **Presentar**: la idea una vez, aislada y con mucho margen.
2. **Practicar**: 2-3 veces, con ritmo y variación.
3. **Giro**: combinar con algo conocido, o apretar el ritmo.
4. **Final**: el momento memorable, seguido de un **respiro** de 3-5 s antes de la salida.

Cada nivel tiene en `LEVELS`:
- `title`;
- `tagline`: la frase de identidad, ≤ 5 palabras, en la tarjeta de título;
- `intro` opcional: aviso de algo nuevo;
- una ficha en el comentario: identidad, concepto, coordinación, momento memorable.

## 4. Reglas de ritmo (capítulos 1-2; las mide `tools/sim/drivers/pacing.luau`)

- Algo que hacer cada 2,5-5 s y nunca más de ~5 s sin exigir nada. Excepciones: el respiro final y las salas de
  espectáculo.
- Una idea nueva por nivel. Lo aprendido vuelve más tarde combinado: introducir → practicar → combinar → dominar.
- Duración: 30-45 s por nivel (las pruebas del capítulo, ~50 s).
- Valles: corto (360 studs, ~6 s) dentro del capítulo y largo (600, ~10 s) al cambiar de capítulo.
- Desde el nivel 3, cada nivel tiene al menos un momento de "¿quién se mueve?" o de cambio sincronizado.
- La intensidad va en ola: tensión → respiro → sorpresa → espectáculo.

**Números de física para diseñar** (con los pilotos de prueba):

| Maniobra | Espacio que necesita |
|---|---|
| Bajar hasta ~40 bajo el centro | ~130 studs |
| Pasar de bajo una viga a encima de un muro (Δ ≈ 75-80) | **≥ 300 studs** (el novato sube a ~17 studs/s) |
| Tras una curva comprometida, antes del siguiente obstáculo | ≥ 150 studs |
| Muro dentro de una descendente | añadir un `ctx.point` antes del muro: la buena línea sube antes de lo que dice el instinto |

## 5. Regla de dificultad (`FlightTester.RULES`)

| Niveles | Tiene que pasar |
|---|---|
| Flight School | novato en el juego sin golpes · tranquilo estricto ≥ 8 |
| 1-10 | completo estricto ≥ 8 (justo) · novato en el juego ≤ 1 golpe y sin perder el ala (error barato) |
| 11-25 | novato en el juego ≤ 1 golpe · tranquilo estricto ≥ 4 |
| 26-50 | completo estricto ≥ 4 · tranquilo en el juego sin golpes |

- Bifurcaciones: se prueban los dos carriles.
- Obstáculos móviles: 4 desfases del reloj.

## 6. Flight School (tutorial, ~40 s)

Es el principio del recorrido: desemboca en el valle de la StartIsland, justo antes del nivel 1. Si alguno del dúo
es nuevo, despegan al principio de Flight School; si no, en la StartIsland. Al cruzar la línea de relevo (el
despegue de los veteranos) empieza el recorrido de verdad sin cortar el vuelo.

| Tramo | Situación | Señal |
|---|---|---|
| BAJAR | puente bajo nada más despegar | "DIVE!" + marcas fantasma |
| SUBIR | muro justo detrás | "CLIMB!" + fantasmas |
| GIRAR | curva a la izquierda (r 150) | "LEFT!" + fantasmas |
| CAMBIO | curva a la derecha seguida | "SWAP RIGHT!" + fantasmas |
| COMBO | viga → muro → S | sin ayudas |

- **Modo práctica**: los golpes son "BONK!", sin corazones. Si el ala se queda casi parada más de 2 s, ayuda el
  viento a favor. Nadie se queda bloqueado.
- **SKIP**: hace falta que lo pulsen los dos.
- No cuenta para tiempos ni estadísticas.

## 7. Fichas de los niveles 1-10

| # | Nivel · tagline | Identidad | Coordinación | Momento memorable | Int. | Dur. |
|---|---|---|---|---|---|---|
| 1 | Up & Under · "Dive. Climb. Faster." | el sube-y-baja | los dos igual, a la vez | "la ola": bajo-arriba-bajo seguidos | 2→3 | ~40 s |
| 2 | Swap · "Swap sides together" | izquierda-derecha de verdad | opuestos y cambio sincronizado | la chicane | 3 | ~40 s |
| 3 | Windows · "Who moves?" | las ventanas | uno solo; descubrir quién | "moviste tú, era yo" | 3 | ~40 s |
| 4 | The Chimney · "Ride the wind up" | la corriente gigante | meterse en la columna y abrirse | salir por encima del acantilado | 2 | ~43 s |
| 5 | Split Decision · "High road or low road?" | la bifurcación | decidir juntos | "¡IZQUIERDA! NO, EL OTRO LADO" | 3→4 | ~49 s |
| 6 | The Big Drop · "Hold on tight" | la gran caída | picar, aguantar quietos, subir | entrar en el túnel tras el picado (aquí se presenta el impulso) | 3 | ~45 s |
| 7 | Crosswind · "Lean into it" | el viento lateral | aguantar inclinados y corregir | las ráfagas | 3→4 | ~45 s |
| 8 | Swinging Logs · "Wait... NOW!" | los troncos | elegir el momento + sube-y-baja | el hueco entre dos troncos en contrafase | 3→4 | ~43 s |
| 9 | Heavy Air · "Read the air" | corrientes que hunden | anticiparse | pasar el último muro por un pelo | 4 | ~38 s |
| 10 | Canyon Trial · "Everything the canyon has" | la prueba del cañón | todo lo anterior | la bifurcación con fuerzas | 5 | ~57 s |

**Progresión de ideas:**

| Idea | Nivel |
|---|---|
| A: vertical | 1 |
| B: lateral + cambio | 2 |
| A+B: ventanas | 3 |
| C: fuerza + espacio | 4 |
| A+B + elección | 5 |
| Velocidad / espacio | 6 |
| B + viento | 7 |
| A + timing | 8 |
| A + aire | 9 |
| Todo | 10 |

## 8. Cómo revisar un nivel

```bash
python3 tools/sim/run.py drivers/check.luau from=N to=N dress=false   # regla de dificultad
python3 tools/sim/run.py drivers/pacing.luau from=N to=N              # ritmo: activo %, tramo muerto, avisos/min
python3 tools/sim/run.py drivers/trace.luau level=N pilot=novicej     # dónde choca el novato (GOLPE …)
python3 tools/sim/run.py drivers/audit.luau                           # regla de oro del vestido
```

Antes de dar por bueno un nivel, pregúntate: **¿qué puede pasar aquí que haga que dos amigos se rían, griten o
tengan que hablar?**
