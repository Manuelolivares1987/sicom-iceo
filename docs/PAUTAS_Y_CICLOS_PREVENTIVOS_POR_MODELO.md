# Pautas y ciclos de mantenimiento preventivo por modelo de la flota

**Investigación técnica — 04-09-2026**
Preparada a pedido de Manuel Olivares: *«que el sistema ayude a planificar preventivas y, sobre todo, a realizar un pedido con anticipación de la preventiva; investigar en profundidad, para cada modelo de la flota, las pautas y los ciclos de mantenimiento»*.

Base de datos usada: flota real en SICOM al 04-09-2026 (68 activos vigentes), pautas cargadas en `pautas_fabricante` (85), lecturas de horómetro/km del sistema, y los sistemas de mantenimiento de cada fabricante (referencias al final).

---

## 1. La idea central: la ESCALERA y el CICLO son lo mismo, visto de dos lados

Manuel lo describió con el ejemplo Mercedes: *«después de una SL viene una S1, pero después vuelve a SL»*. Eso es exactamente cómo funcionan los planes de todos los fabricantes de camiones:

- El fabricante define **servicios escalonados**: uno chico frecuente (SL — lubricación) y mayores cada vez más completos (S1, S2, S3…), cada uno con SU intervalo (ej: SL cada 200 h, S1 cada 400 h, S2 cada 800 h…).
- En la práctica, el taller ve un **ciclo alternado**, porque el servicio mayor **absorbe** al menor cuando coinciden:

```
horas:    200   400   600   800   1000  1200  1400  1600
visita:   SL    S1    SL    S2    SL    S1    SL    S3
                (S1 incluye lo de la SL — no se hacen las dos)
```

**El sistema ya tiene la escalera cargada** (las 85 pautas de MIG490: Actros SL 200 h / SM1 400 / SM2 800 / SM3 1600…, Mack SL 250 / SM1 500 / SM2 1000 / SM3 3000, etc.). Lo que le falta es:

1. **La regla de absorción**: cuando a las 400 h toca SM1, el sistema hoy también «debe» la SL de las 400 — puede generar dos OT donde el manual manda una.
2. **Los kits de materiales por pauta**: de las 85 pautas, **solo 10 tienen materiales cargados**. Sin kit no hay pedido anticipado posible.
3. **Modelos sin pauta**: ver §3 — el hueco más grave es **Scania (7 camiones, los más nuevos de la flota: CERO pautas)**.
4. **La coherencia del B11.04**: el «próximo horómetro de pauta» hoy se calcula como *lectura + 300 h* fijo (MIG496); debería salir del **ciclo del modelo** (el próximo peldaño de SU escalera).

---

## 2. La flota, agrupada para efectos de mantenimiento

| Grupo | Unidades | Modelos | Se administra por |
|---|---|---|---|
| Camiones Mercedes-Benz | 14 | Actros 3336K (5) · Actros 3341 (2) · Atego 1624A 4x4 (2) · Accelo 1016 (3) · Axor 2633 (2) | **Horas**, servicio extremo |
| Camiones Volvo | 11 | FMX 420 (6) · FMX 540 (1) · VM 350 (4) | Horas, servicio extremo |
| Camiones Scania | 7 | P450 B (7) | Horas — **SIN PAUTAS EN SICOM** |
| Camiones Mack | 6 | GU813 (autom/Allison/mec) | Horas — los de mayor uso (7.800–16.700 h) |
| Otros camiones | 2 | Renault C440 (1) · Mitsubishi Canter (1) | Horas / km |
| Camionetas | 12 | Hilux (4) · NP300 (3) · Maxus T60 (2) · Berlingo (2) · Montana (1) · RAM 1500 (1) | **Kilómetros**, condición severa |
| Bombas y compresores | 5 | Atlas Copco WEDA D60N (4) · XAS 185 (1) | Horas |
| Grúas horquilla | 2 | Toyota 02-7FDA50 · Yale GDP 30TK | Horas |
| Surtidores / estanques | 8 | Gilbarco · Tokheim · Wayne · estanques | Calendario (normativo) |

