# Comparación: tabla oficial Mercedes-Benz vs escalera SICOM

**Fecha:** 04-09-2026 · **Fuente oficial:** Manual de mantenimiento Actros Euro 5,
Mercedes-Benz do Brasil / Kaufmann Chile (Literatura Técnica de Servicio TE/BAB),
70 páginas — aplica a la familia Actros/Axor/Atego con motores OM 457/460 LA.
**Nuestra tabla:** escalera 300 h definición compañía (MIG510) + absorción (MIG513).

---

## 1 · Cómo estructura Mercedes-Benz el mantenimiento (el original)

MB **no publica una tabla de horas fija**. El Actros Euro 5 usa el sistema
**Telligent®**: el computador de a bordo calcula cuándo tocan los cambios de
aceite y el mantenimiento según la condición de uso (calidad del aceite MB
228.x, azufre del combustible, esfuerzo). Sobre eso, el manual define **bloques
encadenados** — la misma lógica de escalera que ya usamos:

| Bloque MB | Cuándo | Qué es |
|---|---|---|
| Cambio de aceite motor + filtro | Lo pide el computador (máx. 12 meses) | El servicio de lubricación |
| **Mantenimiento general «M»** | Lo pide el computador | La visita completa: filtros de combustible, correa Poly-V, lubricación, niveles, hermeticidad, frenos, dirección, control final |
| **Z1** | Sólo en el **1er** M (y grapas U también en el 2º) | Reaprietes de chasis, suspensión, 5ª rueda (asentamiento) |
| **Z2** | Cada **2** servicios M | Filtro de polvo de cabina + reaprietes de cardanes y estabilizadoras |
| **Z4** | Cada **4** servicios M | Freno motor, radiadores, 5ª rueda, fuelles, escape, tanque, faros, acople remolque. **Juego de válvulas: en el 1er M y luego cada 4 M** |
| **J1** | Cada **12 meses** | Cartucho secador de aire + grasa y retenes de cubos de rueda delanteros |
| **J2** | Cada **2 años** | Cambio elemento del filtro de aire; filtro de AdBlue (240.000 km o 2 años) |
| **J3** | Cada **3 años** | Cambio líquido refrigerante + calibración bomba AdBlue |

En **servicio severo** (minería: tierra, pendiente, carga máxima, ralentí), la
práctica de la red MB es convertir el «lo pide el computador» en horas fijas
cortas — exactamente lo que hicimos: **M ≈ 300 h de intervalo corto**, con el
resto encadenado en múltiplos. La pauta severa de referencia de la marca para
Atego minero es «300 Hr», que coincide con nuestra definición compañía.

## 2 · Contraste peldaño por peldaño

| Nuestra escalera | Equivalente MB | Veredicto |
|---|---|---|
| **SL 300 h** — aceite motor + filtro, drenaje racor/estanques, engrase, niveles, fugas, frenos/neumáticos/luces, horómetro | Cambio de aceite (computador; en severo = intervalo corto) + parte de la inspección | ✔ CORRECTO. En servicio extremo 300 h es lo que la red aplica. El engrase en cada visita supera al manual (que lo pide en M) — bien para minería |
| **SM1 600 h** — filtros combustible + prefiltro, filtro aire (revisión), correas, reapriete ruedas/suspensión, frenos | Mantenimiento general **M** | ✔ CORRECTO con 1 matiz (aire, ver §3.4) |
| **SM2 1200 h** — filtros aire, filtro cabina, aceite diferenciales, espectrometría, frenos completo, eléctrico/baterías | M + **Z2** (cada 2 M) | ✔ CORRECTO. El filtro de cabina calza exacto con Z2. La espectrometría es nuestra (buena práctica minera, MB no la exige) |
| **SM3 2400 h** — aceite caja + dirección, secador, refrigerante, correas, rótulas/terminales/suspensión | M + **Z4** (cada 4 M) + J1/J3 parciales | ⚠ CASI: acá deberían estar las **válvulas** y falta **AdBlue** y **cubos** (ver §3) |
| **SM4 4800 h** — válvulas, turbo, embrague/transmisión, alternador/arranque, radiadores | Cada 8 M | ⚠ Las válvulas van cada 4 M (2400 h), no cada 8 |
| **SM5 9600 h / SM6 19200 h** — desgaste mayor, estructural, evaluación motor/caja | No existen en el manual (son horizonte de overhaul) | ✔ OK como definición nuestra de largo plazo |

