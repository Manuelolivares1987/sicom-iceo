# Datos reales flota Mack GU 813 (SICOM-ICEO prod) — base para pauta de servicio severo

Extraído 19-11-2026, solo SELECT (transacciones READ ONLY, statement_timeout 15 s, siempre filtrado por activo_id de los 6 Mack).
Helper: `scratchpad/mack/ro.mjs` (pg + .env.supabase-admin.local, `BEGIN READ ONLY` … `ROLLBACK`).

## 0. Flota

| Patente | Código | Modelo SICOM | Año | Uso | Faena / estado hoy | Horómetro ficha | Km ficha |
|---|---|---|---|---|---|---|---|
| HHWB-42 | CC-20-01 | GU 813 autom | 2015 | petrolero 20 kL | Franke, operativo | 25.695,9 | 191.802 |
| HHWB-44 | CC-20-02 | GU 813 autom | 2015 | petrolero 20 kL | Taller Coquimbo, en_mantenimiento | 25.934,6 | 197.184 |
| LCSX-78 | CC-15-17 | GU 813 autom | 2019 | petrolero 15 kL | Franke, operativo | 10.106,2 | 94.422 |
| GCHT-12 | AI-25-01 | GU813E Mec | 2014 | aljibe agua 25 kL | Coquimbo, en venta (V) desde ago | 7.825 | 112.743 |
| LKPY-18 | AI-20-07 | GU 813 autom | 2019 | aljibe agua 20 kL | Coquimbo, disponible | 6.297,9 | 74.451 |
| GGHB-32 | AI-20-03 | GU813E Allison | 2014 | aljibe agua 20 kL | Coquimbo, fuera_servicio | 9.451,4 | 115.864 |

IDs: HHWB-42 ceef7332-…-3074 · HHWB-44 a3150f17-…-80489c · LCSX-78 593e4605-…-2f48207 · GCHT-12 74df9bf8-… · LKPY-18 9b7f44aa-… · GGHB-32 09d170ff-…

## 1. Intensidad de uso

### 1a. GPS diario (activo_horas_dia, Radicom/Navixy) — SÍ hay serie diaria desde 14-09-2026 para los 3 de Franke
(una lectura/día; el brief decía "pocos días": para los Franke ya hay 58 días seguidos. Los de Coquimbo casi sin datos.)

| Patente | Período | ΔH | ΔKm | h/día calendario | km/día cal | km por hora motor | días con ≥1 h | h/día operando (media / mediana / máx) | km/día operando |
|---|---|---|---|---|---|---|---|---|---|
| HHWB-42 | 14-09→19-11 (66 d) | 593,8 | 5.707 | **9,0** | 86 | **9,6** | 49 de 52 pares | **11,5 / 12,0 / 20,2** | 111 |
| LCSX-78 | 14-09→18-11 (65 d) | 399,8 | 3.594 | **6,2** | 55 | **9,0** | 47 de 49 | **7,4 / 5,4 / 16,0** | 59 |
| HHWB-44 | 14-09→17-11 (64 d) | 55,1 | 731 | 0,9 | 11 | 13,3 | 14 de 27 | 2,5 / 2,1 / 10,5 | 44 (en taller desde oct) |

Por mes (GPS):
- HHWB-42: sep (16 d) 5,7 h/d, 14,5 km/h · **oct 9,97 h/d (309 h), 8,7 km/h** · nov (19 d) 10,2 h/d, 8,8 km/h
- LCSX-78: sep 9,5 h/d, 7,8 km/h · oct 5,9 h/d (177 h), 9,8 km/h · nov 3,8 h/d, 9,4 km/h
- HHWB-44: sep 1,7 h/d · oct 0,5 h/d · nov 0,8 h/d (taller)

v_equipo_horas (30 d): HHWB-42 313,9 h / 2.801 km / 27 días con uso / 10,46 h/d; LCSX-78 114,5 h / 1.395 km / 19 días / 3,95 h/d.

### 1b. Lecturas manuales de largo plazo (v_activo_lecturas_horometro: OS histórica, checklist recepción, cambio estado/contrato)