---

## 3. Ciclo recomendado por marca (servicio extremo / minería)

Los intervalos de fábrica son para carretera. En faena minera (polvo, ralentí alto, caminos de mina, carga máxima) **todos los fabricantes mandan el intervalo severo**, que en la práctica chilena de minería es **cada 250–300 h la visita de lubricación**. Los números de esta sección son la **recomendación base**; la letra chica de cada unidad debe validarse contra su manual (o Kaufmann / Scania Chile / el dealer que corresponda) antes de sembrarlos — la columna «estado» lo marca.

### 3.1 Mercedes-Benz (Actros · Axor · Atego · Accelo) — 14 camiones

MB estructura el plan en **Servicio de lubricación (SL)** y **servicios mayores escalonados**. La escalera ya cargada en SICOM (SL 200 / SM1 400 / SM2 800 / SM3 1600 / SM4 3200) es consistente con el esquema severo de MB.

| Visita (cada 200 h) | Servicio | Contenido esencial |
|---|---|---|
| 200 h | **SL** | Aceite motor + filtro aceite, engrase general, inspección fugas/niveles, revisión visual frenos |
| 400 h | **S1** (absorbe SL) | SL + filtros combustible (primario y separador de agua) + filtro aire (revisar/soplar) + reapriete |
| 600 h | SL | — |
| 800 h | **S2** (absorbe S1) | S1 + filtro aire (cambio) + filtro cabina + revisión embrague/frenos a fondo + análisis aceite |
| 1000 h | SL | — |
| 1200 h | S1 | — |
| 1400 h | SL | — |
| 1600 h | **S3** (absorbe S2) | S2 + aceites de caja y diferenciales + refrigerante (según análisis) + secador de aire + correas |

**Estado**: escalera cargada ✅ · absorción NO implementada ❌ · kits ❌ (0 de 44 pautas MB con materiales, salvo 1).
**Nota**: el Atego 1624A 4x4 (FJTJ-60/61, aljibes) opera con SL 200 h — coherente con lo cargado. El Accelo 1016 (3 unidades) es liviano: puede llevar ciclo 250 h.

### 3.2 Volvo (FMX 420/540 · VM 350) — 11 camiones

Volvo estructura **Servicio Básico** (aceite+filtros) y servicios escalonados; el plan minero típico parte en 400 h y escala 800→1200→1600→2400→4800 h, con reducción para operación severa. SICOM ya tiene 15 pautas Volvo cargadas.

| Visita (cada 250–300 h severo) | Servicio | Contenido esencial |
|---|---|---|
| 300 h | **Básico** | Aceite motor + filtros aceite (full-flow y bypass), engrase, inspección |
| 600 h | **Básico+** | Básico + filtros combustible + separador agua + revisión frenos |
| 900 h | Básico | — |
| 1200 h | **Completo** | Básico+ + aceite caja (I-Shift: según análisis) + filtro aire + secador |
| …1600 h | Diferenciales | Aceite ejes traseros |

**Estado**: escalera cargada ✅ (3 modelos) · kits: solo 3 pautas con materiales ⚠.
**Nota**: FMX 420/540 son los cisterna/tolva de faena — candidatos a intervalo severo de 250 h; VM 350 (semipesado) puede sostener 300 h.

### 3.3 Scania (P450 B) — 7 camiones ⚠ EL HUECO MÁS GRAVE

Los 7 Scania son **los camiones más nuevos de la flota** (≈580 h promedio) y **no tienen ni una pauta en SICOM**: hoy el sistema no puede decir cuándo les toca nada.

Scania organiza el mantenimiento en **paquetes modulares**: **S** (chico: aceite+filtro), **M** (mediano: S + combustible/aire) y **L/XL** (grande), con variantes M+Z1, M+Z2 según componentes, y un **ciclo minero** documentado. Para XT/minería el aceite va en 250–500 h según severidad y calidad de aceite.

