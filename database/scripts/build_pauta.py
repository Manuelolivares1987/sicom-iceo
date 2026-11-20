import sys
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

OUT = sys.argv[1]
F = "Arial"
H = Font(name=F, bold=True, color="FFFFFF"); HF = PatternFill("solid", fgColor="1F4E3D")
B = Font(name=F, bold=True); N = Font(name=F); TT = Font(name=F, bold=True, size=14)
BLUE = Font(name=F, color="0000FF"); YEL = PatternFill("solid", fgColor="FFFF00")
RED = PatternFill("solid", fgColor="F8D7DA"); AMB = PatternFill("solid", fgColor="FFF3CD")
GRN = PatternFill("solid", fgColor="D4EDDA")
thin = Side(style="thin", color="BBBBBB"); BOX = Border(top=thin, bottom=thin, left=thin, right=thin)
WR = Alignment(wrap_text=True, vertical="top")


def header(ws, r, cols, widths):
    for i, (c, w) in enumerate(zip(cols, widths), 1):
        x = ws.cell(r, i, c); x.font = H; x.fill = HF; x.alignment = WR; x.border = BOX
        ws.column_dimensions[get_column_letter(i)].width = w


def row(ws, r, vals, font=N, fill=None):
    for i, v in enumerate(vals, 1):
        x = ws.cell(r, i, v); x.font = font; x.alignment = WR; x.border = BOX
        if fill:
            x.fill = fill


wb = Workbook()
# ---------------- Resumen
ws = wb.active; ws.title = "Resumen"
ws["A1"] = "PAUTA MACK GU 813 — SERVICIO SEVERO (propuesta para SICOM)"; ws["A1"].font = TT
ws["A2"] = "Pillado · 19-11-2026 · Base: pauta Pillado v1.0 borrador (09-11) + escalera de la compañía + datos reales de la flota en SICOM"; ws["A2"].font = N
lines = [
    ("CRITERIO", ""),
    ("Escalera", "Se mantiene la escalera de la compañía con absorción (SL 300 · SM1 600 · SM2 1.200 · SM3 2.400 · SM4 4.800 h): el motor de preventivas, el bono y el presupuesto de SICOM funcionan sobre ella. Los niveles PM1–PM6 del Excel 09-11 se mapean al peldaño igual o MÁS CONSERVADOR."),
    ("Lo que ocurra primero", "Horas de motor o días calendario (SICOM ya calcula el primero de horas/km/días con el ritmo medido de cada equipo)."),
    ("Servicio severo", "Franke: 7,9–9,6 km por hora de motor y 50–66 % del tiempo de motor detenido (ralentí + PTO), sobre el 30 % de Mack → aplica el intervalo de drenaje corto."),
    ("Aceite de motor", "Se mantiene cada 300 h (como hoy) + MUESTRA DE ACEITE en cada visita. Con 3 análisis consecutivos OK se puede pasar a 600 h (Mack severo EOS-4.5: 750 h). Hoy no hay ningún análisis registrado: extender sin respaldo sería un riesgo sin dato."),
    ("Diaria", "La revisión diaria de Franke se amplía con lo que la flota mostró que falla y no se revisaba (códigos de tablero, paradas de emergencia, temperatura de transmisión, freno motor, puesta a tierra, válvula de emergencia, separador de agua). No se elimina ningún ítem actual."),
    ("Aplica a", "Tareas 'Aljibe combustible' solo a camiones de combustible (Franke: HHWB-42, HHWB-44, LCSX-78). Transmisión: Allison (TES 668/295) o caja mecánica/mDRIVE según placa — LCSX-78 marcó 'na' en aceite Allison: confirmar tipo de caja."),
    ("", ""),
    ("DATOS DE LA FLOTA (SICOM, 19-11)", ""),
    ("Uso Franke", "HHWB-42: 9,0 h/día calendario (11,5 h los días que opera; octubre = 309 h). LCSX-78: 6,0 h/día. HHWB-44: 6,1 h/día operando. Coquimbo (GCHT-12, GGHB-32, LKPY-18): 0,2–0,5 h/día → manda el calendario."),
    ("Disponibilidad 2026", "Días detenidos: HHWB-42 86 (27 %), HHWB-44 102 (32 %), LCSX-78 32 (10 %)."),
    ("Fallas (HHWB-44, 01-10)", "33 ítems NO OK: eléctrico 9 (paradas de emergencia desconectadas, cableado sin protección, caja de fusibles), suspensión 4 (paquete roto, bujes), frenos 3 (ABS, freno motor débil), códigos motor/transmisión 2, medidor de despacho 2, retenes de cubo x4."),
    ("Brechas de registro", "En Franke casi no se registran correctivos (LCSX-78: 0 OT en 1.068 h); la diaria se usó 1 vez; no hay análisis de aceite ni litros despachados por camión. La pauta funciona solo si se ejecuta y se registra."),
    ("", ""),
    ("FUENTES", "Pauta Pillado v1.0 (09-11) y sus fuentes Mack/Allison/DS 160/DS 298 · SICOM: activo_horas_dia, lecturas de horómetro, OT, checklists, certificados · research_notes/Pauta Mack severa/datos_flota_mack.md"),
]
r = 4
for a, b in lines:
    ws.cell(r, 1, a).font = B; ws.cell(r, 2, b).font = N; ws.cell(r, 2).alignment = WR; r += 1
