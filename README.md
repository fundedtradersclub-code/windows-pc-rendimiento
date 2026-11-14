# rendimiento-pc · skill para que una PC con Windows vuelva a ir rápido

Una **skill para Claude** (Claude Code y apps de Claude que admiten skills) que convierte a Claude en
un técnico cuidadoso: mide por qué la computadora está lenta, lo explica en palabras sencillas,
propone un plan, **pide permiso** y solo entonces hace cambios, siempre reversibles. Al final vuelve
a medir para mostrar qué mejoró.

Nació de una limpieza real de una laptop lenta: emuladores de Android y launchers de juegos que nadie
usaba, temporales acumulados y un disco del sistema lleno con 80 GB de Escritorio y Descargas. Esa
experiencia se convirtió en scripts reutilizables y en un método que cualquiera puede repetir sin
saber de informática.

## Para qué sirve el agente

La persona dice algo como *"mi laptop está lentísima"*, *"se llenó el disco C"* o *"¿qué es BlueStacks
y lo puedo borrar?"*, y Claude:

1. **Diagnostica sin tocar nada**: RAM, tipo y salud de los discos (SSD o mecánico), espacio libre,
   procesos que más consumen, programas que arrancan con Windows, servicios de terceros, programas
   pesados instalados (emuladores, launchers, antitrampas, antivirus duplicados, "optimizadores"),
   temporales, plan de energía, reinicio pendiente y errores de disco. También revisa si hay ranuras
   de RAM libres antes de recomendar comprar memoria, explica qué es cada programa de inicio y avisa
   si arranca un programa de acceso remoto (AnyDesk, TeamViewer). Descuenta la memoria que usan las
   propias herramientas de Claude para no exagerar el problema.
2. **Explica y prioriza** por impacto real. Si el problema es un disco mecánico o poca RAM, lo dice:
   borrar temporales no arregla eso. Si el equipo está sano, también lo dice, y orienta hacia lo que
   suele pesar de verdad (el navegador con muchas pestañas y extensiones).
3. **Propone un plan** separado en "seguro", "necesita tu decisión" y "hardware", explicando qué es
   cada programa antes de sugerir quitarlo.
4. **Actúa solo con permiso**, empezando por lo que no necesita administrador. Antes de desinstalar
   o mover carpetas crea un punto de restauración, y registra todo.
5. **Vuelve a medir** y muestra el antes y el después, y cómo deshacer cada cambio.

### Principios de seguridad

- **Simulación por defecto.** Ningún script cambia nada sin `-Aplicar`. Primero se muestra exactamente
  qué pasaría.
- **Reversible.** Los programas de inicio se *desactivan* como lo hace el Administrador de tareas (no se
  borran). Antes de desinstalar se crea un punto de restauración.
- **Mover carpetas sin riesgo de perder archivos.** Copia → verifica cantidad de archivos y bytes →
  recién entonces cambia la ruta en Windows → borra el original. Si algo falla antes, no se toca nada.
  Nunca a USB ni a discos de red. Avisa si el destino es un disco mecánico y la carpeta tiene miles de
  archivos de trabajo.
- **Nada de trucos dañinos.** No desactiva el antivirus, no usa limpiadores de registro ni "liberadores
  de RAM", no borra carpetas de sistema, no apaga Windows Update ni toca controladores. La lista
  completa, con el porqué, está en [`references/ajustes-y-limites.md`](rendimiento-pc/references/ajustes-y-limites.md).
- **La persona decide.** Un programa que parece inútil puede ser el que usa para trabajar.

## Instalación

Requisitos: Windows 10 u 11, PowerShell 5.1 (viene con Windows) o 7.

**Claude Code** (para tu usuario, disponible en todos los proyectos):

```powershell
git clone https://github.com/fundedtradersclub-code/windows-pc-rendimiento.git
cd windows-pc-rendimiento
powershell -ExecutionPolicy Bypass -File .\instalar.ps1
```