**Ciclo recomendado para sembrar (a validar con Scania Chile / manual de cada VIN):**

| Visita (cada 250 h) | Servicio | Contenido esencial |
|---|---|---|
| 250 h | **S** | Aceite motor + filtro, engrase, inspección |
| 500 h | **M** (absorbe S) | S + filtros combustible + separador + revisión aire |
| 750 h | S | — |
| 1000 h | **L** (absorbe M) | M + filtro aire + caja/retarder según análisis + secador |
| …2000 h | XL | mayor completo |

**Acción**: sembrar estas 4-5 pautas para el modelo P450B **es lo primero** — 7 camiones nuevos acumulando horas sin plan es cómo se pierde una garantía.

### 3.4 Mack (GU813) — 6 camiones, los abuelos de la flota

Ya cargado: SL 250 / SM1 500 / SM2 1000 / SM3 3000 (+365 días). Con 7.800–16.700 h por unidad, en estos camiones **manda la condición tanto como el ciclo**: recomendación de sumar **análisis de aceite en cada SM1** (espectrometría) — a esta edad el análisis anticipa la falla mayor mejor que cualquier pauta.

### 3.5 Renault C440 (1) y Mitsubishi Canter (1)

C440 cargado (500/1000/2500/6000/8000 h — escalera Volvo Group, coherente). Canter **sin pauta**: sembrar ciclo liviano por km (10.000 severo 5.000) o 250 h.

### 3.6 Camionetas (12 unidades) — por kilómetros, condición severa

Regla de industria minera en Chile: **mantención cada 10.000 km alternando chica/grande, reducida a 5.000–7.500 km en condición severa** (caminos de tierra/mina). Ciclo genérico recomendado:

| Visita (cada 10.000 km · severo 7.500) | Servicio | Contenido |
|---|---|---|
| 10.000 | **Chica** | Aceite + filtro aceite + rotación neumáticos + inspección |
| 20.000 | **Media** (absorbe chica) | Chica + filtro aire + filtro combustible + filtro polen + frenos |
| 40.000 | **Grande** (absorbe media) | Media + líquido frenos + alineación/balanceo + correas + bujías (bencineras) |

**Estado**: solo NP300 (3 pautas) y una Hilux (1) tienen algo. **Faltan**: New Hilux (3), Maxus T60 (2), Berlingo (2), Montana (1), RAM 1500 (1). La NP300 con ~209.000 km es la prioridad de condición.

### 3.7 Equipos de apoyo

- **Bombas WEDA D60N (4, ~2.800 h)**: sin pauta. Ciclo eléctrico: inspección sellos/aceite de sello **cada 500 h**, revisión completa 1.000 h. Sembrar.
- **Compresor XAS 185**: cargado (PM 500 h con 3 materiales ✅ — es el formato al que hay que llegar en todo).
- **Grúas horquilla (2)**: sin pauta → 250 h chica / 1.000 h grande.
- **Surtidores**: pautas mensual/trimestral cargadas ✅ (normativo SEC — no tocar).

---

## 4. El pedido ANTICIPADO de la preventiva — diseño propuesto

Esto es lo que Manuel más pidió, y hoy es imposible: **75 de 85 pautas no tienen materiales**. El diseño, reutilizando lo que ya existe:

### 4.1 El kit por pauta
`pautas_fabricante.materiales_estimados` (JSONB, ya existe) se llena con el **kit**: producto de bodega (o descripción + n° de parte) y cantidad. Ejemplo SL Actros: aceite 15W-40 ×36 L, filtro aceite ×1, grasa ×2 kg. Ejemplo S1: kit SL + filtro combustible ×1 + separador ×1.

### 4.2 La regla de anticipación
El motor de MIG421-423 **ya proyecta cuándo toca** cada pauta usando el ritmo real de horas/día del equipo. La regla nueva:

