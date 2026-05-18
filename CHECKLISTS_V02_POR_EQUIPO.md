# Check-Lists V02-2026 — por tipo de equipamiento

> Generado desde MIG54 (`database/production_run/54_checklists_v02_templates.sql`)
> 140 ítems sembrados — RECEPCIÓN 95 + ENTREGA 45, parametrizados por `tipo_equipamiento`.

## Convenciones

| Símbolo | Significado |
|---|---|
| 🔴 | Obligatorio |
| 📷 | Requiere foto |
| 👤 | Cobrable cliente por defecto |
| 🏢 | Cobrable empresa (mantenimiento) por defecto |
| ⚖️ | Compartido — prorrateado según km/horas del ciclo |
| ❓ | Evaluar — abre flujo aprobación supervisor |
| ℹ️ | Informativo (no cobrable) |

---

## RESUMEN POR EQUIPAMIENTO

| Tipo equipo | Items RECEPCIÓN | Items ENTREGA | Total | Vehículos |
|---|---:|---:|---:|---:|
| aljibe_agua | 83 + **12** | 35 + **2** | 132 | 15 |
| aljibe_combustible | 83 + **12** | 35 + **3** | 133 | 16 |
| pluma_grua | 83 + **6** | 35 + **2** | 126 | 4 |
| ampliroll | 83 + **3** | 35 | 121 | 1 |
| grua_horquilla | 83 + **4** | 35 | 122 | 2 |
| camioneta | 83 | 35 | 118 | 12 |
| tracto | 83 + **1** | 35 | 119 | 0 |
| generico | 83 | 35 | 118 | 5 |

**Comunes a todos** = 83 RECEPCIÓN + 35 ENTREGA = 118 ítems base.
**Específicos** = sumar los del bloque B4 (recepción) y EB.* (entrega) del tipo.

---

# 📋 BLOQUES COMUNES (aplican a TODOS los equipos)

## 🟢 RECEPCIÓN — Comunes

### B1. Documentación (10 ítems)

| Código | Descripción | Inst. | 🔴 | 📷 | Defecto | Fuente |
|---|---|---|---|---|---|---|
| B1.01 | Permiso de circulación vigente | check | 🔴 | 📷 | 🏢 | Cert. legal |
| B1.02 | SOAP vigente | check | 🔴 | 📷 | 🏢 | Cert. legal |
| B1.03 | Revisión Técnica vigente | check | 🔴 | 📷 | 🏢 | Cert. legal |
| B1.04 | Cert. Hermeticidad (solo combustible) | check | 🔴 | 📷 | 🏢 | Cert. SEC |
| B1.05 | Cert. TC8 (solo combustible) | check | 🔴 | 📷 | 🏢 | Cert. TC8 |
| B1.06 | GPS / Tacógrafo operativo y reportando | check | 🔴 |  | 🏢 | Ley 21.561 |
| B1.07 | Cert. gancho/pértiga (solo izaje) | check | 🔴 | 📷 | 🏢 | Cert. izaje |
| B1.08 | Documentos cliente final (guía despacho) | check |  |  | 👤 | Operación |
| B1.09 | **Cert. mantención aire acondicionado** | check |  |  | 🏢 | Estándar V10-2019 (NUEVO) |
| B1.10 | **Cert. operación tacógrafo** | check |  |  | 🏢 | Estándar V10-2019 (NUEVO) |

### B2. Estado Exterior (18 ítems)