| Patente | Tramo | ΔH | Días | h/día cal | km/h |
|---|---|---|---|---|---|
| HHWB-42 | 15-08-2025 (22.318 h, 163.463 km) → 19-06-2026 (25.073,4 h, 185.359 km) | 2.755 | 308 | **8,9** | 7,9 |
| HHWB-44 | 29-09-2025 (24.233 h, 183.263 km) → 18-06-2026 (25.834,7 h, 197.081 km) | 1.602 | 262 | **6,1** | 8,6 |
| LCSX-78 | 30-05-2026 (9.087,4) → 18-11-2026 (10.106,2) | 1.019 | 172 | **5,9** | — |
| LCSX-78 | 27-03-2026 (9.038 h, 85.962 km) → 18-11-2026 (10.106 h, 94.422 km) | 1.068 | 236 | 4,5 | 7,9 |
| LCSX-78 | 28-06-2025 → 27-03-2026 (Romeral, poco uso) | 347 | 272 | 1,3 | — |
| GCHT-12 | 02-01-2024 (7.352) → 28-08-2026 (7.825) | 473 | 969 | 0,5 | — |
| GGHB-32 | 04-08-2025 (9.258) → 24-08-2026 (9.451) | 193 | 385 | 0,5 | — |
| LKPY-18 | 15-01-2025 (6.182) → 27-10-2026 (6.298) | 116 | 650 | 0,2 | — |

Anualizado a ritmo actual: HHWB-42 ≈ 3.250–3.650 h/año; HHWB-44 ≈ 2.200 h/año (cuando opera); LCSX-78 ≈ 2.150 h/año. Los 3 de Coquimbo < 200 h/año → mandan las fechas (envejecimiento de aceite/refrigerante), no las horas.
Implicancia: a 300 h, HHWB-42 necesita servicio cada **~30–33 días calendario** (≈ cada 2 ciclos 7x7); a 250 h cada ~25–28 días. Con 12 h/día operando, un turno de 7 días ≈ 80 h.

### 1c. Ralentí / PTO (régimen severo)
- **km por hora de motor ≈ 8–10** en los 3 de Franke (GPS y lecturas manuales coinciden: 7,9–9,6). Un camión de ruta típico hace 40–60 km/h motor → la mayor parte de las horas de motor son detenido (ralentí + bomba PTO despachando).
- GPS eventos 30 d (gps_eventos_log, ~1 muestra/hora, filtrado por activo_id):
  - HHWB-42: 401 muestras con ignición, 149 detenido (<3 km/h) = **37 %**; velocidad media en movimiento 26,2 km/h (mediana 23, máx 59).
  - LCSX-78: 384 con ignición, 146 detenido = **38 %**; media en movimiento 24,3 km/h (mediana 19, máx 77).
  - Estimación por balance: horas en movimiento = km/velocidad media → HHWB-42 2.799 km / 26,2 = 107 h de 314 h motor → **≈ 66 % detenido con motor en marcha**; LCSX-78 1.396/24,3 = 57 h de 114 h → **≈ 50 %**.
  - Rango defendible: **ralentí+PTO 37–66 %** → por sobre el 30 % de la regla Mack → usar el intervalo corto de drenaje de aceite.
- activo_horas_dia.ralenti_fin_h / ralenti_fin_l: **vacíos** para los Mack (Radicom no entrega horas de ralentí ni litros de motor).
- **Litros despachados por camión (proxy horas de bomba PTO): SIN DATOS.** combustible_faena_despachos, combustible_ventas_franke, combustible_cargas_camion, combustible_kardex_valorizado y faena_entrega_combustible tienen **0 filas** para los estanques CAM-HHWB42/44/LCSX78 (stock teórico 0). Franke no registra despachos en SICOM (coincide con memoria: "despachos 0"). Único volumen: combustible_abastecimiento_historico (Excel auditoría): 4.148.838 L en 18.255 despachos a 770 equipos de 20 clientes, **sin fecha ni camión** → no sirve para L/día por camión (promedio 227 L/despacho).

## 2. Fallas (correctivas)

Fuentes: historial_os_legacy / os_historico_importado (34 OS 2024-01→2026-03, **sin texto de trabajos**, solo flags y n° trabajos); ordenes_trabajo SICOM (32 OT 2026, 21 canceladas/duplicadas; costos y HH en 0); NC y checklists V03.

