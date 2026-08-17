# Activar el correo de alerta de exámenes

**Estado:** el sistema ya calcula qué avisar y cuándo. Falta conectar la cuenta
de correo y encender el cron. Son 3 pasos, ~15 minutos.

---

## 1. Crear la cuenta de correo de SICOM

Una cuenta Gmail propia del sistema, no la personal de nadie (si la persona se
va o cambia su clave, se cae el aviso).

1. Crear la cuenta, por ejemplo `sicom.pillado@gmail.com`
2. Activar **verificación en 2 pasos** (obligatorio para el paso siguiente)
3. Google → Seguridad → **Contraseñas de aplicaciones** → generar una
4. Guardar los 16 caracteres que entrega. **Esa es la clave que usa el sistema,
   no la contraseña normal de la cuenta.**

> El sistema ya tiene un correo configurado para No Conformidades. Si prefieres
> usar el mismo, salta al paso 2 y reutiliza sus credenciales.

---

## 2. Configurar las variables en Netlify

Netlify → el sitio `pilladoiceo` → **Site settings → Environment variables**:

| Variable | Valor | Nota |
|---|---|---|
| `SMTP_USER` | `sicom.pillado@gmail.com` | la cuenta que envía |
| `SMTP_PASS` | los 16 caracteres del paso 1 | **no** la contraseña normal |
| `MAIL_FROM` | `SICOM PILLADO <sicom.pillado@gmail.com>` | opcional; es lo que ve quien recibe |
| `PREVENCION_EMAIL_TO` | correos separados por coma | quién recibe la alerta |
| `CRON_SECRET` | un texto largo y aleatorio | **si ya existe, usar el mismo** |

`PREVENCION_EMAIL_TO` sugerido: prevención, jefe de operaciones y gerencia.
Ejemplo: `anyulin@pillado.cl, jefe.operaciones@pillado.cl, molivares.codoceo@gmail.com`

Después de guardar, Netlify pide **redeploy** para que las variables tomen
efecto. Basta con "Trigger deploy → Deploy site".

---

## 3. Encender el cron

Editar `database/production_run/300_cron_alerta_examenes.sql`, reemplazar
`<CRON_SECRET>` por el valor real del paso 2, y aplicar:

```bash
node database/scripts/aplicar-migracion.mjs database/production_run/300_cron_alerta_examenes.sql
```

Queda corriendo todos los días a las **08:00 de Chile**.

---

## Probar antes de esperar al día siguiente

```bash
curl -X POST https://pilladoiceo.netlify.app/api/notificaciones/examenes-vencimiento/ \
  -H "x-cron-secret: EL_VALOR_REAL"
```

Respuestas posibles:

| Respuesta | Significa |
|---|---|
| `{"ok":true,"enviadas":22,...}` | correo enviado |
| `{"ok":true,"enviadas":0}` | no había nada que avisar hoy (correcto, no es error) |
| `{"error":"SMTP o PREVENCION_EMAIL_TO no configurados."}` | falta el paso 2 o el redeploy |
| `{"error":"No autorizado."}` | el `CRON_SECRET` no coincide |

> **La barra final de la URL es obligatoria.** Sin ella el sitio responde 308
> (redirect) y el cron no lo sigue: correría todos los días sin enviar nada y
> sin dar error visible.

---

## Cómo se comporta la alerta

El cron corre **todos los días**, pero el correo **no sale todos los días**: la
frecuencia sube a medida que se acerca el vencimiento.

| Faltan | Avisa |
|---|---|
| 60 a 31 días | 1 vez por semana |
| 30 a 15 días | cada 3 días |
| 14 a 8 días | día por medio |
| 7 a 1 días | todos los días |
| **vencido** | todos los días, hasta que se renueve |

La razón: avisar a diario desde 60 días entrena a la gente a ignorar el correo,
y avisar una sola vez hace que se pase por alto.

**Renovar un examen apaga su alerta automáticamente.** No hay que acordarse de
nada: al subir el nuevo examen, el ciclo se reinicia.

Si el envío falla, los avisos **no** se marcan como enviados y se reintentan al
día siguiente. Es preferible un aviso repetido a uno perdido cuando lo que está
en juego es acreditar gente en faena.

---

## Estado al momento de escribir esto (17-ago-2026)

Con la planilla de Romeral cargada, el primer correo llevará:

- **12 exámenes vencidos** (4 personas) — aviso diario
- **4 exámenes críticos** que vencen en 5 y 6 días — aviso diario
- **6 exámenes** entre 40 y 45 días — aviso semanal
