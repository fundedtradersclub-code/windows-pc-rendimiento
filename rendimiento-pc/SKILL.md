---
name: rendimiento-pc
description: Diagnostica y mejora el rendimiento de una PC o laptop con Windows lenta, de forma segura y reversible. Úsala siempre que alguien diga que su computadora "está lenta", "se traba", "tarda en prender", "se llenó el disco C", quiera "optimizar", "acelerar" o "limpiar" Windows, pregunte qué programas puede desinstalar o desactivar del inicio, quiera liberar espacio o mover Escritorio/Descargas/Documentos a otro disco, o pregunte qué es un programa que encontró instalado (BlueStacks, MEmu, Epic Games, antitrampas, "optimizadores"), aunque no pida un diagnóstico de forma explícita. También sirve para revisar si conviene un SSD o más RAM. Solo Windows 10/11.
---

# Rendimiento de PC con Windows

Ayudas a una persona, que muchas veces no es técnica, a que su PC con Windows vuelva a ir rápido
**sin romper nada**. La confianza es el producto: una limpieza agresiva que borra algo importante o
deja Windows inestable es peor que una PC lenta. Por eso el método es siempre el mismo:
**medir → explicar → pedir permiso → actuar de forma reversible → volver a medir**.

Habla en el idioma de la persona, con palabras sencillas. Di qué hace cada cosa y por qué, sin jerga
("programa que arranca solo con Windows", no "entrada Run de HKCU").

Todos los scripts están en `scripts/` (junto a este archivo). Ejecútalos con
`powershell -NoProfile -ExecutionPolicy Bypass -File "<ruta>\scripts\<script>.ps1" ...`.
Funcionan en Windows PowerShell 5.1 y PowerShell 7. Los que cambian algo **no hacen nada sin `-Aplicar`**:
corre primero sin él para mostrar a la persona exactamente qué pasaría.

## 1. Diagnosticar (solo lectura, no pidas permiso)

```
scripts\diagnostico.ps1 -Json "$env:LOCALAPPDATA\rendimiento-pc\antes.json"
```

Revisa RAM, tipo y salud de discos, espacio libre, procesos, programas al inicio, servicios de
terceros, programas pesados (catálogo en `scripts/programas-pesados.json`), temporales, antivirus,
plan de energía, reinicio pendiente y errores de disco. Añade `-Rapido` si la persona tiene muchísimos
archivos y medir sus carpetas tardaría. Si no es administrador, algunos datos faltan: dilo, no inventes.

Corre el diagnóstico primero, sin preguntar nada. Si la persona ya contó **cuándo** se pone lenta
("al abrir Chrome y Word", "al jugar", "al prender"), usa eso para ordenar el plan. Si no lo contó,
incluye en tu mensaje del plan una sola pregunta corta sobre eso; no detengas el diagnóstico por ella.

El diagnóstico corre con Claude abierto: Claude Code, Node y la terminal ocupan RAM. El informe ya lo
descuenta ("sin contar las herramientas del asistente"); usa ese número, no el bruto, y no
propongas cerrar esos procesos.

## 2. Explicar y proponer un plan

Lee las "Señales" del informe y ordénalas por **impacto real**, no por cantidad. En la práctica:

1. **Disco mecánico (HDD) como disco del sistema** → nada de software se compara con pasar a un SSD.
2. **Poca RAM**: con menos de 8 GB, ampliar es prioridad. Con 8 GB y uso alto (≥ 70 % sin contar
   el asistente), primero ajustes de navegador y programas; ampliar a 16 GB es la recomendación de
   hardware si sigue lento. Con 16 GB o más, la RAM casi nunca es el problema. El informe indica si
   hay ranuras libres: menciónalo antes de que la persona compre nada.
3. **Disco del sistema casi lleno** (< 15 % libre) → liberar espacio.
4. **Emuladores, dos antivirus, "optimizadores", antitrampas sin usar** → desinstalar.
5. **Muchos programas al inicio** → desactivarlos del inicio (no desinstalarlos).
6. **Temporales y cachés grandes** → limpiar.
7. Plan de ahorro de energía, días sin reiniciar, reinicio pendiente → ajustes rápidos.

**Si el equipo está sano** (SSD, espacio de sobra, sin programas pesados, RAM suficiente), dilo con
todas las letras: limpiar no lo va a acelerar, y conviene mirar el uso (navegador, pestañas,
extensiones) o el hardware. Ser honesto aquí genera más confianza que una limpieza de relleno.

Si la lentitud aparece con **el navegador** (lo más común), lee la sección "Navegador" de
`references/ajustes-y-limites.md`: ahorro de memoria, pestañas en suspensión y extensiones.

Presenta el plan en tres grupos: **seguro y rápido** (limpieza, reiniciar), **necesita tu decisión**
(qué desinstalar, qué quitar del inicio, mover carpetas) y **hardware** (SSD/RAM, solo como
recomendación con el porqué). Para cada programa que propongas quitar, explica en una línea qué es
(columnas "Qué es" y "Sugerencia" del informe, o tu conocimiento) y qué pasa si se quita. Los
programas de inicio marcados "mantener" (seguridad, audio, touchpad, utilidades del fabricante) se
dejan. Un programa de **acceso remoto** (AnyDesk, TeamViewer...) merece una pregunta explícita: ¿lo usa
y sabe quién se conecta? Si no, es un tema de seguridad, no solo de velocidad. Si no sabes qué es un programa,
dilo y recomienda no tocarlo. Nunca propongas quitar controladores ni utilidades del fabricante
(audio, touchpad, gráficos, chipset, BIOS).

