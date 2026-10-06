# S&NC Shaders 4.0

Script independiente de Roblox, también disponible desde HzReyzn Hub.
La interfaz aparece directamente y ningún shader se activa automáticamente.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/hzReyzn/crazy/main/SNC_Shaders.lua"))()
```

El enlace anterior `HzReyzn_Shaders.lua` continúa abriendo esta versión.

## Shaders principales

- Noon
- Sunrise
- Sunset
- Night
- Rain
- Snowfall

Se conservan Real Time (Sunrise → Noon → Sunset → Night), clima aleatorio,
restauración del shader anterior, Default, silencio y volumen.

Los cuatro especiales y la pantalla de carga se eliminaron por completo del
script. No hay descarga de texturas ni espera de carga al abrir la interfaz.
Los perfiles de los seis shaders principales, la simulación de lluvia y nieve
y el comportamiento de sus sonidos permanecen iguales a la versión anterior.

## Interfaz

- Negro profundo opaco, detalles blancos neón y bordes con reflejo animado.
- Panel compacto con seis botones principales, nombre S&NC Shaders e icono SC.
- Entrada y salida breves, expansión horizontal, arrastre suavizado y
  minimización completa a un botón SC que también puede arrastrarse.
- Al pulsar un shader: onda blanca desde el punto de contacto, reflejo deslizante,
  pequeñas chispas y pulso de luz. Los efectos se limitan al GUI.
- Los elementos de feedback se reutilizan, evitando crear nuevos objetos en cada
  pulsación. Las animaciones anteriores se cancelan cuando se reemplazan, y los
  cambios de tamaño se coordinan para evitar que compitan entre sí.
- Soporte de ratón y pantalla táctil; scroll y ajuste al tamaño de pantalla.
- Sin selector de calidad; se conservan los ajustes internos anteriores de lluvia
  y nieve, incluida su configuración para dispositivos táctiles.

## Sonido y compatibilidad

Rain y Snowfall conservan sus audios `assets/shaders/rain.ogg` y
`assets/shaders/snow.ogg`. Se descargan únicamente al seleccionar el clima
correspondiente, con `game:HttpGet`, `writefile` y `getcustomasset` (o
`getsynasset`) cuando están disponibles. Los archivos de caché siguen siendo
`HzReyznShaders_v2_rain.ogg` y `HzReyznShaders_v2_snow.ogg`.

El lanzador HTTP/loadstring no utiliza APIs estándar de un LocalScript.
Para Studio, el código puede integrarse como LocalScript con identificadores
propios de audio permitidos, mediante `HzReyznShaderOptions.SoundIds`.
Un fallo de sonido no bloquea la selección de shaders ni crea una pantalla de carga.

Cerrar o pulsar Default restaura el entorno anterior. Se mantienen las
protecciones de respawn, reemplazo de cámara, efectos añadidos por el juego y
reejecución sin duplicar interfaces. El controlador devuelve `SetMode`, `Default`,
`Destroy`, `Show`, `SetSound`, `SetAutoWeather` y `GetState`.

## Verificación

Sintaxis validada y pruebas en un entorno simulado de Roblox: ausencia de carga
y especiales, cero descargas al iniciar, los seis shaders, restauración del
entorno, raycasts de clima, respawn, cámara, sonidos, cierre y limpieza.
También se comprobó la selección táctil con VFX, pulsaciones repetidas sin
acumulación de objetos, arrastre suavizado, expansión y minimización.
Los bloques de los shaders principales, la lluvia, la nieve y el controlador de
audio se compararon con la versión anterior.

Estas pruebas no renderizan Roblox. La apariencia final y los FPS deben
comprobarse dentro del juego.

Made by hzReyzn.
