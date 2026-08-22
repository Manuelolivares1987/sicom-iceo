-- ============================================================================
-- MIG311 · El historial 2026 de los dos aljibes de Romeral, completo
-- ----------------------------------------------------------------------------
-- FUENTE
--   Informes técnicos de mantenimiento elaborados por el Área de Mantenimiento
--   (OS generadas por Ricardo Burgos A.):
--     · INF-MTTO-DJKL18-2026, emitido 05-08-2026 — 12 OS, ene a jul 2026
--     · INF-MTTO-FSLZ67-2026, emitido 12-08-2026 — 5 OS + recepción, ene a ago
--
-- QUÉ ENCONTRÉ AL CRUZARLO CON LA BASE
--   DJKL-18: el sistema tenía 6 de las 12 OS. Faltaban las cinco de abril a
--            julio (3353, 3369, 3378, 3386, 3397) — o sea, todo el trabajo de
--            embrague/PTO y la revisión técnica. Además la OS 3319 estaba
--            cargada como "CQBO-319", un dígito menos.
--   FSLZ-67: estaban las 5 OS pero faltaba la recepción del 07-08-2026, que es
--            justamente la última intervención del equipo.
--   Ninguna de las dos tenía el detalle de lo ejecutado: la tabla sólo guardaba
--   banderas y un contador de trabajos. "16 trabajos" no le sirve a nadie.
--
-- QUÉ NO SE CARGA (a propósito)
--   · OS 3325 y OS 3330 son intervenciones sobre DCHD-83 y LCSX-78. Aparecen
--     en los informes por intercambio/préstamo de componentes, pero el trabajo
--     se hizo sobre OTROS equipos: cargarlas aquí falsearía el historial de
--     ambos lados. Quedan mencionadas en el detalle de la OS que las involucra.
--   · Las HH por OS de las cinco intervenciones nuevas: el informe da el total
--     del período (164,5 HH) pero no el desglose. Se deja en NULL en vez de
--     repartirlo a ojo — un número inventado es peor que un vacío.
-- ============================================================================

BEGIN;

-- ── 1. Dónde vive el detalle de lo que se hizo ─────────────────────────────
ALTER TABLE public.historial_os_legacy
    ADD COLUMN IF NOT EXISTS detalle_trabajos TEXT,
    ADD COLUMN IF NOT EXISTS observacion      TEXT,
    ADD COLUMN IF NOT EXISTS fuente           TEXT;

COMMENT ON COLUMN public.historial_os_legacy.detalle_trabajos IS
  'Lo que efectivamente se ejecutó, en palabras. Las banderas dicen de que tipo fue; esto dice que se hizo. MIG311.';
COMMENT ON COLUMN public.historial_os_legacy.fuente IS
  'De donde salio el registro (informe tecnico, carga Excel original). Para saber a quien reclamarle si algo no cuadra. MIG311.';

-- ── 2. Corregir el folio mal cargado ───────────────────────────────────────
UPDATE public.historial_os_legacy
   SET os_cqbo = 'CQBO-3319', os_numero = '3319'
 WHERE os_cqbo = 'CQBO-319'
   AND activo_id = (SELECT id FROM activos WHERE patente = 'DJKL-18');

-- ── 3. Las cinco OS que faltaban del DJKL-18 ───────────────────────────────
INSERT INTO public.historial_os_legacy
    (anio, os_numero, os_cqbo, patente_raw, activo_id, tipo_equipo, marca_modelo,
     faena, cliente, ubicacion, fecha_recepcion, fecha_entrega,
     horometro, kilometraje, cumplimiento_pct, responsable, num_trabajos, horas_mo,
     flag_mant_prev, flag_correctivo, flag_neumaticos, flag_rev_tec,
     flag_hab_estado, flag_serv_externo, detalle_trabajos, observacion, fuente)