### 2a. OS históricas (legacy) por camión
| Patente | OS | Correctivo | Preventivo | Hab. estanque | HH total | Notas |
|---|---|---|---|---|---|---|
| HHWB-42 | 1 | 1 | 0 | 0 | 0 | 15-08-2025 a 22.318 h, 30 trabajos |
| HHWB-44 | 3 | 2 | 0 | 1 | 130 | 01-2025 y 03-2025 en Franke; 29-09-2025 a 24.233 h: 43 trabajos/130 HH (overhaul, sin flag) |
| LCSX-78 | 11 | 9 | 1 (27-03-2026, 9.038 h) | 1 | 180 | 9 correctivas entre 8.589 y 9.038 h (449 h) ≈ 20 por 1.000 h (Romeral) |
| GCHT-12 | 8 | 6 | 1 (19-05-2025, 7.637 h) | 2 | 154 | |
| GGHB-32 | 6 | 4 | 1 (27-01-2026, 9.425 h) | 0 | 204 | |
| LKPY-18 | 5 | 3 | 0 | 1 | 143 | |

### 2b. OT SICOM 2026 no canceladas
| Patente | OT | Tipo | Fechas | Horas al cierre | Contenido |
|---|---|---|---|---|---|
| HHWB-42 | OT-202609-00012 | correctivo | 15-09→13-10 | 25.299 | Recepción/habilitación; NC: panel de instrumentos (no registra temperatura de transmisión), chapa puertas, seguros anclaje cabina/capot, gases |
| HHWB-42 | OT-202609-00035 | inspección | 22-09→03-11 | 25.543 | Entrega arriendo V02; NC 22-09 "códigos de falla post-arranque (OBD)" |
| HHWB-44 | OT-202606-00009 | correctivo | cerrada 05-10 | 25.834,7 | "OT antigua" |
| HHWB-44 | OT-202610-00001 | correctivo | 01-10→05-10 | 25.834,6 | Recepción con **33 NOK** (detalle abajo) |
| HHWB-44 | OT-202610-00004 | correctivo | 14-10 | 25.899,9 | Falla sistema eléctrico: **fusilera con falla interna**; 24 ítems quedan NC |
| HHWB-44 | OT-202610-00003 | preventivo SM3 | 09-11→12-11 | 25.934,6 | ver §4 (incluye frenos traseros, resortes, bujes) |
| HHWB-44 | OT-202610-00020 | correctivo | en ejecución desde 11-11 | — | 24 NC pendientes |
| LCSX-78 | OT-202609-00029 | preventivo SM3 | 05-10 | 9.870,8 | ver §4 |
| GCHT-12 | OT-202608-00011 | correctivo | 30-09→06-10 | 7.825 | habilitación documental |
| GGHB-32 | OT-202607-00040 | correctivo | 30-09→13-10 | 9.451 | habilitación documental |
| LKPY-18 | OT-202607-00018 | correctivo | 09-07 | 6.295,7 | prueba (obs "test") |

**LCSX-78 en Franke: 0 correctivas registradas en 1.068 h (mar→nov 2026)** vs 20/1.000 h en Romeral → casi seguro sub-registro de reparaciones en faena, no confiabilidad real.

### 2c. HHWB-44 recepción 01-10-2026 (25.815 h) — 33 NOK agrupados por sistema
| Sistema | NOK | Detalle |
|---|---|---|
| Eléctrico / iluminación | 9 | luz baja quemada; faeneros traseros no encienden; trocha no enciende; faros; "confecciones directas sin protección ni aislamiento"; **ambas paradas de emergencia desconectadas**; panel: contacto directo en corta-corriente; limpiaparabrisas no funcionan; (14-10 fusilera con falla interna) |
| Inventario seguridad / documentos | 9 | 1 sola cuña (×2 ítems), extintor vencido, sin gata, sin llave de ruedas, 1 solo repuesto (×2), SOAP y permiso vencidos |
| Suspensión / tren delantero | 4 | paquete de resortes pos 2 roto (ruido en rueda), tapa buje trasero rota, tren delantero, ruido suspensión |
| Frenos / retardo | 3 | código ABS en tablero; frenado brusco; **freno motor deficiente** |
| Carrocería / cabina | 3 | broche capot roto; aspa ventilador sin protección; columna de dirección fijada con cinta aislante |
| Diagnóstico electrónico | 2 | códigos de falla en motor y transmisión |
| Fugas | 2 | aparente fuga depósito hidráulico; dirección (suciedad) |
| Sistema de despacho | 2 | **meter y Liquid Control con lecturas erróneas** (prueba de caudal y matraz) → kit reparación Liquid Control pedido |
Repuestos pedidos (ot_recursos_solicitados, OT-202610-00001): paquete de resortes completo ×2, **retenes de masa ×4**, filtro y aceite de dirección, grasa bujes/rodamientos y chasis, 3 paradas de emergencia, focos, ampolletas, terminales, corrugado, broche capot, gata 30 t, cuñas, kit Liquid Control.

