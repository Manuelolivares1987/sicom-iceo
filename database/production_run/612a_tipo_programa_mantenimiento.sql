-- 612a — tipo de documento «Programa de mantenimiento» (ESMAX lo exige por camión).
-- Va solo: un valor nuevo de enum no se puede usar en la misma transacción.
ALTER TYPE tipo_certificacion_enum ADD VALUE IF NOT EXISTS 'programa_mantenimiento';