Esto copia la carpeta `rendimiento-pc` a `%USERPROFILE%\.claude\skills\`. También puedes copiarla a
mano, o dentro de `.claude\skills\` de un proyecto para usarla solo ahí.

**Otras apps de Claude con skills**: se puede subir la carpeta `rendimiento-pc` comprimida en .zip
desde la sección de skills de la configuración. Ojo: los scripts tienen que correr *en la PC con
Windows que se quiere mejorar*, así que lo natural es usarla con Claude Code instalado en esa PC.

Después, basta con escribirle a Claude: *"mi computadora está lenta, ¿me ayudas?"*.

## Uso de los scripts sin Claude

Todos están en `rendimiento-pc/scripts/`. Para los que hacen cambios, abre PowerShell **como
administrador**.

| Script | Qué hace | Ejemplo |
|---|---|---|
| `diagnostico.ps1` | Informe completo (solo lee). `-Json` guarda los datos para comparar; `-Rapido` no mide carpetas. | `.\diagnostico.ps1 -Json antes.json` |
| `punto-restauracion.ps1` | Crea un punto de restauración. | `.\punto-restauracion.ps1` |
| `desinstalar.ps1` | Desinstala por nombre; abre el asistente de cada uno (o `-Silencioso`). | `.\desinstalar.ps1 -Nombres "BlueStacks,Epic Games Launcher" -Aplicar` |
| `inicio.ps1` | Lista, desactiva o reactiva programas de inicio. | `.\inicio.ps1 -Desactivar "Spotify" -Aplicar` |
| `limpiar.ps1` | Temporales, caché de Windows Update y de Optimización de distribución; opcional `-Papelera` y `-Componentes` (DISM). | `.\limpiar.ps1 -Aplicar` |
| `mover-carpetas.ps1` | Mueve Escritorio, Descargas, Documentos, Imagenes, Musica o Videos a otro disco interno. | `.\mover-carpetas.ps1 -Carpetas "Escritorio,Descargas" -Destino D:\MisCarpetas -Aplicar` |

Sin `-Aplicar`, cada script solo muestra lo que haría. Los registros quedan en
`%LOCALAPPDATA%\rendimiento-pc\registros\`.

El catálogo de programas que suelen pesar (con una explicación sencilla de qué es cada uno) está en
`scripts/programas-pesados.json`. Se agradecen aportes.

### Cómo deshacer

- **Desinstalaciones y cambios del sistema:** Panel de control > Recuperación > Abrir Restaurar sistema.
- **Programas de inicio:** `.\inicio.ps1 -Reactivar "<nombre>" -Aplicar`, o Administrador de tareas >
  Aplicaciones de arranque.
- **Carpetas movidas:** clic derecho en la carpeta > Propiedades > Ubicación > Restaurar valores
  predeterminados (Windows ofrece mover los archivos de vuelta).

## Estructura

```
rendimiento-pc/
├── SKILL.md                       # instrucciones para Claude: método, prioridades, qué no hacer
├── references/
│   └── ajustes-y-limites.md       # energía, Defender, SSD/RAM y la lista de "no hacer"
└── scripts/
    ├── comun.ps1                  # registro, permisos, punto de restauración, lectura de programas
    ├── diagnostico.ps1
    ├── punto-restauracion.ps1
    ├── desinstalar.ps1
    ├── inicio.ps1
    ├── limpiar.ps1
    ├── mover-carpetas.ps1
    └── programas-pesados.json     # catálogo editable
```

## Limitaciones

- Solo Windows 10/11. Probado en Windows 11 con PowerShell 5.1.
- Algunas mediciones (cachés del sistema, servicios) necesitan administrador; sin permisos el informe
  lo indica en lugar de inventar.
- No reemplaza a un técnico si hay fallas de hardware: si el diagnóstico muestra errores de disco, lo
  primero es hacer copia de seguridad.
- Úsala bajo tu responsabilidad. Los scripts son conservadores, pero desinstalar programas y mover
  carpetas son cambios reales en tu equipo.

## Licencia

MIT. Ver [LICENSE](LICENSE).