SELECT v.*
FROM (
    VALUES
    (2026, '3353', 'CQBO-3353', 'DJKL-18',
     (SELECT id FROM activos WHERE patente='DJKL-18'),
     'Camión aljibe de combustible', 'Mercedes-Benz Actros 3341',
     'Romeral', 'Compañía Minera del Pacífico (CMP)', 'Taller',
     DATE '2026-04-21', DATE '2026-04-21',
     NULL::numeric, NULL::numeric, 100::numeric, NULL::text, NULL::integer, NULL::numeric,
     false, true, false, false, false, false,
     'Eliminación de fugas de combustible por bomba y por niples del interior del cajón. '
     || 'Reparación con soldadura: parachoques trasero / pisadera de plataforma y abrazadera en "U" '
     || 'del estanque delantera derecha. Fabricación de gancho para pistola 7H; mejora del contador '
     || 'de pistola 7H del sistema Orpak; prueba de funcionamiento de recirculación.',
     NULL::text,
     'Informe técnico INF-MTTO-DJKL18-2026'),

    (2026, '3369', 'CQBO-3369', 'DJKL-18',
     (SELECT id FROM activos WHERE patente='DJKL-18'),
     'Camión aljibe de combustible', 'Mercedes-Benz Actros 3341',
     'Romeral', 'Compañía Minera del Pacífico (CMP)', 'Taller',
     DATE '2026-05-27', DATE '2026-06-01',
     21686::numeric, 216613::numeric, 100::numeric, 'Felipe López', 19, NULL::numeric,
     false, true, false, false, false, false,
     'Tren motriz: corrección del funcionamiento de la toma de fuerza (PTO); revisión de embrague; '
     || 'normalización de la bomba de combustible; cambio de empaquetaduras del múltiple de escape. '
     || 'Suspensión y frenos: cambio de biela de barra estabilizadora posterior; cambio de buje de '
     || 'soporte posterior del paquete de resortes izquierdo; regulación de frenos; reposición de cuñas. '
     || 'Sistema de despacho: normalización de cadena del carrete de alto flujo; cambio de manguera de '
     || 'pistola 7H; reposición de carrete antiestático; cambio de telecomando; eliminación de '
     || 'filtraciones en cajón surtidor y limpieza. Eléctrico: normalización de todas las luces, focos '
     || 'faeneros y corta corriente; mantención de baterías y cubículos. Reapriete de pernos de anclaje '
     || 'del neumático de repuesto derecho.',
     'Se gestionó la adquisición de repuestos (bomba de embrague, empaquetaduras de escape, '
     || 'telecomando y buje de paquete de resortes), instalados en las OS siguientes.',
     'Informe técnico INF-MTTO-DJKL18-2026'),

    (2026, '3378', 'CQBO-3378', 'DJKL-18',
     (SELECT id FROM activos WHERE patente='DJKL-18'),
     'Camión aljibe de combustible', 'Mercedes-Benz Actros 3341',
     'Romeral', 'Compañía Minera del Pacífico (CMP)', 'Taller',
     DATE '2026-06-17', DATE '2026-06-18',
     21830::numeric, 217384::numeric, 100::numeric, 'Yusdel Sarduy - Joel Coo', NULL::integer, NULL::numeric,
     true, true, false, false, false, false,
     'Mantención preventiva (frecuencia 300 h). Cierre de trabajos de la OS 3369 con repuestos '
     || 'recibidos: cambio de telecomando, empaquetaduras del múltiple de escape y buje del paquete de '
     || 'resortes. Revisión de embrague y de la PTO; eliminación de fugas de aire. Cambio de piola de '
     || 'válvula de fondo, ejecutado en terreno (05-06-26).',
     NULL::text,
     'Informe técnico INF-MTTO-DJKL18-2026'),

    (2026, '3386', 'CQBO-3386', 'DJKL-18',
     (SELECT id FROM activos WHERE patente='DJKL-18'),
     'Camión aljibe de combustible', 'Mercedes-Benz Actros 3341',
     'Romeral', 'Compañía Minera del Pacífico (CMP)', 'Taller',
     DATE '2026-06-30', DATE '2026-06-30',
     NULL::numeric, NULL::numeric, 100::numeric, 'Joel Coo', 1, NULL::numeric,
     false, false, false, true, false, false,
     'Obtención de revisión técnica del equipo — realizado.',
     NULL::text,
     'Informe técnico INF-MTTO-DJKL18-2026'),

    (2026, '3397', 'CQBO-3397', 'DJKL-18',
     (SELECT id FROM activos WHERE patente='DJKL-18'),
     'Camión aljibe de combustible', 'Mercedes-Benz Actros 3341',
     'Romeral', 'Compañía Minera del Pacífico (CMP)', 'Romeral',
     DATE '2026-07-17', DATE '2026-07-17',
     NULL::numeric, NULL::numeric, 100::numeric, 'Joel Coo - Felipe López', NULL::integer, NULL::numeric,
     false, true, false, false, false, false,
     'Falla de embrague: cambio de bomba de embrague (componente nuevo), sangrado/cebado del sistema '
     || 'y prueba de funcionamiento.',
     'Previamente se había cambiado el servo embrague (componente retirado del equipo 31).',
     'Informe técnico INF-MTTO-DJKL18-2026')
) AS v(anio, os_numero, os_cqbo, patente_raw, activo_id, tipo_equipo, marca_modelo,
       faena, cliente, ubicacion, fecha_recepcion, fecha_entrega,
       horometro, kilometraje, cumplimiento_pct, responsable, num_trabajos, horas_mo,
       flag_mant_prev, flag_correctivo, flag_neumaticos, flag_rev_tec,
       flag_hab_estado, flag_serv_externo, detalle_trabajos, observacion, fuente)