### 2d. Downtime (estado_diario_flota 01-01→19-11-2026, 323 días; M=mantención, F=fuera de servicio, R)
| Patente | M | F | R | Total días parado | % | Otros |
|---|---|---|---|---|---|---|
| HHWB-42 | 64 | 18 | 4 | **86** | 27 % | C 108, U 80, A 27 |
| HHWB-44 | 85 | 17 | 0 | **102** | 32 % | C 105, U 85, A 25 |
| LCSX-78 | 29 | 3 | 0 | **32** | 10 % | C 193, U 70 |
| LKPY-18 | 61 | 6 | 7 | 74 | 23 % | D 225 |
| GGHB-32 | 66 | 136 | 3 | 205 | 63 % | |
| GCHT-12 | 5 | 5 | 7 | 17 | 5 % | V 120 |
Episodios: HHWB-42 jul–sep (M/F 63 d seguidos); HHWB-44 may (25 d M) y oct→hoy (50 d M).
horas_operativas/km_recorridos de estado_diario_flota = 0 en todas las filas (no sirven para uso).

### 2e. MTBF
No calculable con rigor: correctivas sin fecha de falla, sin texto en OS legacy, Franke no registra reparaciones. Aproximaciones: HHWB-44 ≈ 6–7 eventos correctivos en ~2.000–3.000 h (≈ 1 cada 400–500 h); HHWB-42 2 eventos en ~2.800 h (sub-registro evidente: pasó 2.755 h sin OS); LCSX-78 Romeral ≈ 1 cada 50 h de motor (≈ 1/mes).

## 3. No conformidades

- **Pauta diaria Franke (FRK-DIA-CP, 28 ítems): 1 sola ejecución en total** (HHWB-44, 24-08-2026, estado borrador, horómetro "2566" erróneo, ningún ítem respondido). **No hay estadística de NOK desde la pauta diaria.** FRK-PM-300 (14 ítems): 0 ejecuciones.
- no_conformidades: 64 filas (HHWB-44 57, HHWB-42 5, GGHB-32 1, LKPY-18 1); todas origen inspección/ejecución OT en taller, la mayoría archivadas. Contenido = los NOK de §2c.
- Checklist V03 recepción (checklist_v2): 34 instancias, NOK totales 60 (HHWB-44 01-10: 33; HHWB-44 06-10: 24 repetidos; HHWB-42: 1 gases; GGHB-32: 1 extintor; LKPY-18: 1 bocina).
- Ítems que más fallan (conteo de ocurrencias NOK en checklists): luces bajas/faeneros/trocha/faros (2 c/u), panel instrumentos (2 + HHWB-42), pernos tablero (2), limpiaparabrisas (2), paquetes de resorte (2), bujes resortes (2), tren delantero (2), aspa (2), cableado (2), paradas de emergencia (2), ABS (2), OBD motor/transmisión (2+2), pruebas de ruta frenos/freno motor/suspensión (2 c/u), fugas (2), caudal/matraz despacho (2 c/u).
- Pauta diaria actual ya cubre: niveles aceite/refrigerante/hidráulico/dirección-frenos, fugas, correas, neumáticos, balatas por visor, purga estanques aire, suspensión, luces, pértiga, baliza, despacho (manguera, cuentalitros, seguros metter, escotilla/válvulas de fondo, derrames), extintor, cuñas, botiquín, kit antiderrame, documentos. **No cubre**: códigos de falla/testigos en tablero, paradas de emergencia, filtro de aire/restricción, separador de agua del diésel, freno motor, temperatura transmisión, horas de bomba/PTO, engrase diario de quinta rueda/crucetas.

## 4. Historial preventivo