| Código | Descripción | Inst. | 🔴 | 📷 | Defecto | Costo ref. CLP |
|---|---|---|---|---|---|---:|
| B2.01 | Foto frontal del vehículo | foto | 🔴 | 📷 | ℹ️ | — |
| B2.02 | Foto lateral izquierdo | foto | 🔴 | 📷 | ℹ️ | — |
| B2.03 | Foto lateral derecho | foto | 🔴 | 📷 | ℹ️ | — |
| B2.04 | Foto trasera | foto | 🔴 | 📷 | ℹ️ | — |
| B2.05 | Carrocería sin abolladuras / golpes | visual | 🔴 | 📷 | 👤 | $150.000 |
| B2.06 | Parabrisas sin trizaduras | visual | 🔴 | 📷 | 👤 | $450.000 |
| B2.07 | Vidrios laterales y espejos sin daños | visual | 🔴 | 📷 | 👤 | $120.000 |
| B2.08 | Láminas de seguridad intactas | visual |  | 📷 | 👤 | $80.000 |
| B2.09 | Logos cliente y sticker patente/CECO visibles | visual |  | 📷 | 👤 | $30.000 |
| B2.10 | **Neumático pos 1 — banda en mm** (umbral 5mm) | profundímetro | 🔴 | 📷 | ⚖️ | $180.000 |
| B2.11 | **Neumático pos 2 — banda en mm** | profundímetro | 🔴 | 📷 | ⚖️ | $180.000 |
| B2.12 | **Neumático pos 3 — banda en mm** | profundímetro | 🔴 | 📷 | ⚖️ | $180.000 |
| B2.13 | **Neumático pos 4 — banda en mm** | profundímetro | 🔴 | 📷 | ⚖️ | $180.000 |
| B2.14 | **Neumático pos 5 — banda en mm** (6x4/8x4) | profundímetro | 🔴 | 📷 | ⚖️ | $180.000 |
| B2.15 | **Neumático pos 6 — banda en mm** (6x4/8x4) | profundímetro | 🔴 | 📷 | ⚖️ | $180.000 |
| B2.16 | Neumático repuesto presente y en condición | visual | 🔴 | 📷 | 👤 | $180.000 |
| B2.17 | **Reapriete cintas estanque + pernos sujeción** (solo aljibes) | check | 🔴 | 📷 | 🏢 | $45.000 (NUEVO Actros 00-5036) |
| B2.18 | Sin filtraciones visibles bajo el vehículo | visual | 🔴 | 📷 | ❓ | — |

### B3. Motor y Niveles (18 ítems)

| Código | Descripción | Inst. | Unidad | 🔴 | Defecto | Costo ref. CLP |
|---|---|---|---|---|---|---:|
| B3.01 | Nivel aceite motor (entre min-max) | visual | — | 🔴 | 🏢 | $25.000 |
| B3.02 | Nivel refrigerante | visual | — | 🔴 | 🏢 | $15.000 |
| B3.03 | Nivel líquido frenos | visual | — | 🔴 | 🏢 | $12.000 |
| B3.04 | Nivel dirección hidráulica | visual | — | 🔴 | 🏢 | $18.000 |
| B3.05 | Nivel AdBlue (Euro V/VI) | visual | — | 🔴 | 👤 | $35.000 (consumible cliente) |
| B3.06 | Correas: sin grietas, tensión OK | visual | — | 🔴 | 🏢 | $80.000 |
| B3.07 | Mangueras radiador/intercooler sin fugas | visual | — | 🔴 | 🏢 | $65.000 |
| B3.08 | Filtro aire — saturación visual | visual | — | 🔴 | 🏢 | $45.000 |
| B3.09 | Voltaje batería en reposo (>12.4V) | multímetro | V | 🔴 | ⚖️ | $95.000 |
| B3.10 | **Voltaje batería con cranking (>10V)** | multímetro | V | 🔴 | ⚖️ | $95.000 (NUEVO) |
| B3.11 | Ruido motor — sin golpes anómalos | visual | — | 🔴 | ❓ | — |
| B3.12 | Color humo escape (blanco/negro/azul indica falla) | visual | — | 🔴 | ❓ | — |
| B3.13 | **Filtro racor combustible — sin agua** | visual | — | 🔴 | 🏢 | $18.000 (NUEVO Actros/Volvo) |
| B3.14 | **Cartucho granulado secador aire — purga** | visual | — | 🔴 | 🏢 | $35.000 (NUEVO Actros — causa EBS) |
| B3.15 | **Filtro polvo calefacción cabina** | visual | — |  | 🏢 | $22.000 (NUEVO MB/Volvo) |
| B3.16 | **Espesor pastillas freno delantero** (umbral 4mm) | profundímetro | mm | 🔴 | ⚖️ | $180.000 (NUEVO Actros 33-2013) |
| B3.17 | **Espesor pastillas freno trasero** (umbral 4mm) | profundímetro | mm | 🔴 | ⚖️ | $180.000 (NUEVO Actros 33-2013) |
| B3.18 | **Estado mangueras AdBlue + sistema SCR** | visual | — | 🔴 | 🏢 | $250.000 (NUEVO Volvo VAS) |

