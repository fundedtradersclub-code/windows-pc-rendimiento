# Ajustes sueltos y límites

## Ajustes rápidos (siempre con permiso)

**Plan de energía.** Ver: `powercfg /getactivescheme`. En equipo enchufado, "Equilibrado" es lo
correcto: `powercfg /setactive SCHEME_BALANCED`. "Alto rendimiento" (`SCHEME_MIN`) solo aporta en
escritorios y gasta más; en laptop con batería, no lo recomiendes. "Ahorro de energía" frena el
procesador a propósito.

**Reiniciar de verdad.** Con "Inicio rápido", apagar no limpia la memoria; reiniciar sí. Si el
diagnóstico muestra muchos días encendido o reinicio pendiente, pide un reinicio.

**Análisis de malware.** Si hay lentitud repentina, ventanas que se abren solas o CPU alta sin
motivo: `Start-MpScan -ScanType QuickScan` (Microsoft Defender, como administrador). Si encuentra
algo, `Get-MpThreatDetection`. No instales otro antivirus "para probar".

**Almacenamiento automático (Storage Sense).** Configuración > Sistema > Almacenamiento. Vacía
temporales y la papelera cada cierto tiempo sin intervención. Recomiéndalo después de una limpieza.

**Windows Update.** Que esté al día: muchas lentitudes se corrigen con actualizaciones de
controladores y del sistema. Si hay una actualización a medio instalar, termina con un reinicio.

**Efectos visuales.** Solo en equipos muy justos (2-4 GB de RAM, sin gráfica): `SystemPropertiesPerformance.exe`
> "Ajustar para obtener el mejor rendimiento". Explica que Windows se verá más simple. Mejora poco
en equipos normales: no lo propongas por defecto.

## Navegador (la causa más común con 8 GB de RAM)

Cada pestaña y cada extensión es un proceso que ocupa memoria, aunque no se mire. Sin tocar nada del
sistema:

- **Chrome:** menú ⋮ > Configuración > Rendimiento > activar **Ahorro de memoria** (suspende pestañas
  que no se usan). En la misma pantalla, "Ahorro de energía" si es laptop con batería.
- **Edge:** Configuración > Sistema y rendimiento > **Pestañas en suspensión** (activar, 5-15 min) y
  "Aumento de inicio" desactivado si la PC tarda en prender.
- **Extensiones:** `chrome://extensions` o `edge://extensions`. Quitar las que no se reconocen; cada
  una consume, y algunas son publicidad o rastreo.
- **Pestañas:** con 8 GB, mantener unas 10-15 abiertas como máximo, sobre todo antes de abrir Word,
  Excel o una videollamada.
- **Un solo navegador:** tener Chrome, Edge y Opera abiertos a la vez triplica el consumo.
- Para ver qué pestaña consume más: Shift+Esc (Administrador de tareas del navegador).

## Hardware: cuándo recomendarlo

- **SSD**: si el disco del sistema es HDD (`MediaType` HDD en el diagnóstico). Es la mejora más grande
  posible (arranque de minutos a segundos). Un SSD SATA de 480-500 GB es barato y entra en casi
  cualquier laptop que tenga HDD de 2,5". Se puede clonar el disco sin reinstalar.
- **RAM**: con 4 GB, Windows 11 va justo con un navegador; 8 GB es el mínimo cómodo, 16 GB si usa
  muchas pestañas, Office y videollamadas. Antes de recomendar comprar, mira la línea "RanurasRam" del
  diagnóstico (ranuras ocupadas, máximo de la placa, módulos actuales). Windows no siempre sabe si hay
  memoria soldada: confirma con el modelo exacto (`Get-CimInstance Win32_ComputerSystemProduct | Select Name`)
  en la ficha del fabricante. Hay que comprar la misma generación (DDR4/DDR5) y, si es posible, la
  misma velocidad.
- **Disco con errores o salud distinta de "Healthy"**: copia de seguridad YA, antes de cualquier otra cosa.

## Lo que NO hay que hacer (y por qué)

Si la persona pide alguna de estas cosas, explica el riesgo y ofrece la alternativa:

| Pedido típico | Por qué no | Alternativa |
|---|---|---|
| Desactivar Microsoft Defender "para que vaya más rápido" | Deja el equipo sin protección; la ganancia es mínima | Dejar un solo antivirus; excluir carpetas de juegos solo si hace falta |
| Usar "limpiadores de registro" u "optimizadores" | No aceleran, pueden romper programas y algunos son adware | Los scripts de esta skill |
| Desactivar Windows Update para siempre | Riesgo de seguridad, controladores viejos | Pausar unas semanas desde Configuración |
| Borrar a mano `C:\Windows\WinSxS`, `Installer` o `System32` | Rompe Windows | `limpiar.ps1 -Componentes` (DISM) |
| Desactivar el archivo de paginación | Programas se cierran al quedarse sin memoria | Dejarlo administrado por Windows; ampliar RAM |
| Desfragmentar un SSD | Desgasta y no ayuda | Windows ya optimiza (TRIM) solo |
| Desinstalar algo que no se reconoce | Puede ser un controlador o utilidad del fabricante | Buscar qué es; si hay duda, dejarlo |
| "Liberadores de RAM" | Vacían la memoria que Windows usa como caché: luego todo va más lento | Cerrar lo que no se usa; más RAM |
| Desactivar servicios de Windows al azar ("debloat" de internet) | Efectos raros semanas después, difíciles de rastrear | Quitar programas de terceros del inicio |
| Mover carpetas a un USB o disco externo | Al desconectarlo, Windows pierde el Escritorio | Solo discos internos fijos |