Espera la confirmación. Si puedes, ofrece la lista como opciones de selección múltiple para que la
persona marque qué quiere. Lo que no confirme, no se toca.

## 3. Actuar (solo lo aprobado)

**Qué necesita qué.** Empieza por lo que no pide permisos especiales, así la persona ve resultados
sin trámites:

- **Sin administrador, sin punto de restauración** (ya son reversibles): quitar del inicio programas
  "de usuario", limpiar los temporales del usuario.
- **Con administrador y punto de restauración antes**: desinstalar, programas de inicio "de equipo",
  limpieza de cachés de Windows, mover carpetas.

Para el segundo grupo, crea primero el punto de restauración:

```
scripts\punto-restauracion.ps1
```

Si no hay permisos de administrador, explica en simple cómo abrir "Terminal (Administrador)"
(clic derecho en el botón Inicio). No desinstales sin punto de restauración salvo que la persona lo
acepte sabiendo el riesgo.

| Qué | Comando (primero sin `-Aplicar`) | Notas |
|---|---|---|
| Desinstalar | `desinstalar.ps1 -Nombres "BlueStacks,Epic Games Launcher" [-CerrarProcesos HD-Player] [-Silencioso]` | Sin `-Silencioso` abre el asistente de cada programa uno por uno para que la persona acepte: es lo más transparente y lo recomendado por defecto. `-Silencioso` desinstala sin ventanas si el programa lo permite. |
| Quitar del inicio | `inicio.ps1` (lista) · `inicio.ps1 -Desactivar "Steam,Spotify"` | Igual que el Administrador de tareas: reversible con `-Reactivar` o desde ahí. |
| Limpiar | `limpiar.ps1` · opcional `-Papelera` (preguntar: son archivos del usuario) · `-Componentes` (DISM, 5-30 min) | Sin administrador solo limpia los temporales del usuario. |
| Mover carpetas | `mover-carpetas.ps1 -Carpetas Escritorio,Descargas -Destino D:\<carpeta>` | Copia, verifica y solo entonces cambia la ruta; si algo falla no toca nada. Solo a discos fijos internos, nunca USB. Pide una carpeta de destino vacía. Avisa que puede tardar (≈ 1 min por cada 3-4 GB en discos normales). |

Antes de mover, mira **a qué tipo de disco va** (columna "tiene Windows" y tipo en el diagnóstico).
Lo típico es Windows en un SSD pequeño y un HDD grande de datos: ahí conviene mover lo que se
**guarda** (Descargas, Videos, Imágenes, un Escritorio lleno de archivos), pero no lo que se **trabaja**
a diario con miles de archivos pequeños (proyectos de programación con `node_modules` o `.git`,
bases de datos, bibliotecas de fotos de Lightroom): en un HDD irían mucho más lentos. Si Documentos
tiene decenas de miles de archivos, pregunta qué hay antes de proponerlo; el script también avisa.

Cuando pases listas a los scripts, sepáralas con comas en un solo argumento
(`-Nombres "BlueStacks,Epic Games Launcher"`): con `-File` PowerShell no arma listas, y los scripts
las separan ellos mismos.

Para ajustes sueltos (plan de energía, Defender, reinicio, SSD/RAM, almacenamiento automático) y la
lista de cosas que **no** hay que hacer, lee `references/ajustes-y-limites.md` cuando el plan los incluya
o la persona pida algo de esa lista.

Cada script deja un registro en `%LOCALAPPDATA%\rendimiento-pc\registros\`. Si algo sale con
AVISO o ERROR, explícalo en simple y propone el siguiente paso; no lo escondas.

Las desinstalaciones con ventana pueden quedar esperando a la persona: dile que mire la barra de
tareas. Algunas piden reiniciar (código 3010): anótalo y sugiere reiniciar al final, una sola vez.

## 4. Volver a medir y cerrar

```
scripts\diagnostico.ps1 -Json "$env:LOCALAPPDATA\rendimiento-pc\despues.json"
```

Compara con `antes.json` y muestra solo lo que cambió, con números: espacio libre antes/después,
programas al inicio antes/después, programas quitados, RAM en uso. Si algo no mejoró, dilo.
Termina con:

- Qué se hizo y qué quedó pendiente (por ejemplo, la recomendación de SSD).
- Cómo deshacer: punto de restauración, `inicio.ps1 -Reactivar`, "Restaurar valores predeterminados"
  en la pestaña Ubicación de la carpeta movida.
- Dónde están los registros.
- Que reinicie una vez para que todo se aplique.

## Por qué este método

- **Diagnosticar primero** evita la "limpieza a ciegas": la causa más común de lentitud (disco
  mecánico, poca RAM, disco lleno) no se arregla borrando temporales, y conviene decirlo.
- **Simulación por defecto** permite enseñar exactamente qué pasará antes de que pase.
- **Reversible siempre**: desactivar del inicio en vez de borrar entradas, copiar y verificar antes de
  mover, punto de restauración antes de desinstalar.
- **La persona decide** qué se quita: un programa "inútil" para ti puede ser el que usa para trabajar.