WHERE NOT EXISTS (
    SELECT 1 FROM public.historial_os_legacy h
     WHERE h.os_cqbo = v.os_cqbo AND h.activo_id = v.activo_id
);

-- ── 4. La recepción del FSLZ-67 que cerraba el período ─────────────────────
-- No tiene OS en carpeta: se documentó con informe de recepción firmado por el
-- Jefe de Mantenimiento. Se carga como intervención igual, porque el equipo
-- estuvo en taller y se le cambiaron mangueras: eso es historial.
INSERT INTO public.historial_os_legacy
    (anio, os_numero, os_cqbo, patente_raw, activo_id, tipo_equipo, marca_modelo,
     faena, cliente, ubicacion, fecha_recepcion, fecha_entrega,
     horometro, kilometraje, cumplimiento_pct, responsable, num_trabajos, horas_mo,
     flag_mant_prev, flag_correctivo, flag_neumaticos, flag_rev_tec,
     flag_hab_estado, flag_serv_externo, detalle_trabajos, observacion, fuente)
SELECT
    2026, 'REC-20260807', 'RECEPCIÓN 07-08-26', 'FSLZ-67',
    (SELECT id FROM activos WHERE patente='FSLZ-67'),
    'Camión aljibe de combustible 15.000 L (6x4)', 'Mercedes-Benz Actros 3341',
    'Romeral', 'Compañía Minera del Pacífico (CMP)', 'Taller Pillado, Coquimbo',
    DATE '2026-08-07', DATE '2026-08-07',
    15897::numeric, 129716::numeric, NULL::numeric, 'Ricardo Burgos', 2, NULL::numeric,
    false, true, false, false, false, false,
    'Inspección de recepción por personal mecánico: mangueras de los surtidores 7H y Wiggins con '
    || 'daños. Cambio de las mangueras surtidoras de la pistola Wiggins y de la pistola 7H, '
    || 'incluida la pistola.',
    'Atención documentada mediante informe de recepción firmado por el Jefe de Mantenimiento '
    || '(sin OS en carpeta a la fecha de emisión del informe técnico).',
    'Informe técnico INF-MTTO-FSLZ67-2026'
WHERE NOT EXISTS (
    SELECT 1 FROM public.historial_os_legacy h
     WHERE h.os_numero = 'REC-20260807'
       AND h.activo_id = (SELECT id FROM activos WHERE patente='FSLZ-67')
);