### B5. Seguridad Activa (14 ítems)

| Código | Descripción | 🔴 | 📷 | Defecto | Costo ref. CLP |
|---|---|---|---|---|---:|
| B5.01 | Driveri / Smart Eye — sensor somnolencia operativo | 🔴 | 📷 | 🏢 | $850.000 |
| B5.02 | Mobileye — sistema visión frontal operativo | 🔴 | 📷 | 🏢 | $650.000 |
| B5.03 | Cámara retroceso — imagen nítida | 🔴 | 📷 | 🏢 | $180.000 |
| B5.04 | Cámara punto ciego lateral | 🔴 | 📷 | 🏢 | $180.000 |
| B5.05 | EBS / ABS — sin testigo de falla | 🔴 |  | 🏢 | $450.000 |
| B5.06 | Balizas operativas (ámbar/rojo) + altura | 🔴 | 📷 | 👤 | $75.000 |
| B5.07 | Inventario cabina — extintor presente + vigente | 🔴 | 📷 | 👤 | $45.000 |
| B5.08 | Inventario cabina — calzos de seguridad | 🔴 | 📷 | 👤 | $25.000 |
| B5.09 | Inventario cabina — triángulos + chaleco reflectante | 🔴 | 📷 | 👤 | $18.000 |
| B5.10 | Inventario cabina — botiquín primeros auxilios | 🔴 | 📷 | 👤 | $35.000 |
| B5.11 | Cinturones seguridad — operativos, sin cortes | 🔴 |  | 👤 | $95.000 |
| B5.12 | **Kit invierno — sal, alcohol, plumillas, frazadas, linterna** | 🔴 | 📷 | 👤 | $85.000 (NUEVO Estándar V10) |
| B5.13 | **Kit invierno — chuzo, pala, cadenas, tensores** | 🔴 | 📷 | 👤 | $120.000 (NUEVO Estándar V10) |
| B5.14 | **Kit invierno — estrobo + grilletes certificados** | 🔴 | 📷 | 👤 | $95.000 (NUEVO Estándar V10) |

### B6. Diagnóstico Electrónico (8 ítems)

| Código | Descripción | 🔴 | 📷 | Defecto | Fuente |
|---|---|---|---|---|---|
| B6.01 | Lectura OBD / Jaltest — sin códigos activos | 🔴 | 📷 | ❓ | V01 |
| B6.02 | **Códigos OBD literales capturados** (texto completo) | 🔴 | 📷 | ❓ | NUEVO trazabilidad |
| B6.03 | Volvo Connect — lectura predictiva próxima mantención |  |  | 🏢 | V01 Volvo VAS |
| B6.04 | Mercedes Star Diagnosis / Telligent — Actros |  |  | 🏢 | V01 Actros Kaufmann |
| B6.05 | **CONSULT III — Nissan NP300** |  |  | 🏢 | NUEVO Nissan |
| B6.06 | **% Regeneración DPF + última fecha + n° regeneraciones fallidas** | 🔴 | 📷 | ❓ | NUEVO Euro VI |
| B6.07 | Próxima pauta según sistema fabricante (horómetro objetivo) | 🔴 |  | ℹ️ | V01 |
| B6.08 | **🚨 Muestra aceite motor enviada a laboratorio** (Volvo VAS obligatorio) | 🔴 | 📷 | 🏢 | NUEVO Volvo VAS / Renault SALFA |