### 4a. Planes en SICOM (planes_mantenimiento)
- Escalera Mack SL 300 h / SM1 600 h / SM2 1.200 h / SM3 2.400 h (pautas_fabricante "Mack GU813E", tipo mixto, **sin frecuencia en días ni km**).
- **En los 3 de Franke los planes SL 300 h, SM1 600 h y "Servicio programado 300 h · Mack GU 813" (FRK-PM-300) están activo_plan = false**; solo SM2 y SM3 activos → el motor solo agenda cada 1.200 h.
- Última ejecución registrada:

| Patente | Plan / nivel | Última (h) | Fecha | Horas desde (a hoy) | Comentario |
|---|---|---|---|---|---|
| HHWB-42 | SM2/SM3 (base) | 24.717,6 | sin fecha | **978 h** | v_equipo_horas lo muestra "al_día" con SM2 en 221,7 h; con régimen 300/250 h está **vencido ~680–730 h** |
| HHWB-42 | FRK-PM-300 (inactivo) | 24.963 | sin fecha | 733 h | |
| HHWB-44 | 300 h | 25.585 | 11-08-2026 | — | |
| HHWB-44 | SM3 (OT-202610-00003) | 25.934,6 | 12-11-2026 | 0 | intervalo logrado 25.585→25.934 = 350 h |
| LCSX-78 | 300 h | 9.345 | 03-08-2026 | — | anterior: OS 27-03-2026 a 9.038 (307 h) |
| LCSX-78 | SM3 (OT-202609-00029) | 9.634,7 (checklist 10-09) / 9.870,8 (cierre 05-10) / 9.965,1 (plan SM3 16-10) | | 141–471 h | 3 horómetros distintos para el mismo servicio |
| GGHB-32 | SL..SM3 | 9.446,7 | 27-02-2025 | 5 h | SM3 próxima por fecha 27-02-2026 (vencida) |
| LKPY-18 | SL..SM3 | 6.288 | 09-07-2026 | 10 h | |
| GCHT-12 | SL..SM3 | 7.775,2 | sin fecha | 50 h | |

Intervalos logrados donde hay dos puntos: LCSX-78 307 h y ~290–525 h; HHWB-44 350 h; HHWB-42 sin servicios registrados entre 22.318 h (ago-2025) y hoy, salvo bases de plan sin fecha.

### 4b. Contenido real de los SM3 ejecutados (checklist_v2 momento preventiva)
- LCSX-78 SM3 (10-09/05-10): OK aceite motor 15W40 38 L, refrigerante 50/50 57 L, diferencial delantero+divisor 80W90 18 L, trasero 15 L, dirección ATF220 3,8 L, filtros motor (2+1), kit filtros petróleo/racor/aire/respiradero/dirección/transmisión, correas alternador-A/C y ventilador-bomba, **juego de válvulas**, limpieza estanque combustible. **Caja Allison TES295 48 L + filtros = "na"**.
- HHWB-44 SM3 (05-10/12-11): OK aceite motor, diferenciales, filtros, niveles. **Excluidos**: refrigerante (anual), caja Allison, aceite dirección, correas alternador/ventilador del ítem estándar (sí "cambio de correas" agregado), **juego de válvulas**, limpieza estanque. Agregados correctivos: desarme frenos traseros + rodillos y resortes de freno, paquete resortes delantero derecho, bujes "Bugy" ambos lados, chapa de partida, protecciones.
- → **El cambio de aceite de transmisión no se ha hecho en ningún Mack de Franke** con registro; el ítem Allison "na" en LCSX-78 sugiere que el modelo "GU 813 autom" no lleva Allison (posible mDRIVE) → la pauta tiene el lubricante de caja equivocado/sin definir.
- Lubricantes por nivel (pautas_fabricante.materiales_estimados): SL: aceite 15W40 38 L + 3 filtros aceite (+ filtros combustible/aire/AC según FRK-PM-300); SM1: + diferenciales 18+15 L 80W90 + filtro petróleo + racor; SM2: + filtro dirección, respiradero diferenciales, tensores, turbo (anual/3000 h); SM3: + refrigerante 57 L, caja 48 L, dirección 3,8 L, correas, válvulas, limpieza estanque.