-- ── 5. El detalle de las OS que ya estaban cargadas ────────────────────────
-- Estaban con banderas y contador, sin decir qué se hizo. Se completa desde
-- los mismos informes técnicos.
UPDATE public.historial_os_legacy h
   SET detalle_trabajos = v.detalle,
       observacion      = COALESCE(v.obs, h.observacion),
       flag_mant_prev   = COALESCE(v.pm, h.flag_mant_prev),
       fuente           = COALESCE(h.fuente, v.fuente)
  FROM (VALUES
    ('DJKL-18', 'CQBO-3293',
     'Mantención preventiva (frecuencia 300 h; próxima a 21.281 hrs) y revisión/relleno de niveles. '
     || 'Cambio de: pértiga, empaquetaduras de válvulas de venteo, correa de accesorios (ejec. 27-01), '
     || 'retén de salida del eje de la PTO, cuñas dañadas y plásticos de moldura de retrovisor derecho. '
     || 'Cambio de 6 neumáticos pos. 1-2-7-8-9-10 (servicio externo) y verificación de torque de tuercas '
     || 'con check point. Ajuste de llave de emergencia; enderezado de parachoques trasero; limpieza de '
     || 'cajón surtidor, cabina, cajón de baterías y descontaminación del ducto de venteo.',
     'La bajada del equipo se produjo por un derrame por sobrellenado, quedando combustible en el tubo '
     || 'de venteo, el cual fue limpiado y descontaminado. El equipo se entregó a Romeral el 23-01-26.',
     true, 'Informe técnico INF-MTTO-DJKL18-2026'),

    ('DJKL-18', 'CQBO-3303',
     'Prueba de funcionamiento del aire acondicionado (servicio externo) y prueba de surtidores.',
     'Segunda revisión por reporte de falla de A/C; no se encuentran anomalías. Se revisan presiones, '
     || 'varillaje de calefacción y temperatura: alcanza 6 °C incluso con puertas abiertas.',
     false, 'Informe técnico INF-MTTO-DJKL18-2026'),

    ('DJKL-18', 'CQBO-3304',
     'Prueba de recirculación y caudal controlada por empresa externa (FESJET/JESTEC). Cambio de 6 '
     || 'neumáticos pos. 1-2-7-8-9-10 (externo) y traslado del equipo a Romeral.',
     NULL, false, 'Informe técnico INF-MTTO-DJKL18-2026'),

    ('DJKL-18', 'CQBO-3315',
     'Revisión del equipo por alerta de humo cerca de la PTO.',
     'Se evalúa el equipo en faena y no se detecta falla; pruebas de funcionamiento conformes. '
     || 'Equipo queda operativo.',
     false, 'Informe técnico INF-MTTO-DJKL18-2026'),

    ('DJKL-18', 'CQBO-3319',
     'Cambio de Liquid Control y Meter; prueba de matraz y prueba de sensor de llenado óptico. '
     || 'Eliminación de fuga de combustible por base de entrada a la bomba; fabricación de hilo en hoyos '
     || 'de base. Revisión del acople de la PTO, engrase y limpieza de cajón surtidor.',
     'El Liquid Control y Meter instalados provienen del equipo DCHD-83; los retirados se instalarán en '
     || 'dicho equipo previa mantención (OS 3325, ejecutada sobre DCHD-83).',
     false, 'Informe técnico INF-MTTO-DJKL18-2026'),

    ('DJKL-18', 'CQBO-3345',
     'Mantención preventiva (próxima a 21.513 hrs) y limpieza de zona de bomba (queda en observación). '
     || 'Eliminación de fugas de combustible por sistema Orpak; normalización de fijación de baliza Orpak '
     || 'y tapa de sistema eléctrico. Cambio de manguera Wiggins; reparación de neumático pos. 4 '
     || '(pinchado); reparación de soporte de abrazadera "U" entre estanque y chasis delantero derecho.',
     'Bajada de Romeral. Ejecutada entre el 06 y el 07-04-2026.',
     true, 'Informe técnico INF-MTTO-DJKL18-2026'),

    ('FSLZ-67', 'CQBO-3297',
     'Cambio de hoja madre del paquete de resortes delantero, quebrada (servicio externo). Cambio de '
     || 'bujes del paquete de resortes delantero (servicio externo). Desmontaje y montaje del estanque de '
     || 'AdBlue para acceder a uno de los bujes a cambiar. Traslado del equipo Romeral → Resortes Estadio '
     || 'y viceversa.',
     'Bajada de urgencia por quebradura de la hoja madre. Llegó a taller externo la tarde del 20-01-26, '
     || 'los trabajos se ejecutaron entre el 21 y el 26-01-26 y el equipo fue trasladado y entregado en '
     || 'faena Romeral.',
     false, 'Informe técnico INF-MTTO-FSLZ67-2026'),

    ('FSLZ-67', 'CQBO-3312',
     'Cambio de manguera de pistola 7H (ejecutado el 02-02-26). Cambio de correa de accesorios '
     || '(ejecutado el 03-02-26).',
     'Ambos trabajos fueron realizados en faena, sin bajada del equipo.',
     false, 'Informe técnico INF-MTTO-FSLZ67-2026'),

    ('FSLZ-67', 'CQBO-3314',
     'Cambio de apoyabrazos de la palanca de cambios.',
     'Intervención ejecutada y entregada el mismo día (09:00 a 13:00 hrs).',
     false, 'Informe técnico INF-MTTO-FSLZ67-2026'),

    ('FSLZ-67', 'CQBO-3335',
     'Reemplazo de manguera y pistola del surtidor Wiggins. Reemplazo de pistola del surtidor 7H.',
     'Componentes reemplazados en faena. La manguera del carrete Wiggins fue facilitada desde el equipo '
     || 'LCSX-78 (OS 3330, ejecutada sobre ese equipo).',
     false, 'Informe técnico INF-MTTO-FSLZ67-2026'),

    ('FSLZ-67', 'CQBO-3338',
     'Mantención preventiva según pauta (frecuencia 300 h; próxima a 15.803 hrs), con revisión general. '
     || 'Frenos y suspensión: cambio de tambores de freno de los puentes traseros; embalatado de los '
     || 'patines; verificación del ajuste de frenos de servicio; eliminación de fuga de aire por servo de '
     || 'freno. Tren motriz: eliminación de fuga de aceite por tapón del cárter de la transmisión; cambio '
     || 'de tensor de la correa de accesorios. Eléctrico: normalización del cableado de la baliza delantera '
     || 'y del sistema del estanque de AdBlue; reposición de luz intermitente delantera izquierda. Otros: '
     || 'reposición de cuñas y conos reflectantes; cambio de banderín de pértiga; alineado del parachoques '
     || 'trasero; mantención de baterías y cajón; limpieza del cajón surtidor.',
     'El equipo se recibió el lunes 09-03 a las 17:45 hrs y se envió a lavado el 10-03; la mantención '
     || 'comenzó el 11-03-26. El informe de recepción registró 15 desviaciones detectadas, todas '
     || 'intervenidas en esta OS.',
     true, 'Informe técnico INF-MTTO-FSLZ67-2026')
  ) AS v(patente, os, detalle, obs, pm, fuente)
 WHERE h.os_cqbo = v.os
   AND h.activo_id = (SELECT id FROM activos a WHERE a.patente = v.patente);