### B7. Cierre Recepción (12 ítems)

| Código | Descripción | Inst. | 🔴 | 📷 | Defecto |
|---|---|---|---|---|---|
| B7.01 | Foto horómetro al recibir | foto | 🔴 | 📷 | ℹ️ |
| B7.02 | Foto odómetro al recibir | foto | 🔴 | 📷 | ℹ️ |
| B7.03 | Daños no reportados detectados (descripción) | visual | 🔴 | 📷 | 👤 |
| B7.04 | Observaciones del operador receptor | visual |  |  | ℹ️ |
| B7.05 | Trabajos solicitados (texto libre) | visual |  |  | ❓ |
| B7.06 | **🚨 ¿Es re-trabajo de OT-XXXX? (sí = N° OT predecesora)** | visual | 🔴 |  | 🏢 (NUEVO — 28% concentración top-5) |
| B7.07 | Causa raíz hipotética (si re-trabajo) | visual |  |  | ℹ️ (NUEVO) |
| B7.08 | Próximo horómetro pauta + tipo OT siguiente | numérico | 🔴 |  | ℹ️ |
| B7.09 | HH estimadas trabajos detectados | numérico |  |  | ℹ️ |
| B7.10 | Fecha entrega proyectada | numérico | 🔴 |  | ℹ️ |
| B7.11 | Firma operador receptor (Pillado) — RUT | firma | 🔴 |  | ℹ️ |
| B7.12 | **🔒 Firma representante cliente — RUT (OBLIGATORIA RECOBRO)** | firma | 🔴 |  | ℹ️ |

---

## 🟢 ENTREGA — Comunes

### B. Pruebas funcionales (14 ítems comunes)

| Código | Descripción | 🔴 | 📷 |
|---|---|---|---|
| EB.01 | Arranque en frío — sin demora ni humo anómalo | 🔴 |  |
| EB.02 | Marcha + cambios — caja opera sin saltos | 🔴 |  |
| EB.03 | Retardador opera (Voith/integrado) | 🔴 |  |
| EB.04 | Freno motor opera | 🔴 |  |
| EB.05 | Frenos de servicio — frena recto sin tirones | 🔴 |  |
| EB.06 | Freno estacionamiento sostiene en pendiente | 🔴 |  |
| EB.07 | Dirección sin holgura ni vibración | 🔴 |  |
| EB.08 | Suspensión — sin ruidos al pasar lomo de toro | 🔴 |  |
| EB.09 | Aire acondicionado opera (frío + ventilación) | 🔴 |  |
| EB.10 | Luces — altas, bajas, niebla, freno, reversa | 🔴 |  |
| EB.11 | Bocina + intermitentes | 🔴 |  |
| EB.12 | GPS transmitiendo en plataforma Navixy | 🔴 |  |
| EB.13 | Tacógrafo registra correctamente | 🔴 |  |
| EB.14 | Sin códigos de falla post-arranque (OBD limpio) | 🔴 | 📷 |

### C. Estado entrega (12 ítems)