ws.column_dimensions["A"].width = 28; ws.column_dimensions["B"].width = 120

# ---------------- Escalera (with formulas)
es = wb.create_sheet("Escalera")
es["A1"] = "ESCALERA Y CUÁNDO TOCA CADA SERVICIO"; es["A1"].font = TT
es["A2"] = "Celdas amarillas = editables (h/día medidas en SICOM; horas y tope de cada nivel). Días = MIN(horas ÷ h/día ; tope)."; es["A2"].font = N
header(es, 4, ["Nivel", "Horas", "Tope (días)", "Equivale a (pauta 09-11)", "Contenido"], [10, 12, 12, 26, 90])
lv = [("SL", 300, 30, "PM1 (250 h / 1 mes)", "Inspección general, lubricación de chasis, drenajes, frenos (carrera y fugas), códigos de tablero, aceite + filtros + muestra, sistema de despacho y DS 298 mensual"),
      ("SM1", 600, 90, "PM2 + PM3 (500/750 h; 3–6 meses)", "SL + filtros de combustible y aire, frenos y suspensión en detalle, escape/DEF, transmisión y enfriador, bastidor y anclajes del estanque, filtro de despacho, extintores"),
      ("SM2", 1200, 365, "PM4 (1.500 h / 12 meses)", "SM1 + anuales: aceite de diferenciales, filtro de aire secundario, correas y tensor, CCV, filtro de refrigerante, turbo, compresor, rodamientos, alineación, secador, dirección, calibración del medidor, prueba de mangueras"),
      ("SM3", 2400, 730, "PM5 (3.000 h / 36 meses)", "SM2 + válvulas y freno motor, filtros de transmisión, limpieza del estanque de combustible del chasis, refrigerante si es formulado"),
      ("SM4", 4800, 1460, "PM6 (6.000 h / 48 meses)", "SM3 + fluido de transmisión, refrigerante larga vida, postratamiento (DPF, electrodo, AHI, filtros DEF)")]
for i, (n, h, d, eq, c) in enumerate(lv, 5):
    row(es, i, [n, h, d, eq, c])
    for col in (2, 3):
        es.cell(i, col).font = BLUE; es.cell(i, col).fill = YEL
es.cell(11, 1, "Días hasta cada nivel según el uso medido").font = B
heads = ["Equipo", "h/día calendario", "SL (días)", "SM1 (días)", "SM2 (días)", "SM3 (días)", "SM4 (días)", "Fuente de h/día"]
for i, c in enumerate(heads, 1):
    x = es.cell(12, i, c); x.font = H; x.fill = HF; x.alignment = WR; x.border = BOX
es.column_dimensions["H"].width = 44
trucks = [("HHWB-42", 9.0, "GPS 14-09→19-11 + horómetro ago-25→jun-26"), ("LCSX-78", 6.0, "GPS 14-09→19-11"),
          ("HHWB-44", 6.1, "Horómetro sep-25→jun-26 (operando)"), ("GCHT-12", 0.4, "GPS (Coquimbo)"),
          ("GGHB-32", 0.3, "GPS (fuera de servicio)"), ("LKPY-18", 0.4, "GPS (Coquimbo)")]
