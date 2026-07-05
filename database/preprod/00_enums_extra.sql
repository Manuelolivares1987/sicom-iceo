SET client_min_messages = warning;
DO $$ BEGIN CREATE TYPE criticidad_enum AS ENUM ('critica','alta','media','baja'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE tipo_activo_enum AS ENUM ('punto_fijo','punto_movil','surtidor','dispensador','estanque','bomba','manguera','camion_cisterna','lubrimovil','equipo_bombeo','herramienta_critica','pistola_captura','camioneta','camion','equipo_menor'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE tipo_equipamiento_enum AS ENUM ('aljibe_agua','aljibe_combustible','pluma_grua','ampliroll','grua_horquilla','camioneta','tracto','generico'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
