# Prueba punta a punta + Notificaciones de No Conformidades + Sugerencias

Guía para (A) configurar el correo, (B) probar el flujo completo de taller incluyendo
No Conformidades, y (C) verificar las mejoras nuevas (control de cambios, preventivas
multi-eje, campanita, ampolleta).

Migraciones involucradas: **MIG173** (control de cambios), **MIG174** (preventivas
multi-eje), **MIG175** (NC → campanita + correo + sugerencias), **MIG176** (cron del
digest, se aplica al final).

---

## A) Configurar el correo (Gmail gratis)

El correo se usa para: (1) avisar las No Conformidades, (2) recibir las sugerencias de
la ampolleta. El remitente es un Gmail tuyo (gratis).

1. **Crea o elige un Gmail** para enviar, ej. `taller.pillado@gmail.com`.
2. En esa cuenta: **Seguridad → Verificación en 2 pasos → actívala**.
3. **Seguridad → Contraseñas de aplicaciones → genera una** (16 caracteres). Cópiala.
   Esa es la `SMTP_PASS` (NO es la contraseña normal del correo).
4. En **Netlify → Site settings → Environment variables**, agrega:
   - `SMTP_USER` = el Gmail (ej. `taller.pillado@gmail.com`)
   - `SMTP_PASS` = la contraseña de aplicación de 16 caracteres
   - `MAIL_FROM` = `PILLADO ICEO <taller.pillado@gmail.com>` (opcional)
   - `NC_EMAIL_TO` = destinatarios de las NC, separados por coma
     (ej. `jefe.taller@empresa.cl, supervisor@empresa.cl, molivares.codoceo@gmail.com`)
   - `SUGERENCIAS_EMAIL_TO` = a dónde llegan las sugerencias (ej. tu correo)
   - `CRON_SECRET` = un texto aleatorio largo (inventa uno)
   - `SUPABASE_SERVICE_ROLE_KEY` = la *service role key* de Supabase
     (Supabase → Project settings → API → service_role). **Solo backend.**
5. Redespliega el sitio (Netlify lo hace solo al cambiar env, o "Trigger deploy").

### Activar el envío automático de NC (digest cada 2 h)
Una vez configuradas las variables:
1. Edita `database/production_run/176_cron_nc_digest.sql` y reemplaza `__CRON_SECRET__`
   por el MISMO valor que pusiste en `CRON_SECRET`.
2. Aplícalo: `node database/scripts/aplicar-migracion.mjs database/production_run/176_cron_nc_digest.sql`

> La **campanita in-app de NC funciona sin nada de esto** (es 100% base de datos).
> El correo es el canal adicional.

---

## B) Prueba punta a punta del taller (incluye No Conformidades)

Ruta principal: **Mantenimiento → Plan Semanal Taller** y **Mantenimiento → No Conformidades**.

1. **Recepción (gatillo de NC).**
   - En **Sugerencias de estado** marca un equipo como **"R" (Recepción)**.
   - En el **Plan Semanal Taller** aparece el bloque celeste *"Recepción por planificar"*.
     Arrástralo a un día → asigna grupo → se crea la OT de inspección + su checklist.
2. **Ejecutar el checklist y generar NC.**
   - Abre la inspección de recepción y marca ítems como **no_ok** (con foto).
   - Al cerrar la inspección, las NC se generan solas; o usa **"Generar del checklist"**.
   - También puedes **"Registrar NC ad-hoc"** (mejora continua).
   - **➜ Al crearse cada NC, suena la campanita** (badge del header) para
     admin/supervisor/planificador, y entra al digest de correo.
3. **Bandeja de NC** (`/dashboard/mantenimiento/no-conformidades`).
   - Por cada NC: **asignar recursos** (grupo + horas + materiales) y **Planificar**
     (crea la OT correctiva).
4. **Agendar el correctivo.**
   - En el Plan Semanal aparece el bloque naranjo *"Correctivos de recepción por agendar"*.
     Arrástralo a un día.
5. **Ejecución.**
   - Libera la OT a ejecución, el mecánico la ejecuta (vista `/m/taller`), checklist con
     fotos, pausa/fin → se generan NC de la jornada si hay no_ok.
6. **Ticket de bodega.**
   - Emite el ticket de materiales de las NC, el bodeguero lo escanea y rebaja stock FIFO.

---

## C) Verificar las mejoras nuevas

### 1. Control de cambios del plan (MIG173)
- En el **Plan Semanal Taller**, **confirma** el plan (botón Confirmar).
- Arrastra una OT a otro día → ahora **pide un motivo** (porque el plan está confirmado).
  En borrador, mueve directo sin pedir nada.
- Abre el detalle de una jornada (lápiz) → cambia el responsable/mecánicos: si el plan
  está confirmado, **exige motivo**. Abajo verás **"Control de cambios"** con la línea de
  tiempo (quién, cuándo, de qué a qué, y el motivo).

### 2. Preventivas que se vienen, multi-eje (MIG174)
- En **Plan Semanal Taller** (panel "Preventivas sugeridas") y en
  **Mantenimiento → Planificación**: ahora aparecen las preventivas por **fecha, km y
  horas** (antes solo por fecha). Cada una muestra el **eje crítico** (📅/🛣/⏱) y el detalle
  ("Vencida por 800 km", "Faltan 12 h", etc.).
- Las que tengan **⚠** significan que la *última lectura de km/horas del plan está
  desfasada* — conviene corregir esa lectura para que el vencimiento sea exacto.

### 3. Campanita de notificaciones (MIG175)
- Crea/lleguen NC → el **icono de campana** del header muestra el contador y, al hacer
  clic, **despliega** la lista; al tocar una, te lleva a la bandeja y la marca leída.

### 4. Ampolleta de sugerencias (P5)
- En cualquier pantalla del dashboard, abajo a la derecha hay una **💡**.
- Escribe una mejora → se **guarda** (tabla `sugerencias`) y, si el correo está
  configurado, te **llega un email con el texto ya formateado como prompt** para pegármelo
  aquí y que yo lo implemente.

---

## Notas
- Si el correo aún no está configurado, la campanita y la ampolleta **igual funcionan**
  (la sugerencia queda guardada en BD; el envío se omite).
- Destinatarios in-app de NC: roles `administrador`, `supervisor`, `planificador`.