-- ── 6. Que el historial muestre el detalle de las OS antiguas ──────────────
-- Antes la vista armaba una frase con las banderas ("2 trabajo(s) registrados,
-- Neumáticos"). Cuando hay detalle real, manda el detalle.
CREATE OR REPLACE VIEW public.v_historial_mantenimiento_equipo AS
SELECT
    o.activo_id,
    'ot'::text                                     AS origen,
    o.id                                           AS ref_id,
    o.folio::text                                  AS folio,
    o.tipo::text                                   AS tipo,
    o.estado::text                                 AS estado,
    COALESCE(o.fecha_termino, o.fecha_cierre_supervisor,
             o.fecha_inicio, o.fecha_programada::timestamptz, o.created_at) AS fecha,
    o.fecha_inicio,
    o.fecha_termino,
    o.trabajo_realizado,
    NULLIF(o.observaciones, '')                    AS motivo,
    o.km_al_cierre,
    o.horas_al_cierre,
    o.horas_hombre,
    COALESCE(o.costo_mano_obra, 0) + COALESCE(o.costo_materiales, 0) AS costo,
    COALESCE(resp.nombre_completo, tec.nombre_completo) AS responsable,
    sup.nombre_completo                            AS supervisor,
    (SELECT count(*)::int FROM checklist_ot c WHERE c.ot_id = o.id)                         AS tareas_total,
    (SELECT count(*)::int FROM checklist_ot c WHERE c.ot_id = o.id AND c.resultado = 'ok')  AS tareas_ok,
    (SELECT count(*)::int FROM checklist_ot c WHERE c.ot_id = o.id AND c.resultado = 'no_ok') AS tareas_no_ok,
    (SELECT count(*)::int FROM movimientos_inventario m
      WHERE m.ot_id = o.id AND m.tipo IN ('salida','merma'))                                AS repuestos_total,
    (SELECT count(*)::int FROM evidencias_ot e WHERE e.ot_id = o.id)                        AS evidencias_total,
    (SELECT count(*)::int FROM no_conformidades nc WHERE nc.ot_id = o.id)                   AS hallazgos_total,
    NULL::text                                     AS fuente
FROM ordenes_trabajo o
LEFT JOIN usuarios_perfil resp ON resp.id = o.responsable_id
LEFT JOIN usuarios_perfil tec  ON tec.id  = o.tecnico_id
LEFT JOIN usuarios_perfil sup  ON sup.id  = o.supervisor_cierre_id
WHERE o.activo_id IS NOT NULL

UNION ALL

SELECT
    h.activo_id,
    'os_legacy'::text,
    h.id,
    ('OS ' || COALESCE(h.os_cqbo, h.os_numero, left(h.id::text, 8)))::text,
    CASE WHEN h.flag_mant_prev THEN 'preventivo'
         WHEN h.flag_correctivo THEN 'correctivo'
         ELSE 'servicio' END,
    'cerrada'::text,
    h.fecha_recepcion::timestamptz,
    h.fecha_recepcion::timestamptz,
    h.fecha_entrega::timestamptz,
    -- El detalle real manda; si no lo hay, se arma lo que se pueda con las
    -- banderas, que es lo único que trajo la carga original.
    COALESCE(h.detalle_trabajos, NULLIF(concat_ws('. ',
        NULLIF(h.num_trabajos::text, '') || ' trabajo(s) registrados',
        CASE WHEN h.flag_neumaticos    THEN 'Neumáticos' END,
        CASE WHEN h.flag_rev_tec       THEN 'Revisión técnica' END,
        CASE WHEN h.flag_hab_estado    THEN 'Habilitación' END,
        CASE WHEN h.flag_serv_externo  THEN 'Servicio externo' END,
        NULLIF('Cumplimiento ' || h.cumplimiento_pct::text || '%', 'Cumplimiento %')
    ), '')),
    COALESCE(NULLIF(h.observacion, ''), NULLIF(h.ubicacion::text, ''), NULLIF(h.faena::text, '')),
    h.kilometraje::numeric,
    h.horometro::numeric,
    h.horas_mo::numeric,
    NULL::numeric,
    h.responsable,
    NULL::text,
    COALESCE(h.num_trabajos, 0)::int,
    COALESCE(h.num_trabajos, 0)::int,
    0, 0, 0, 0,
    h.fuente
FROM historial_os_legacy h
WHERE h.activo_id IS NOT NULL;

GRANT SELECT ON public.v_historial_mantenimiento_equipo TO authenticated;

COMMIT;