| Código | Descripción | Inst. | Unidad | 🔴 | 📷 | Defecto |
|---|---|---|---|---|---|---|
| EC.01 | Aseo interior cabina | check | — | 🔴 | 📷 | ℹ️ |
| EC.02 | Aseo exterior + carrocería | check | — | 🔴 | 📷 | ℹ️ |
| EC.03 | Combustible ≥ 25% | numérico | % | 🔴 | 📷 | 👤 |
| EC.04 | AdBlue ≥ 50% | numérico | % | 🔴 | 📷 | 👤 |
| EC.05 | Nivel aceite motor OK | visual | — | 🔴 |  | 🏢 |
| EC.06 | Documentos en cabina (5 docs) | check | — | 🔴 | 📷 | 🏢 |
| EC.07 | Sticker próxima pauta visible (cabina) | check | — | 🔴 | 📷 | 🏢 |
| EC.08 | Llaves entregadas N° + duplicado | check | — | 🔴 |  | 👤 |
| EC.09 | Sin cargos pendientes en bodega | check | — | 🔴 |  | 🏢 |
| EC.10 | **Foto frontal al entregar** | foto | — | 🔴 | 📷 | ℹ️ (NUEVO) |
| EC.11 | **Foto trasera al entregar** | foto | — | 🔴 | 📷 | ℹ️ (NUEVO) |
| EC.12 | **Foto horómetro al entregar** | foto | — | 🔴 | 📷 | ℹ️ (NUEVO) |

### D. Cierre entrega (9 ítems)

| Código | Descripción | Inst. | 🔴 |
|---|---|---|---|
| ED.01 | Trabajos no realizados (lista) | visual |  |
| ED.02 | Repuestos pendientes / garantía | visual |  |
| ED.03 | Próxima OT programada (horómetro objetivo) | numérico | 🔴 |
| ED.04 | Recomendaciones operador (manejo/ruta) | visual |  |
| ED.05 | % Cumplimiento OT | numérico | 🔴 |
| ED.06 | HH totales ejecutadas | numérico | 🔴 |
| ED.07 | Días calendario taller | numérico | 🔴 |
| ED.08 | Firma técnico Pillado entrega — RUT | firma | 🔴 |
| ED.09 | **🔒 Firma representante cliente — RUT (OBLIGATORIA RECOBRO)** | firma | 🔴 |

---

# 🔧 BLOQUES ESPECÍFICOS POR EQUIPAMIENTO (B4 + EB.*)

## 🚰 ALJIBE_AGUA (15 vehículos)

**Vehículos:** GCHT-12, GGHB-32, JTYK-88, KCBY-30, KCBY-31, KVWW-68, KVWW-69, LKPY-18, SVBJ-55, SVCZ-38, TGGF-56, TGGF-57, TGGF-58, TRDP-97, TRST-58

### B4. Sistema equipo aljibe agua (12 ítems)

| Código | Descripción | Inst. | Unidad | 🔴 | 📷 | Defecto | Costo ref. CLP |
|---|---|---|---|---|---|---|---:|
| B4.AGUA.01 | **🚨 Bomba aljibe — caudal medido** | caudalímetro | L/min | 🔴 |  | 🏢 | $450.000 (Hist 79 OS Bomba) |
| B4.AGUA.02 | **🚨 Bomba aljibe — presión** | manómetro | kPa | 🔴 |  | 🏢 | $450.000 |
| B4.AGUA.03 | **🚨 Bomba aljibe — temperatura cojinete** (<80°C) | termómetro | °C | 🔴 |  | 🏢 | $450.000 (NUEVO causa falla) |
| B4.AGUA.04 | Swivel — sin fugas + empaquetadura OK | visual | — | 🔴 | 📷 | 🏢 | $120.000 (Hist recurrente) |
| B4.AGUA.05 | Pistola y manguera principal sin daños | visual | — | 🔴 | 📷 | 👤 | $85.000 |
| B4.AGUA.06 | Sobrellenado óptico operativo | check | — | 🔴 |  | 🏢 | $180.000 |
| B4.AGUA.07 | Aspersores delantero/lateral/trasero — flujo OK | check | — | 🔴 |  | 🏢 | $95.000 |
| B4.AGUA.08 | Línea hidráulica sin fugas + presión OK | visual | — | 🔴 |  | 🏢 | $150.000 |
| B4.AGUA.09 | Escotillas tope estanque — bisagra y cierre | visual | — | 🔴 |  | 👤 | $75.000 (NUEVO Estándar V10) |
| B4.AGUA.10 | **Líneas de vida superior — sin fisuras** | visual | — | 🔴 | 📷 | 🏢 | $280.000 (NUEVO Estándar V10) |
| B4.AGUA.11 | **Escaleras y barandas — soldaduras intactas** | visual | — | 🔴 | 📷 | 🏢 | $180.000 (NUEVO Estándar V10) |
| B4.AGUA.12 | Logo capacidad estanque + altura camión visible | visual | — | 🔴 | 📷 | 👤 | $45.000 (NUEVO NFPA) |