## 3 · Diferencias que hay que corregir (aplicables)

1. **Juego de válvulas** — el manual lo pide en el **1er M y luego cada 4 M**
   (≈ cada 2400 h con M=600). Nosotros lo tenemos en SM4 (4800 h): al doble
   del intervalo oficial. → **Mover a SM3 (2400 h)**; la absorción lo arrastra
   a 4800/9600/19200 sin duplicar.
2. **Sistema AdBlue** — el Actros/Axor Euro 5 usa AdBlue y el manual pide
   **cambio del filtro de AdBlue (240.000 km o 2 años)** y calibración de la
   bomba (J3). No está en ninguna pauta nuestra. → **Agregar a SM3 (2400 h)**.
3. **Cubos de rueda delanteros (J1 anual)** — cambiar grasa y retenes,
   verificar rodamientos y juego axial, una vez al año. No está en nuestra
   escalera. → **Agregar a SM3 (2400 h)** con la nota «máx. 12 meses».
4. **Filtro de aire: no se sopla** — el manual dice *remover el polvo de la
   válvula de descarga* y *comprobar la saturación*; el elemento se cambia
   (J2 máx. 2 años o cuando el indicador lo pide). Soplar el papel filtrante
   lo microperfora y deja pasar polvo al motor — en minería es la muerte del
   turbo. Nuestro SM1 dice «revisión/soplado». → **Reescribir el ítem**: revisar
   saturación y limpiar la válvula de descarga, sin soplar el elemento.
5. **Secador de aire** — lo tenemos en SM3 (2400 h); el manual lo pide
   **anual** (J1). Un camión que corre poco puede pasar del año sin llegar a
   2400 h. → **Anotar «máx. 12 meses» en el ítem** (el motor de preventivas
   corre por horas; el tope calendario queda declarado para el planificador).
6. **Primer servicio (Z1, asentamiento)** — reaprietes de chasis/suspensión/5ª
   rueda sólo en el 1er mantenimiento (y grapas U también en el 2º). Aplica a
   **camiones nuevos**; nuestra flota ya está rodada. → No se crea pauta; queda
   declarado acá para la próxima incorporación de un equipo 0 km.

## 4 · Dónde nuestra tabla es MÁS exigente que el manual (se mantiene)

- **Espectrometría de aceite cada 1200 h** — MB no la pide; en minería paga sola.
- **Cambio de correas y tensores a las 2400 h** — el manual sólo «verificar y
  cambiar si es necesario»; en polvo y calor el cambio programado evita cortes.
- **Refrigerante máx. cada 2 años** (manual: 3 años) — más conservador, OK.
- **Engrase completo en cada SL (300 h)** — el manual lo pide en cada M; con
  tierra y agua de regadío, engrasar cada 300 h es lo correcto.

## 5 · Lo que el manual deja al conductor (ya cubierto en SICOM)

La **inspección diaria y semanal** del manual (drenar racor, presiones,
luces, tacógrafo, correa, apriete de ruedas, 5ª rueda) es responsabilidad del
conductor y **no forma parte de las pautas de taller**: en SICOM vive en el
checklist pre-operativo diario. Sin cambios.

---

**Aplicación:** MIG517 aplica los puntos 1-5 del §3 sobre las pautas activas
de Actros, Axor y Atego (la escalera Accelo no tiene turbo grande ni AdBlue
en la misma configuración; sólo se le corrige el ítem del filtro de aire).
