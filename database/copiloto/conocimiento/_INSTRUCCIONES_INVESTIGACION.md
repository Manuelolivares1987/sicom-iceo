# Instrucciones comunes — investigación técnica para el Copiloto del taller

Contexto: Pillado Empresas (Chile) opera 37 camiones pesados en faenas mineras
(Coquimbo y Calama): aljibes de combustible, camiones de riego/agua industrial,
camiones pluma, polibrazo y carrocería plana. El "Copiloto Técnico" es un
asistente IA que responde a los mecánicos desde el teléfono, citando fuentes.
Regla dura del copiloto: los valores críticos (torques, presiones, códigos de
falla, amperajes de fusibles, pines, resistencias) SOLO pueden salir de fuentes
citadas. Por eso TODO dato que escribas debe llevar su URL de fuente.

## Fuentes permitidas
- Oficiales OEM (portales públicos, body builder, driver guide, manuales de
  operación/mantenimiento públicos, boletines públicos, recalls NHTSA/Transport
  Canada/ACCC/Senacon/SERNAC).
- Fabricantes de componentes (Allison, WABCO/ZF, Knorr-Bremse, Bosch, Voith,
  Parker Chelsea, Eaton, Hyva, Palfinger, IMT, Blackmer, Liquid Controls...).
- Técnicas de terceros serias (SAE J1939 resúmenes, CSS Electronics, Noregon,
  Diesel Laptops, Jaltest, universidades, revistas técnicas).
- Foros de mecánicos SOLO como "experiencia_campo" (confiabilidad baja) y solo
  si varios coinciden.

## Prohibido
- Sitios de manuales pirateados / "download full workshop manual" / warez,
  bypass de paywall o de logins. Si un documento solo está tras licencia OEM
  (XENTRY/WIS, Scania SDP3/TIS, Volvo Tech Tool/Impact), anótalo como
  "requiere licencia: <portal>" y sigue.
- Inventar valores. Si no encuentras el dato con fuente, no lo escribas.

## Descargas
PDFs públicos y útiles para diagnóstico (diagramas, fusibles, códigos, body
builder eléctrico, manuales de operación/mantenimiento) se descargan con
`curl -L -o "<ruta>" "<url>"` a:
`C:/Users/Manuel Olivares/Desktop/OPERACIONES/00_PILLADO (PRIORIDAD)/01_OPERACIONES/Mantenimiento/Manuales/_Investigacion web 2026-09-19/<Marca>/`
Nombre de archivo: `<Marca> <Modelo> - <Qué es> (<idioma>).pdf`. Verifica que
sea un PDF real (`file` o primeros bytes `%PDF`) y bórralo si no. Máx ~40 MB c/u.
Ya existen (NO re-descargar) los PDFs de la carpeta hermana
`_Descargados oficiales 2026-09` (Mercedes Brasil manuales mantención/operación
Actros/Atego/Axor/Accelo; Mack GU body builder secciones 0-9 + diagrama 12V
completo; Volvo NA body builder FMX secciones 0-9 + diagramas cableado; Scania
body builder cisternas + códigos DM1 DC09/13/16 + EMS instrumentación).

## Formato del archivo de conocimiento (markdown, en español)
Una "ficha" por hecho/tema. Cada ficha es autocontenida (se indexa sola):

```
## [<sistema>] <Título concreto>
- Aplica: <marca> <modelo(s)> <motor/caja/ECU> <años>
- Tipo: codigo_falla | fusibles_reles | diagrama_electrico | pinout_conector | arquitectura_can | procedimiento_diagnostico | falla_conocida | especificacion | boletin_recall | lectura_codigos_tablero
- Confiabilidad: oficial | tecnica_terceros | experiencia_campo
- Fuente: <URL exacta> (<título del documento>, pág. N si aplica)

<contenido: concreto, orientado al mecánico, con valores y pasos. Tablas markdown OK.>
```
<sistema> ∈ electrico, motor, transmision, frenos, hidraulica, direccion,
tren_rodaje, combustible, postratamiento, implemento, general.

## Formato de códigos de falla (JSON)
Archivo `codigos/<marca>.json`: array de objetos
```
{"marca":"mack","aplica":"MP8 EPA10 / GU813","ecu":"EECU","formato":"SPN-FMI",
 "codigo":"SPN 3251 FMI 0","descripcion":"...","causas":["..."],
 "comprobaciones":["..."],"sistema":"postratamiento",
 "confiabilidad":"oficial","fuente":"https://..."}
```
formato ∈ SPN-FMI | MID-PID-FMI | MID-SID-FMI | MID-PSID | FR/MR/GS (Mercedes) |
blink | DTC-OEM | Allison-DTC | ABS/EBS. Solo códigos con fuente; mejor 60
códigos bien documentados que 500 sin respaldo. Prioriza los más frecuentes en
operación minera (polvo, altura, calor, ralentí largo, vibración).