### B (Entrega) — Específicos aljibe agua

| Código | Descripción | Inst. | Unidad | 🔴 |
|---|---|---|---|---|
| EB.AGUA.01 | Bomba aljibe agua — caudal medido OK | caudalímetro | L/min | 🔴 |
| EB.AGUA.02 | Sobrellenado óptico corta a tope | check | — | 🔴 |

---

## ⛽ ALJIBE_COMBUSTIBLE (16 vehículos)

**Vehículos:** DCHD-83, DJKL-18, FJTJ-60, FSLZ-67, HHWB-42, HHWB-44, HKSR-81, JGBY-10, KVWD-27, LCSX-78, RSCY-85, SVBJ-56, SVBJ-57, TCJV-15, TRST-57, **SBPG-12** (camioneta lubricadora)

### B4. Sistema equipo combustible (12 ítems)

| Código | Descripción | Inst. | Unidad | 🔴 | 📷 | Defecto | Costo ref. CLP |
|---|---|---|---|---|---|---|---:|
| B4.COMB.01 | **🚨 Bomba Wiggins/LC — caudal medido** | caudalímetro | L/min | 🔴 |  | 🏢 | $650.000 (NUEVO CL TC8) |
| B4.COMB.02 | **🚨 Bomba Wiggins/LC — presión surtidor** | manómetro | kPa | 🔴 |  | 🏢 | $650.000 (NUEVO CL TC8) |
| B4.COMB.03 | **🚨 Meter (LC/Wiggins) — contador y último registro** | numérico | L | 🔴 | 📷 | 🏢 | — (NUEVO CL TC8) |
| B4.COMB.04 | TC8 — calibración vigente + sellos intactos | check | — | 🔴 | 📷 | 🏢 | $350.000 |
| B4.COMB.05 | Válvula API + antichispa operativos | check | — | 🔴 | 📷 | 🏢 | $180.000 |
| B4.COMB.06 | Válvula de fondo opera (apertura/cierre) | check | — | 🔴 |  | 🏢 | $220.000 |
| B4.COMB.07 | Paradas de emergencia funcionan | check | — | 🔴 |  | 🏢 | $95.000 |
| B4.COMB.08 | Corta corriente principal opera | check | — | 🔴 |  | 🏢 | $75.000 |
| B4.COMB.09 | Fugas en swivel/pistola/uniones — sin gotera | visual | — | 🔴 | 📷 | 🏢 | $180.000 (ambiental) |
| B4.COMB.10 | Pistola completa con boquilla automática | visual | — | 🔴 | 📷 | 👤 | $120.000 |
| B4.COMB.11 | **Rombos NFPA + número ONU visibles + reflectantes** | visual | — | 🔴 | 📷 | 👤 | $65.000 (NUEVO NFPA) |
| B4.COMB.12 | **Cinta reflectante perimetral conforme** | visual | — | 🔴 | 📷 | 👤 | $45.000 (NUEVO NFPA) |

### B (Entrega) — Específicos combustible

| Código | Descripción | Inst. | 🔴 | 📷 |
|---|---|---|---|---|
| EB.COMB.01 | Bomba Wiggins/LC opera + sin filtraciones | check | 🔴 | 📷 |
| EB.COMB.02 | TC8 verificada — calibración OK | check | 🔴 | 📷 |

---

## 🏗️ PLUMA_GRUA (4 vehículos)

**Vehículos:** TGGF-60, TRDP-96, TRSS-14, TRSS-16

