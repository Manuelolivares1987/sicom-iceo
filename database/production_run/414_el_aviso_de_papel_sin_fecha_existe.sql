-- ============================================================================
-- MIG414 · El aviso «papel sin fecha» tiene que existir para poder emitirse
-- ----------------------------------------------------------------------------
-- El escalamiento de MIG412/413 reventó al primer intento:
--
--     new row for relation "alertas" violates check constraint "chk_alertas_tipo"
--
-- La tabla `alertas` tiene una lista blanca de tipos y `doc_sin_fecha` no está
-- en ella. El estado es nuevo —lo creó MIG407 esta misma tarde— y la lista se
-- quedó atrás.
--
-- Es un buen constraint: impide que aparezcan tipos inventados que después
-- ninguna pantalla sabe mostrar. Sólo hay que declararle el tipo nuevo, igual
-- que se le declaró la traducción en `lib/alertas-labels.ts`.
-- ============================================================================

BEGIN;

ALTER TABLE public.alertas DROP CONSTRAINT IF EXISTS chk_alertas_tipo;
ALTER TABLE public.alertas ADD CONSTRAINT chk_alertas_tipo CHECK (
  (tipo)::text = ANY (ARRAY[
    'vencimiento','stock_minimo','ot_vencida','incumplimiento','bloqueante',
    'antiguedad_vehiculo','semep_vencido','fatiga_conductor','rt_por_vencer',
    'hermeticidad_vencida','sec_no_vigente','sensor_fuga','accidente_no_reportado',
    'jornada_excedida','pts_faltante','disponibilidad_vencida','gps_sin_senal',
    'no_conformidad','recurso_solicitado','recurso_por_comprar','recurso_recibido',
    'vale_emitido','doc_por_vencer','doc_vencido','doc_vencidos_equipo',
    -- [MIG414] Hay papel cargado, su tipo caduca y nadie anotó hasta cuándo.
    'doc_sin_fecha'
  ]::text[]));

COMMIT;