for j, (p, hd, src) in enumerate(trucks, 13):
    es.cell(j, 1, p).font = N
    c = es.cell(j, 2, hd); c.font = BLUE; c.fill = YEL; c.number_format = "0.0"
    for k, lvl_row in enumerate(range(5, 10), 3):
        f = es.cell(j, k, "=ROUND(MIN($B$%d/IF($B%d>0,$B%d,0.01),$C$%d),0)" % (lvl_row, j, j, lvl_row))
        f.font = N; f.number_format = "0"
    es.cell(j, 8, src).font = N
    for k in range(1, 9):
        es.cell(j, k).border = BOX

# ---------------- Tareas por nivel
tk = wb.create_sheet("Tareas por nivel")
tk["A1"] = "TAREAS POR NIVEL (el nivel mayor incluye a los menores — absorción)"; tk["A1"].font = TT
header(tk, 3, ["ID", "Nivel", "Sistema", "Tarea", "Tipo", "Aplica a", "Especificación / consumible", "Origen", "Por qué"],
       [8, 6, 16, 60, 11, 18, 34, 16, 46])
T = []


def t(n, s, tarea, tipo, aplica="Todos", esp="—", ori="", porq=""):
    T.append((n, s, tarea, tipo, aplica, esp, ori, porq))


AC = "Aljibe combustible"
# SL
t("SL", "Lecturas", "Horómetro, odómetro y códigos de falla activos (motor, transmisión, ABS, postratamiento) con lector", "Registro", "Todos", "Mack PTT / lector", "C-61 (adelantado)", "Códigos ABS/motor/transmisión activos en HHWB-42/44 sin registro")
t("SL", "Motor", "Cambio de aceite de motor y filtros (2 + 1 adicional). Si la visita es por calendario y van menos de 150 h desde el último cambio: solo nivel + muestra", "Reemplazo", "Todos", "Mack EOS-4.5 15W40 (38–42 L) · filtros genuinos", "SICOM SL + C-01", "Servicio severo (>30 % ralentí); sin análisis de aceite no se extiende")
t("SL", "Motor", "Tomar muestra de aceite de motor para laboratorio (viscosidad, TBN, hollín, metales, combustible, refrigerante)", "Ensayo", "Todos", "Kit de muestra", "C-04", "Habilita extender el aceite a 600 h con 3 análisis OK")
t("SL", "Motor", "Drenar agua del separador de combustible; revisar sensor WIF", "Inspección", "Todos", "—", "C-03")
t("SL", "Motor", "Leer indicador de restricción del filtro de aire; reemplazar el primario si está en máximo", "Inspección", "Todos", "Indicador in H2O", "C-05", "Polvo de faena")
t("SL", "Motor", "Correas de ventilador y accesorios: grietas, desgaste, tensión", "Inspección", "Todos", "—", "C-10")
t("SL", "Motor", "Refrigerante: nivel y concentración (refractómetro)", "Inspección", "Todos", "Refractómetro", "C-13")
t("SL", "Motor", "Radiador, intercooler y condensador: limpieza externa de polvo; mangueras y abrazaderas", "Inspección", "Todos", "Aire a baja presión", "C-16", "Polvo de faena")
t("SL", "Motor", "Soportes de motor, fugas de aceite/combustible/refrigerante, arnés", "Inspección", "Todos", "—", "C-21")
t("SL", "Transmisión", "Nivel y condición del fluido de transmisión (en caliente); fugas; respiradero; temperatura en tablero", "Inspección", "Todos", "Allison TES 668/295 o según placa", "C-27 + dato", "HHWB-42 sin temperatura de transmisión en tablero")
t("SL", "PTO", "Toma de fuerza: montaje, fugas, ruido, activación y mando en cabina", "Inspección", AC, "—", "C-32", "La PTO mueve la bomba: su falla detiene el despacho")
t("SL", "Tren motriz", "Engrase de cardanes: crucetas, yugos deslizantes, soporte central", "Lubricación", "Todos", "Grasa NLGI 2 EP", "C-33")
t("SL", "Tren motriz", "Nivel de aceite de diferenciales, respiraderos, retenes de piñón y de cubos", "Inspección", "Todos", "—", "C-36", "4 retenes de cubo pedidos en HHWB-44")
t("SL", "Tren motriz", "Engrase de pivotes (king pins), extremos de barra y brazos de dirección", "Lubricación", "Todos", "Grasa NLGI 2 EP", "C-38")
t("SL", "Tren motriz", "Cubos delanteros: nivel y condición del aceite", "Inspección", "Todos", "—", "C-39")
t("SL", "Frenos", "Medir carrera de cámaras / ajustadores automáticos; engrasar ajustadores y levas S-cam", "Inspección", "Todos", "Grasa NLGI 2 EP", "C-42", "Frenado brusco en HHWB-44")
t("SL", "Frenos", "Prueba de fugas de aire, gobernador (corte/entrada), freno de estacionamiento, alarma de baja presión", "Ensayo", "Todos", "Manómetro calibrado", "C-46")
t("SL", "Frenos", "Freno motor: prueba funcional en ruta", "Ensayo", "Todos", "—", "Dato flota", "Freno motor débil en HHWB-44")
t("SL", "Frenos", "Drenaje de estanques de aire y válvulas de drenaje automáticas", "Inspección", "Todos", "—", "C-45")
t("SL", "Neumáticos", "Presión, desgaste, daños, torque de tuercas de rueda; registrar profundidad de banda", "Inspección", "Todos", "Torquímetro · profundímetro", "C-50 + dato", "No hay registro de profundidad de banda")
t("SL", "Dirección", "Nivel de fluido, bomba, mangueras, caja, juego libre, rótulas y extremos", "Inspección", "Todos", "—", "C-53")
t("SL", "Suspensión", "Engrase de puntos de suspensión; inspección de paquetes de resortes, hojas y bujes", "Lubricación", "Todos", "Grasa NLGI 2 EP", "C-54 + dato", "Paquete de resortes roto y bujes en HHWB-44")
t("SL", "Eléctrico", "Baterías: bornes, sujeción, voltaje; alternador y arranque", "Inspección", "Todos", "Voltímetro", "C-57")
t("SL", "Eléctrico", "Paradas de emergencia (cabina y zona de despacho) conectadas y funcionando; cableado protegido; caja de fusibles", "Ensayo", "Todos", "—", "Dato flota", "9 de 33 fallas de HHWB-44 fueron eléctricas, incluidas las 2 paradas de emergencia desconectadas")
t("SL", "Eléctrico", "Luces, balizas, alarma de retroceso, bocina, limpiaparabrisas, tacógrafo", "Inspección", "Todos", "—", "C-60", "DS 298")
t("SL", "Estanque", "Estanque: fugas, abolladuras, corrosión, soldaduras, anclajes y cunas", "Inspección", AC, "—", "E-01", "DS 160 art. 177 d) y 203")
t("SL", "Válvulas", "Válvula de emergencia (de fondo) por compartimiento: cierre primario y remoto, fusible térmico", "Ensayo", AC, "—", "E-05", "DS 160 art. 186")
t("SL", "Válvulas", "Válvulas de presión/vacío, venteos y arrestallamas de venteo; válvulas de descarga, tapas y candados", "Inspección", AC, "—", "E-06 + E-07", "DS 160")
t("SL", "Estanque", "Escotillas: empaquetaduras, cierres, trabas; carga inferior API y sensor de sobrellenado", "Inspección", AC, "—", "E-08 + E-09", "DS 160")
t("SL", "Bomba", "Bomba de despacho: sello, fugas, ruido, acople, presión/caudal, alivio; limpiar strainer", "Inspección", AC, "—", "E-10")
t("SL", "Medición", "Medidor volumétrico: verificación con serafín y ajuste; precintos; eliminador de aire; registrador/ticket y totalizador", "Ensayo", AC, "Serafín trazable · OIML R 117 ±0,5 %", "E-12 + E-14", "Medidor y Liquid Control con lectura errónea en HHWB-44")
t("SL", "Filtración", "Filtro/separador de despacho: ΔP, drenaje de agua, sumidero", "Inspección", AC, "Manómetro diferencial", "E-15")
t("SL", "Mangueras", "Mangueras, pistola con cierre automático, acoples, swivels; engrase del carrete", "Inspección", AC, "Grasa NLGI 2", "E-17 + E-19 + E-20", "DS 160 art. 200")
t("SL", "Puesta a tierra", "Puesta a tierra: cable, pinza, carrete; medir continuidad camión–manguera–pinza", "Ensayo", AC, "Óhmetro (< 10 Ω)", "E-21", "DS 160 art. 190")
t("SL", "Seguridad", "Arrestallamas de escape, parachoques, señalización NU 1202, radio, corte general, kit de derrames, pasarela y barandas", "Inspección", AC, "—", "E-23 a E-29", "DS 160 / DS 298")
t("SL", "Cumplimiento", "Inspección mensual DS 298 con registro; documentación y certificados vigentes (hermeticidad, SEC, revisión técnica, calibración)", "Inspección", AC, "Control Documental de SICOM", "E-31 + E-32", "LCSX-78 opera con certificados vencidos")
t("SL", "Cierre", "Prueba de ruta y del sistema de despacho; horómetro de la próxima mantención en el sticker", "Ensayo", "Todos", "—", "SICOM FRK-PM-300")
# SM1
t("SM1", "Motor", "Filtros de combustible: primario/separador y secundario", "Reemplazo", "Todos", "Filtros genuinos Mack", "C-02")
t("SM1", "Motor", "Filtro de aire primario: reemplazo (antes si el indicador está en máximo)", "Reemplazo", "Todos", "Filtro genuino", "C-06")
t("SM1", "Motor", "Filtro de venteo del estanque de combustible del chasis", "Reemplazo", "Todos", "Filtro genuino", "C-08")
t("SM1", "Motor", "Embrague de ventilador, bomba de agua (orificio testigo)", "Inspección", "Todos", "—", "C-18")
t("SM1", "Postratamiento", "Escape, abrazaderas, sensores NOx/temperatura/ΔP; nivel y calidad de DEF", "Inspección", "Todos", "Refractómetro DEF 32,5 %", "C-26")
t("SM1", "Transmisión", "Enfriador de transmisión, líneas, conectores, selector, códigos TCM", "Inspección", "Todos", "Allison DOC / Mack PTT", "C-31")
t("SM1", "Tren motriz", "Cardanes: juego de crucetas, torque de pernos, soporte central", "Inspección", "Todos", "Torquímetro", "C-34")
t("SM1", "Tren motriz", "Bloqueo de diferencial / divisor de potencia: prueba funcional", "Ensayo", "Todos", "—", "C-37")
t("SM1", "Frenos", "Espesor de balatas, tambores, resortes, pasadores, cámaras", "Inspección", "Todos", "—", "C-43")
t("SM1", "Frenos", "Tiempo de recuperación del compresor (build-up)", "Ensayo", "Todos", "—", "C-47")
t("SM1", "Frenos", "Mangueras, cañerías y conexiones neumáticas", "Inspección", "Todos", "—", "C-48")
t("SM1", "Frenos", "ABS: códigos, sensores de rueda, anillos dentados, cableado", "Inspección", "Todos", "Herramienta de diagnóstico", "C-49", "Código ABS activo en HHWB-44")
t("SM1", "Neumáticos", "Rotación / evaluación de reemplazo", "Servicio", "Todos", "—", "C-51")
t("SM1", "Suspensión", "Torque de pernos U, bujes, amortiguadores, barras, soportes", "Inspección", "Todos", "Torquímetro", "C-55")
t("SM1", "Estructura", "Bastidor: fisuras, pernos sueltos, travesaños; soportes, cunas y pernos U del estanque", "Inspección", "Todos", "Torquímetro", "C-56 + E-33", "Zona crítica en aljibe")
t("SM1", "Eléctrico", "Conectores eléctricos: corrosión, seguros, grasa dieléctrica", "Inspección", "Todos", "Grasa dieléctrica", "C-59")
t("SM1", "Cabina", "Filtro de cabina, cinturones, espejos, parabrisas, asiento, extintor de cabina", "Inspección", "Todos", "Filtro de cabina", "C-62")
t("SM1", "Filtración", "Cambio de elementos del filtro de despacho", "Reemplazo", AC, "Elementos según fabricante", "E-16")
t("SM1", "Seguridad", "Extintores PQS (2 × 40 BC): revisión semestral, presión, sello, fecha", "Inspección", AC, "—", "E-22", "DS 160 art. 198")
t("SM1", "Seguridad", "Sistema de recuperación de vapores (si existe)", "Inspección", AC, "—", "E-30")
# SM2
t("SM2", "Tren motriz", "Cambio de aceite de diferenciales delantero + divisor y trasero", "Reemplazo", "Todos", "80W90 / GO-J Plus (18 L + 15 L)", "C-35", "Mack off-highway 1.200 h / 12 meses (hoy está en SM1: se ajusta)")
t("SM2", "Tren motriz", "Limpieza de respiraderos de diferenciales", "Servicio", "Todos", "—", "SICOM SM2")
t("SM2", "Motor", "Filtro de aire secundario (de seguridad)", "Reemplazo", "Todos", "Filtro genuino", "C-07")
t("SM2", "Motor", "Correas de ventilador y accesorios + tensor y poleas", "Reemplazo", "Todos", "Correas genuinas", "C-11", "Hoy en SM3: el servicio severo pide 12 meses")
t("SM2", "Motor", "Filtro de ventilación del cárter (CCV)", "Reemplazo", "Todos", "Filtro genuino", "C-12")
t("SM2", "Motor", "Filtro de refrigerante / acondicionador", "Reemplazo", "Todos", "Según refrigerante instalado", "C-14")
t("SM2", "Motor", "Prueba de estanqueidad del intercooler (CAC) y ductos", "Ensayo", "Todos", "Kit CAC", "C-17")
t("SM2", "Motor", "Turbocompresor: juego axial/radial, fugas, actuador VGT", "Inspección", "Todos", "—", "C-19")
t("SM2", "Motor", "Compresor de aire: aceite en líneas, culata, descarga", "Inspección", "Todos", "—", "C-20")
t("SM2", "Tren motriz", "Rodamientos de ruedas: juego, retenes, ajuste; cambio de aceite de cubos", "Inspección", "Todos", "—", "C-40")
t("SM2", "Tren motriz", "Alineación de los 3 ejes", "Ajuste", "Todos", "Equipo de alineación", "C-41")
t("SM2", "Frenos", "Secador de aire: cartucho", "Reemplazo", "Todos", "Cartucho Bendix/Mack", "C-44")
t("SM2", "Dirección", "Fluido y filtro de dirección hidráulica", "Reemplazo", "Todos", "Según manual Mack", "C-52")
t("SM2", "Eléctrico", "Prueba de carga de baterías y salida de alternador", "Ensayo", "Todos", "Probador de carga", "C-58")
t("SM2", "Estanque", "Interior de compartimentos: mamparos, corrosión, sedimentos, agua; limpieza", "Inspección", AC, "Procedimiento de espacio confinado", "E-04", "DS 160 art. 202 f)")
t("SM2", "Bomba", "Bomba de despacho: sello mecánico, rodamientos, empaquetaduras; verificar caudal", "Servicio", AC, "Kit de sello", "E-11")
t("SM2", "Medición", "Calibración certificada del sistema de medición y re-sellado", "Ensayo", AC, "Laboratorio trazable", "E-13", "Certificado anual")
t("SM2", "Mangueras", "Prueba de presión de mangueras de despacho", "Ensayo", AC, "1,5 × presión máxima", "E-18")
# SM3
t("SM3", "Motor", "Ajuste de válvulas y freno motor", "Ajuste", "Todos", "Manual MP8", "C-09 + SICOM SM3")
t("SM3", "Transmisión", "Filtros de transmisión (principal + lubricación) — Allison; caja mecánica/mDRIVE: aceite según placa", "Reemplazo", "Todos", "Allison TES 668/295 · confirmar tipo de caja", "C-29 + dato", "LCSX-78 marcó 'na' en aceite Allison: confirmar caja antes de comprar")
t("SM3", "Motor", "Limpieza del estanque de combustible del chasis", "Servicio", "Todos", "—", "SICOM SM3")
t("SM3", "Motor", "Cambio de refrigerante si es formulado (larga vida: SM4)", "Reemplazo", "Todos", "50/50 (57 L)", "SICOM SM3 + C-15", "Confirmar tipo de refrigerante")
# SM4
t("SM4", "Transmisión", "Cambio de fluido de transmisión", "Reemplazo", "Todos", "Allison TES 668/295 (~48 L) o según placa", "C-28")
t("SM4", "Motor", "Cambio de refrigerante larga vida", "Reemplazo", "Todos", "ELC", "C-15")
t("SM4", "Postratamiento", "DPF: limpieza; electrodo y tobera; inyector AHI; filtros y drenaje DEF", "Servicio", "Todos", "Genuinos", "C-22 a C-25", "Mack servicio pesado 4.500 h")
cnt = {}
for i, v in enumerate(T, 4):
    cnt[v[0]] = cnt.get(v[0], 0) + 1
    row(tk, i, ["%s-%02d" % (v[0], cnt[v[0]])] + list(v))