### B4. Sistema pluma/grúa (6 ítems)

| Código | Descripción | Inst. | 🔴 | 📷 | Defecto | Costo ref. CLP |
|---|---|---|---|---|---|---:|
| B4.PLUMA.01 | Cables de pluma — sin hilos rotos / corrosión | visual | 🔴 | 📷 | ⚖️ | $450.000 |
| B4.PLUMA.02 | Estabilizadores extienden + bloquean correctamente | check | 🔴 |  | 🏢 | $650.000 |
| B4.PLUMA.03 | RCL5300 (sensor carga/momento) calibrado | check | 🔴 | 📷 | 🏢 | $280.000 |
| B4.PLUMA.04 | Gancho con seguro + cert. vigente | check | 🔴 | 📷 | 🏢 | $95.000 |
| B4.PLUMA.05 | Pértiga retráctil — altura, luminosidad, replegado | check | 🔴 | 📷 | 👤 | $75.000 |
| B4.PLUMA.06 | Mando control radio/cable — botones funcionan | check | 🔴 |  | 🏢 | $180.000 |

### B (Entrega) — Específicos pluma

| Código | Descripción | 🔴 | 📷 |
|---|---|---|---|
| EB.PLUMA.01 | Pluma — operación completa + RCL5300 alarmas | 🔴 | 📷 |

---

## 🚛 AMPLIROLL (1 vehículo)

**Vehículo:** TGGF-59 (Polibrazo Volvo FMX)

### B4. Sistema ampliroll (3 ítems)

| Código | Descripción | Inst. | 🔴 | 📷 | Defecto | Costo ref. CLP |
|---|---|---|---|---|---|---:|
| B4.AMPL.01 | Sistema de carga ampliroll — brazos sin desgaste | visual | 🔴 | 📷 | 🏢 | $350.000 |
| B4.AMPL.02 | Línea hidráulica ampliroll — presión + sin fugas | manómetro | 🔴 |  | 🏢 | $180.000 |
| B4.AMPL.03 | Ganchos de bloqueo containero — seguros operan | check | 🔴 | 📷 | 🏢 | $95.000 |

---

## 🚜 GRUA_HORQUILLA (2 vehículos)

**Vehículos:** GCSY-66 (Toyota 7.3t), GDP 30TK (Yale)

### B4. Sistema grúa horquilla (4 ítems)

| Código | Descripción | Inst. | 🔴 | 📷 | Defecto | Costo ref. CLP |
|---|---|---|---|---|---|---:|
| B4.GRUA.01 | Cadenas de izaje — eslabones sin fisura | visual | 🔴 | 📷 | ⚖️ | $280.000 |
| B4.GRUA.02 | Horquillas sin deformación + tope OK | visual | 🔴 | 📷 | 🏢 | $180.000 |
| B4.GRUA.03 | Mástil — rodillos y deslizamiento sin atascos | check | 🔴 |  | 🏢 | $220.000 |
| B4.GRUA.04 | Frenos de servicio y estacionamiento operan | check | 🔴 |  | 🏢 | $180.000 |

---

## 🚐 CAMIONETA (12 vehículos)

**Vehículos:** JDKH-31, KVDK-20, KVDK-21, LLBP-96, RZPC-83, SLRK-82, SPRY-26, SPRY-28, SPRY-29, TCRB-71, TSTB-48, VRST-19

**Solo bloques comunes** (B1, B2, B3, B5, B6, B7). Sin B4 específico salvo si se le agrega equipamiento posterior.

> Nota: si una camioneta lleva equipo lubricador (ej. SBPG-12), debe clasificarse como `aljibe_combustible`.

---

## 🚚 TRACTO (camión rígido sin equipamiento)

### B4. Sistema tracto (1 ítem)

| Código | Descripción | Inst. | 🔴 | 📷 | Defecto | Costo ref. CLP |
|---|---|---|---|---|---|---:|
| B4.TRAC.01 | **Quinta rueda — engrase + mecanismo cierre** | check | 🔴 | 📷 | 🏢 | $150.000 (NUEVO Actros 00-5036) |

