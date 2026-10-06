# S&NC Shaders 3.0

Controlador visual independiente de Roblox, también disponible desde HzReyzn Hub.
La interfaz se abre sin activar ningún shader automáticamente.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/hzReyzn/crazy/main/SNC_Shaders.lua"))()
```

La ruta anterior `HzReyzn_Shaders.lua` sigue funcionando y abre esta versión.

## Cambios

- Interfaz negro carbón, bordes blancos, nombre **S&NC Shaders** e icono **SC**.
  Arrastre suavizado, expansión horizontal, minimización a SC y cierre animado.
- Carga con barra y porcentaje. Al llegar al 100%, viaje dimensional de cinco
  segundos, seguido de un desvanecimiento. No altera la cámara del juego.
- Noon, Sunrise, Sunset y Night tienen ajustes de atmósfera, color y luz.
- **Rain y Snowfall conservan sus perfiles, simulación, límites, partículas y
  ajustes anteriores. El controlador de sonido y los seis audios no se modifican.**
- Se elimina el selector de calidad. Los especiales tienen detalle completo fijo.
  Los ajustes internos anteriores de lluvia y nieve se mantienen para respetar
  la petición de no cambiarlos, incluyendo su configuración para dispositivos táctiles.

## Especial Shaders 💎

- **Meteor Shower:** caída continua aleatoria dentro de un radio horizontal de
  450 studs alrededor del personaje, cabezas luminosas, estelas, chispas,
  iluminación cercana y destellos de impacto. Sin daño ni cambios de física.
- **Starfall:** caída continua en el mismo radio, estelas blancas visibles,
  halos fríos, partículas y destellos locales.
- **Aurora Sky:** tres cortinas amplias con filamentos, ondas suaves y gradación
  verde, cian y violeta sobre un cielo estrellado oscuro.
- **Deep Space:** cielo negro sin niebla, galaxia, planeta con anillos, planeta
  helado y recreación visual de **TON 618**, con disco de acreción y arco luminoso.
  Los cuerpos se colocan frente a la dirección inicial de la cámara; después
  conservan su orientación para que puedas mirar alrededor.

TON 618 es una interpretación artística inspirada en visualizaciones ópticas de
agujeros negros; no es una fotografía ni una simulación relativista completa.
Las texturas astronómicas se generaron para este proyecto. Referencia conceptual:
[visualización de NASA](https://www.nasa.gov/universe/nasa-visualization-shows-a-black-holes-warped-world/).

Los proyectiles utilizan conjuntos reutilizables de objetos y raycasts. Las
cortinas y los cuerpos celestes se animan con un límite de 30 actualizaciones por
segundo; la caída y la interfaz siguen los fotogramas renderizados.

## Recursos y compatibilidad

El ejecutable descarga las texturas de `assets/snc/` y los audios existentes de
`assets/shaders/`. Utiliza `game:HttpGet`, `writefile` y `getcustomasset` (o
`getsynasset`) cuando están disponibles. Guarda las texturas en sus propios
archivos `SNCShaders_r3_*.png`; los audios mantienen sus archivos de caché v2.

Estas funciones del lanzador no son APIs estándar de un LocalScript de Roblox.
Si faltan los recursos personalizados, los efectos geométricos pueden continuar,
pero no aparecerán las imágenes astronómicas. Para usarlos en una experiencia de
Studio se deben subir las imágenes y sonidos como assets permitidos y adaptar
sus identificadores. Los audios también aceptan los SoundIds configurables
anteriores mediante `getgenv().HzReyznShaderOptions`.

Las descargas se realizan en segundo plano. La carga inicial espera como máximo
12 segundos antes de iniciar el viaje; los recursos que terminen después se
incorporan cuando estén disponibles. Un fallo de audio no bloquea los shaders.

Default y cerrar restauran el entorno anterior. Se conservan Real Time, clima
aleatorio, volumen, silencio, restauración del shader anterior y protección
contra interfaces duplicadas al volver a ejecutar.

El controlador devuelto ofrece `SetMode`, `Default`, `Destroy`, `Show`,
`SetSound`, `SetAutoWeather` y `GetState`.

## Verificación

Sintaxis comprobada y pruebas en un entorno simulado de Roblox: diez efectos,
cambios repetidos, restauración del entorno, raycasts, respawn, reemplazo de
cámara, limpieza de conexiones, fallos de red, sonidos y reejecución. También
se comprobó la secuencia de carga, sus cinco segundos de viaje y las acciones
de expansión y minimización. Los bloques protegidos de lluvia, nieve y audio
se compararon con la versión 2.0 y permanecen iguales.

Estas pruebas no renderizan Roblox. El aspecto final, la disponibilidad de
texturas y los FPS necesitan una comprobación dentro del juego. Los efectos no
pueden forzar la calidad gráfica elegida en el cliente ni reemplazar su motor
de renderizado.

Made by hzReyzn.