### 4c. Consumo de repuestos registrado en bodega
Casi nulo: salidas_bodega/movimientos_inventario solo 2 × filtro aceite CAT 1R-0751 (HHWB-42, prueba E2E jul-2026). ot_materiales_planeados 0 filas. Lo único útil es ot_recursos_solicitados de HHWB-44 (§2c). No hay base para consumo real de lubricantes por servicio.

## 5. Otros que afectan la pauta

- **Certificados LCSX-78 (operando en Franke) vencidos**: hermeticidad venció 01-04-2026; flujo de descarga y calibración 09-09-2026; torque de ruedas 09-09-2026; óptico sobrellenado 01-10-2026; A/A y ausencia falla ECM 01-10-2026; certificado de mantención 29-07-2026. HHWB-42: hermeticidad vigente a 28-03-2027 (semestral), RT/gases a 27-02-2027, inventario neumáticos 15-09-2026. HHWB-44: hermeticidad 12-05-2027, RT/gases por vencer 05-12-2026. Ciclos observados: hermeticidad 6 meses (Pillado) / 12 meses (OEC SEC); RT y gases 6 meses; flujo descarga, calibración, torque ruedas, óptico, ECM, A/A 12 meses.
- **Neumáticos**: solo certificado "inventario_neumaticos" (sin profundidades, rotaciones ni costo). HHWB-44: retenes de masa ×4 y ruido en rueda pos 2 → revisar extremos de rueda (wheel-end) en la pauta.
- **Análisis de aceite**: no existe tabla ni registro (búsqueda de tablas *aceite*/*muestra*/*tribolog*: 0). No hay base para extender drenajes por análisis.
- **Códigos de falla**: HHWB-42 no registra temperatura de transmisión en panel + OBD activo; HHWB-44 códigos motor+transmisión y ABS → la pauta debe incluir escaneo (Jaltest/Mack PTT) en cada SL.
- **Sistema de despacho**: errores de meter/Liquid Control (HHWB-44) → calibración del cuentalitros como ítem periódico, no solo anual.

## 6. Calidad de datos (no confiar a ciegas)
- Horómetros manuales inconsistentes: HHWB-44 25.815 (01-10) / 25.934,6 (05-10) / 25.899,9 (06-10) vs GPS 25.834–25.840 esos días (GPS ≈ 80–95 h bajo la ficha); HHWB-42 checklist 04-09 = 25.177 h y 116.018 km (errado); LCSX-78 OS 26-02-2026 = 8.616 h / 52.933 km (errado); GGHB-32 OS 15-05-2025 horómetro 108.969 (km y horas invertidos); HHWB-44 km_al_cierre 1.198.080 (corregido en ficha por MIG719).
- Pauta diaria y despachos Franke: prácticamente sin uso (1 pauta borrador, 0 despachos, 0 entregas con litros).
- OS legacy sin descripción de trabajos; OT SICOM con costo y HH = 0.
- Planes con ultima_ejecucion_fecha NULL (HHWB-42, GCHT-12) y próximas fechas absurdas (GGHB-32 2104/2183/2342; LKPY-18 2030–2043) por h/día ≈ 0.
- GPS: muestreo ~1/hora; ignición/velocidad sirven para proporción, no para horas absolutas de ralentí.

## 7. SQL usado (principales)