tk.freeze_panes = "A4"

# ---------------- Diaria Franke
dd = wb.create_sheet("Diaria Franke")
dd["A1"] = "REVISIÓN DIARIA · camión abastecedor Mack GU 813 (FRK-DIA-CP v2)"; dd["A1"].font = TT
dd["A2"] = "Antes del primer despacho del turno. Un NO OK en ítem crítico (★) deja el equipo fuera de servicio hasta corregirlo. Verde = se mantiene · Amarillo = nuevo."; dd["A2"].font = N
header(dd, 4, ["Bloque", "Ítem", "Crítico", "Estado", "Por qué"], [20, 70, 9, 10, 50])
D = [
    ("Lecturas", "Horómetro", "", "actual", ""), ("Lecturas", "Kilometraje", "", "actual", ""), ("Lecturas", "Numeral del metter", "", "actual", ""),
    ("Tablero", "Luces testigo y códigos de falla activos (motor, transmisión, ABS)", "★", "nuevo", "Códigos activos sin registrar en HHWB-42 y HHWB-44"),
    ("Tablero", "Temperatura de transmisión visible y en rango", "", "nuevo", "HHWB-42 sin temperatura de transmisión en tablero"),
    ("Motor y fluidos", "Nivel de aceite de motor", "", "actual", ""), ("Motor y fluidos", "Nivel de refrigerante", "", "actual", ""),
    ("Motor y fluidos", "Nivel de fluido de transmisión (indicador)", "", "nuevo", "Pauta 09-11, ítem 2"),
    ("Motor y fluidos", "Nivel de DEF", "", "nuevo", "Pauta 09-11, ítem 2"),
    ("Motor y fluidos", "Nivel de aceite hidráulico", "", "actual", ""),
    ("Motor y fluidos", "Nivel de dirección y líquido de frenos", "★", "actual", ""),
    ("Motor y fluidos", "Drenar separador de agua del combustible del motor", "", "nuevo", "Pauta 09-11, ítem 3"),
    ("Motor y fluidos", "Indicador de restricción del filtro de aire", "", "nuevo", "Polvo de faena"),
    ("Motor y fluidos", "Fugas bajo el equipo", "★", "actual", ""), ("Motor y fluidos", "Correas y mangueras", "", "actual", ""),
    ("Rodado y frenos", "Neumáticos: presión, cortes, tuercas (marcas) y piedras entre duales", "★", "actual", ""),
    ("Rodado y frenos", "Balatas de freno por visor", "★", "actual", ""),
    ("Rodado y frenos", "Purga de estanques de aire; presión de corte normal; sin alarma", "★", "actual", ""),
    ("Rodado y frenos", "Prueba de freno de servicio, estacionamiento y freno motor", "★", "nuevo", "Freno motor débil en HHWB-44"),
    ("Rodado y frenos", "Suspensión: paquetes de resortes y amortiguadores", "★", "actual", ""),
    ("Rodado y frenos", "Dirección: juego libre normal, sin ruidos ni dureza", "★", "nuevo", "Pauta 09-11, ítem 7"),
    ("Luces y señalización", "Luces altas, bajas, freno y viraje", "", "actual", ""),
    ("Luces y señalización", "Pértiga y su punto de conexión", "★", "actual", ""),
    ("Luces y señalización", "Baliza ámbar", "★", "actual", ""), ("Luces y señalización", "Focos de trocha", "", "actual", ""),
    ("Luces y señalización", "Alarma de retroceso, bocina, espejos, limpiaparabrisas", "", "nuevo", "DS 298"),
    ("Luces y señalización", "Tacógrafo operativo y radio con cobertura", "", "nuevo", "DS 298 art. 5 / DS 160 art. 197"),
    ("Sistema de despacho", "Manguera y pistola: sin cortes ni goteo; cierre automático; carrete retrae", "★", "actual", ""),
    ("Sistema de despacho", "Cuentalitros y ticket printer: marca e imprime", "★", "actual", ""),
    ("Sistema de despacho", "Seguros del metter", "★", "actual", ""),
    ("Sistema de despacho", "Seguros de escotilla y válvulas de fondo", "★", "actual", ""),
    ("Sistema de despacho", "Válvula de emergencia: accionamiento y cierre; mando remoto accesible", "★", "nuevo", "DS 160 art. 186"),
    ("Sistema de despacho", "Puesta a tierra: cable y pinza íntegros, carrete funciona", "★", "nuevo", "DS 160 art. 190"),
    ("Sistema de despacho", "Filtro de despacho: ΔP en rango, sumidero drenado", "", "nuevo", "Pauta 09-11, ítem 15"),
    ("Sistema de despacho", "Área de carga sin derrames", "★", "actual", ""),
    ("Emergencia", "Paradas de emergencia (cabina y despacho) operativas", "★", "nuevo", "Las 2 desconectadas en HHWB-44"),
    ("Emergencia", "Arrestallamas de escape instalado; escape sin fugas", "★", "nuevo", "DS 160 art. 197"),
    ("Emergencia", "Extintores: carga, sello y vigencia", "★", "actual", ""), ("Emergencia", "Cuñas y triángulos", "", "actual", ""),
    ("Emergencia", "Botiquín de cabina", "", "actual", ""), ("Emergencia", "Kit antiderrame / saco absorbente", "★", "actual", ""),
    ("Cierre", "Orden y aseo de cabina y equipo", "", "actual", ""),
    ("Cierre", "Documentación a bordo vigente (hermeticidad, SEC, revisión técnica, SOAP)", "★", "actual", "LCSX-78 con certificados vencidos"),
]
for i, v in enumerate(D, 5):
    row(dd, i, list(v), fill=(AMB if v[3] == "nuevo" else GRN))