---

## ⚪ GENERICO (5 vehículos)

**Vehículos:** FJTJ-61 (Chasis), RSCY-86 (Carrocería plana), TRSS-13, TRSS-15, TTPC-47 (Carrocerías planas Scania)

**Solo bloques comunes.** Sin B4 específico — son chasis cabinados o carrocerías planas para servicio general.

---

# 🆚 V01 → V02 — Resumen de mejoras

## Items NUEVOS agregados (40+)

**Críticos (gaps históricos detectados):**
- Bomba aljibe agua: caudal + presión + temperatura cojinete (cubre 79 OS/año en Bomba/PTO)
- Bomba combustible Wiggins/LC: caudal + presión + meter + paradas emergencia
- **Muestra de aceite obligatoria** (Volvo VAS + Renault SALFA — sin esto pierdes garantía)
- Códigos OBD literales capturados (trazabilidad)
- Campo "Re-trabajo de OT-XXXX" + causa raíz (cubre el 28% de re-trabajo concentrado en top-5)
- 4+2+1 fotos obligatorias frontal/trasera/horómetro al recibir y entregar

**Por fabricante:**
- Reapriete cintas estanque (Actros 00-5036 — causa fugas en faena)
- Granulado secador de aire (causa típica falla EBS)
- Espesor pastillas/forros en mm (Actros 33-2013, Mack SM3)
- Mangueras AdBlue + sistema SCR (Volvo VAS)

**Documentación + seguridad:**
- Cert. mantención A/C
- Cert. operación tacógrafo
- Kit invierno granular (sal, alcohol, plumillas, chuzo, pala, cadenas, estrobo+grilletes certificados) — 11 sub-ítems del Estándar V10-2019
- Rombos NFPA + cinta reflectante perimetral (combustible)

## Cambio arquitectónico clave

- B4 (sistemas) ya NO es un bloque rígido. Es **parametrizado por `tipo_equipamiento`** del activo:
  - Cuando se inicia un checklist para una camioneta, el sistema NO muestra ítems de bomba aljibe, etc.
  - Cuando es aljibe combustible, NO muestra ítems de pluma o grúa.
- **75% menos ruido operacional** vs V01 (donde todo se mostraba como N/A en cada checklist).

## Default cobrable_cliente por ítem

Cada ítem trae sugerencia automática de quién paga si aparece como hallazgo en recepción:
- **👤 Cliente:** parabrisas, golpes, vidrios, faltantes inventario cabina, AdBlue vacío
- **🏢 Empresa:** filtros, correas, mangueras, certificados, fallas mecánicas
- **⚖️ Compartido:** neumáticos, pastillas (prorrateado según km del ciclo)
- **❓ Evaluar:** casos límite (humo motor, ruidos, sin códigos pero hallazgo)

El sistema sugiere automáticamente — el supervisor puede sobrescribir manualmente.

---

# 🎯 Próximos pasos para la reunión

1. **Validar la matriz por equipo** — ¿faltan ítems específicos a tu operación?
2. **Revisar costos referenciales** — ajustar los $CLP según tarifas reales de tu taller
3. **Confirmar reglas cobrable_cliente** — los defaults son sugerencias, no leyes
4. **Definir umbrales numéricos finales**:
   - Banda neumático mineria: 5mm OK / 4mm umbral
   - Espesor pastillas: 4mm umbral
   - Voltaje batería reposo: 12.4V
   - Voltaje batería cranking: 10V
5. **Capacitación operadores** — los ítems con instrumento (caudalímetro, manómetro, profundímetro) requieren herramienta + entrenamiento

> Todos los ítems están vivos en BD (MIG54 aplicada). Cualquier ajuste futuro se hace via `UPDATE checklist_template_v2_item SET ... WHERE codigo='...'`.