```sql
-- Mack
select a.id, a.patente, a.codigo, a.estado::text, f.codigo fae, mo.nombre modelo, ma.nombre marca
from activos a left join modelos mo on mo.id=a.modelo_id left join marcas ma on ma.id=mo.marca_id
left join faenas f on f.id=a.faena_id where ma.nombre ilike '%mack%';

-- Lecturas horómetro unificadas (gps, recepción, preventiva, OS, cambio estado/contrato)
select a.patente, l.fecha, l.horometro, l.fuente from v_activo_lecturas_horometro l join activos a on a.id=l.activo_id
where l.activo_id in (<6 ids>) order by 1,2;

-- GPS diario (horas, km)
select a.patente, h.fecha, h.horometro_ini, h.horometro_fin, h.km_ini, h.km_fin, h.ralenti_fin_h
from activo_horas_dia h join activos a on a.id=h.activo_id where h.activo_id in (<3 Franke>) order by 1,2;
-- (deltas diarios y mensuales calculados en Python: scratchpad/mack/an1.py)

-- Proporción detenido con ignición, 30 d (usa idx_gps_log_activo_ts)
select a.patente, count(*) filter (where ignicion) ign, count(*) filter (where ignicion and coalesce(velocidad_kmh,0)<3) still,
 round(avg(velocidad_kmh) filter (where ignicion and velocidad_kmh>=3),1) avg_mov
from gps_eventos_log g join activos a on a.id=g.activo_id
where g.activo_id in ('ceef7332-3469-4695-ae7f-bbff324d3074','593e4605-882d-4e74-b161-42c732f48207')
  and ts_gps >= now()-interval '30 days' group by 1;

-- OS históricas
select a.patente, h.os_numero, h.fecha_recepcion, h.horometro, h.kilometraje, h.flag_mant_prev, h.flag_correctivo,
 h.flag_hab_estado, h.num_trabajos, h.horas_mo, h.detalle_trabajos
from historial_os_legacy h join activos a on a.id=h.activo_id where h.activo_id in (<6 ids>) order by 1,3;

-- OT SICOM
select a.patente, o.folio, o.tipo::text, o.estado::text, o.fecha_inicio::date, o.fecha_termino::date, o.horas_al_cierre,
 o.km_al_cierre, pm.nombre plan, o.observaciones, o.trabajo_realizado
from ordenes_trabajo o join activos a on a.id=o.activo_id left join planes_mantenimiento pm on pm.id=o.plan_mantenimiento_id
where o.activo_id in (<6 ids>) order by 1, o.created_at;

-- NOK de checklists
select a.patente, i.fecha_inicio::date, ti.bloque::text, coalesce(ii.descripcion_custom, ti.descripcion) item, ii.observacion
from checklist_v2_instance_item ii join checklist_v2_instance i on i.id=ii.instance_id join activos a on a.id=i.activo_id
left join checklist_template_v2_item ti on ti.id=ii.template_item_id
where i.activo_id in (<6 ids>) and ii.resultado='no_ok';

-- Contenido de preventivas ejecutadas
select a.patente, coalesce(ii.descripcion_custom, ti.descripcion) item, ii.resultado::text, ii.excluido
from checklist_v2_instance_item ii join checklist_v2_instance i on i.id=ii.instance_id join activos a on a.id=i.activo_id
left join checklist_template_v2_item ti on ti.id=ii.template_item_id
where i.activo_id in (<6 ids>) and i.momento_uso::text='preventiva';

-- Planes
select a.patente, pm.nombre, pm.frecuencia_horas, pm.ultima_ejecucion_fecha::date, pm.ultima_ejecucion_horas, pm.activo_plan
from planes_mantenimiento pm join activos a on a.id=pm.activo_id where pm.activo_id in (<6 ids>);

-- Pauta diaria Franke
select p.codigo, i.orden, i.bloque, i.texto, i.critico from faena_pauta_item i join faena_pauta p on p.id=i.pauta_id
where p.codigo in ('FRK-DIA-CP','FRK-PM-300');
select e.fecha, e.estado, e.horometro, i.texto, x.resultado from faena_pauta_ejecucion_item x
join faena_pauta_ejecucion e on e.id=x.ejecucion_id join faena_pauta_item i on i.id=x.item_id where e.activo_id in (<6 ids>);

-- Despachos por camión (todas 0 filas)
select es.patente, to_char(d.fecha,'YYYY-MM'), sum(d.litros) from combustible_faena_despachos d
join combustible_estanques es on es.id=d.estanque_id where d.estanque_id in (<CAM-HHWB42/44/LCSX78>) group by 1,2;
-- idem combustible_ventas_franke.estanque_movil_id, combustible_cargas_camion, combustible_kardex_valorizado.estanque_id,
--   combustible_movimientos.estanque_id, faena_entrega_combustible

-- Downtime
select a.patente, e.estado_codigo, count(*) from estado_diario_flota e join activos a on a.id=e.activo_id
where e.activo_id in (<6 ids>) and e.fecha between '2026-01-01' and '2026-11-19' group by 1,2;

-- Certificados
select a.patente, c.tipo::text, c.fecha_emision, c.fecha_vencimiento, c.estado::text from certificaciones c
join activos a on a.id=c.activo_id where c.activo_id in (<3 Franke>) and c.anulado_at is null;
```