n_new = sum(1 for x in D if x[3] == "nuevo")
dd.cell(len(D) + 6, 1, "Total: %d ítems (%d se mantienen, %d nuevos). Ningún ítem actual se elimina." % (len(D), len(D) - n_new, n_new)).font = B

# ---------------- Hallazgos urgentes
hz = wb.create_sheet("Hallazgos urgentes")
hz["A1"] = "HALLAZGOS QUE NO ESPERAN A LA PAUTA"; hz["A1"].font = TT
header(hz, 3, ["#", "Hallazgo", "Dato", "Acción sugerida"], [4, 40, 60, 60])
Hz = [
    ("LCSX-78 opera en Franke con certificados vencidos", "Hermeticidad vencida 01-04-2026; caudal/calibración y torque de ruedas 09-09-2026; sensor de sobrellenado, ECM y A/C 01-10-2026", "Regularizar de inmediato (riesgo legal DS 160 y con el mandante)"),
    ("HHWB-42 con la preventiva atrasada ~700 h", "Último preventivo registrado 24.717,6 h; hoy 25.695,9 h. Los planes de 300/600 h estaban apagados (desde MIG717 SICOM ya lo muestra vencido)", "Programar SL/SM1 ya"),
    ("SM3 hechos incompletos", "HHWB-44: sin refrigerante, transmisión, dirección, válvulas ni limpieza de estanque. Ningún cambio de aceite de transmisión registrado en Franke", "Completar en la próxima visita a Coquimbo"),
    ("Tipo de caja de LCSX-78 por confirmar", "Marcó 'na' en aceite Allison: el modelo 'GU 813 autom' podría no ser Allison", "Leer placa (y confirmar motor MP8, refrigerante y ejes) antes de comprar repuestos"),
    ("En Franke casi no se registran correctivos", "LCSX-78: 0 OT en 1.068 h (en Romeral: ~20 por 1.000 h). HHWB-42: 2.755 h sin OT", "Toda reparación en faena debe abrir OT (o nota del operador → NC)"),
    ("La revisión diaria no se usa", "FRK-DIA-CP: 1 ejecución en total (borrador, sin ítems)", "Exigirla en la entrega de turno; el supervisor la revisa"),
    ("No hay análisis de aceite", "Sin registros", "Contratar laboratorio y tomar muestra en cada SL"),
    ("Lecturas de horómetro inconsistentes", "HHWB-44: 25.815 / 25.934,6 / 25.899,9 en 6 días; LCSX-78: SM3 con 3 lecturas distintas", "Foto del tablero obligatoria al abrir/cerrar OT"),
]
for i, (h, d, a) in enumerate(Hz, 4):
    row(hz, i, [i - 3, h, d, a], fill=(RED if i <= 5 else None))
for s in wb.worksheets:
    s.sheet_view.showGridLines = False
wb.save(OUT)
print("ok", len(T), "tareas", len(D), "diaria", cnt)