> Cuando a un equipo le falten **≤ N horas** para su próxima pauta (N = ritmo diario × días de lead time del kit, por defecto **50 h ≈ 1 semana**), el sistema genera automáticamente la **solicitud del kit**:
> - si hay stock en bodega → **reserva** (aparece en el tablero de bodega como «preparar kit para pauta»),
> - si no hay stock → entra a **«Por comprar»** en Seguimiento de repuestos, con el correo a compras del ciclo que ya armamos.

Así el camión llega a su pauta **con el kit sobre el mesón** — cero días parado esperando filtros.

### 4.3 La regla de absorción
Al calcular «qué toca», si en la misma ventana vencen la SL y un servicio mayor del mismo equipo, **se programa solo el mayor** (que incluye al menor) y la SL se marca «absorbida». Una OT, no dos.

### 4.4 El B11.04 sale del ciclo
El «próximo horómetro de pauta» deja de ser lectura+300 fija: pasa a ser **el próximo peldaño de la escalera del modelo** (ej: Actros en 4.850 h → próxima = 5.000 h, y es S2). Cambio chico en `rpc_taller_registrar_medidores`.

---

## 5. Plan de implementación sugerido (en orden de dolor)

| # | Acción | Impacto | Esfuerzo |
|---|---|---|---|
| 1 | **Sembrar pautas Scania P450** (validando intervalos con Scania Chile) | 7 camiones nuevos entran al plan | 1 migración |
| 2 | **Cargar kits de materiales** en las pautas de camiones (MB, Volvo, Mack, Scania) — partir por SL/S y S1/M, que son el 80 % de las visitas | habilita el pedido anticipado | trabajo de datos con bodega (códigos reales) |
| 3 | **Regla de anticipación** (≤50 h → reserva/compra del kit) + tarjeta en bodega | el pedido con anticipación que pidió Manuel | 1 migración + UI |
| 4 | **Regla de absorción** en el cálculo de vencimientos | una OT por visita, no dos | 1 migración |
| 5 | B11.04 desde el ciclo del modelo | coherencia total | cambio chico |
| 6 | Sembrar camionetas + bombas WEDA + grúas | flota completa cubierta | 1 migración |
| 7 | Sanar líneas base: 127/215 pautas sin base de horómetro se corrigen solas al cerrar la **primera** preventiva de cada equipo en SICOM (MIG420) — priorizar cerrar una preventiva por equipo | el motor calcula con datos reales | operación, no código |

**Advertencia de gerente de mantenimiento**: los pasos 1 y 2 requieren validar contra el manual de cada modelo (o el dealer) los intervalos exactos y los números de parte — esta investigación entrega la estructura y los valores de industria para servicio extremo, no reemplaza la pauta oficial de cada VIN. Lo que NO hay que hacer es esperar esa validación para el Scania: sembrar hoy con 250 h severo y ajustar después es infinitamente mejor que 7 camiones sin plan.

---

## Referencias

- Scania — [mantenimiento periódico series L/P/G/R/S (paquetes S/M/L, ciclo minero)](https://test-til.scania.com/groups/cvs/documents/cvs/xzaw/mdaw/~edisp/cvs_0000009_03.pdf) · [Scania minería](https://www.scania.com/mx/es/home/transport-operations/mining/mineria-subterranea.html)
- Volvo Trucks — [programa de mantenimiento FMX (400 h → escalado, reducción por severidad)](https://www.scribd.com/doc/175586833/Plan-de-Mantenimiento-Volvo-Fmx) · [manual de mantenimiento preventivo Servicio Básico](https://sb450a336796059b7.jimcontent.com/download/version/1461167612/module/5850089918/name/MANUAL%20DE%20VOLVO.pdf)
- Sistemas de servicio MB (SL/S1-S3) y Mack (SL/SM1-SM3): nomenclatura y escaleras ya validadas en las pautas cargadas en SICOM (MIG490), consistentes con los planes de mantenimiento de los fabricantes para operación severa.
- Datos de flota, uso y pautas: SICOM producción, 04-09-2026 (`diag_flota_modelos.sql`, `diag_pautas_por_marca.sql`).
