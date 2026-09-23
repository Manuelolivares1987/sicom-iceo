import nodemailer from 'nodemailer'

// Envío de correo del sistema. Dos caminos, en este orden:
//
// 1) MICROSOFT 365 (Graph API) — el correcto para Pillado.
//    El dominio pilladoempresas.cl vive en Microsoft 365 (MX a
//    mail.protection.outlook.com, SPF solo de Outlook). Un correo que sale de
//    un Gmail personal con el nombre «PILLADO ICEO» es, para el filtro de
//    Outlook, masivo + cuenta gratuita + suplantación de la empresa: va a
//    correo no deseado. Enviado desde un buzón propio del tenant llega como
//    correo interno, a la bandeja de entrada.
//    Graph con una app registrada (client credentials), no SMTP con usuario y
//    contraseña: Microsoft lo deja desactivado por defecto desde el 31-12-2026
//    y anunciará su retiro final en 2027 (se reactiva a mano, pero es prestado).
//      MS_TENANT_ID      → Id. de directorio (inquilino) de Entra ID
//      MS_CLIENT_ID      → Id. de aplicación (cliente) de la app «SICOM Correo»
//      MS_CLIENT_SECRET  → secreto de cliente de esa app
//      MS_SENDER         → buzón que envía, ej. sicom@pilladoempresas.cl
//    El permiso se da en EXCHANGE, no en Entra ID: RBAC for Applications, rol
//    «Application Mail.Send» con alcance solo a MS_SENDER. Si además se da
//    Mail.Send en Entra ID, la app puede enviar como CUALQUIER buzón.
//
//    Puente mientras tanto (sin código): SMTP_HOST=smtp.office365.com,
//    SMTP_PORT=587 y un buzón con licencia y SMTP AUTH habilitado.
//
// 2) SMTP (Gmail) — respaldo mientras no esté configurado lo anterior.
//      SMTP_USER / SMTP_PASS (App Password) / SMTP_HOST / SMTP_PORT / MAIL_FROM

const MS = {
  tenant: process.env.MS_TENANT_ID,
  client: process.env.MS_CLIENT_ID,
  secret: process.env.MS_CLIENT_SECRET,
  sender: process.env.MS_SENDER,
}
const usaGraph = () => !!(MS.tenant && MS.client && MS.secret && MS.sender)

export function mailerConfigured(): boolean {
  return usaGraph() || !!(process.env.SMTP_USER && process.env.SMTP_PASS)
}

export function mailFrom(): string {
  if (usaGraph()) return `SICOM Pillado <${MS.sender}>`
  return process.env.MAIL_FROM || `PILLADO ICEO <${process.env.SMTP_USER}>`
}

function getTransport() {
  const host = process.env.SMTP_HOST || 'smtp.gmail.com'
  const port = Number(process.env.SMTP_PORT || 465)
  return nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
  })
}

export function parseRecipients(envValue: string | undefined): string[] {
  if (!envValue) return []
  return envValue.split(/[,;]/).map((s) => s.trim()).filter(Boolean)
}

// El token de Graph dura ~1 h; en una función caliente se reutiliza.
let tokenCache: { valor: string; vence: number } | null = null

async function tokenGraph(): Promise<string> {
  if (tokenCache && tokenCache.vence > Date.now() + 60_000) return tokenCache.valor
  const r = await fetch(`https://login.microsoftonline.com/${MS.tenant}/oauth2/v2.0/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: MS.client!,
      client_secret: MS.secret!,
      scope: 'https://graph.microsoft.com/.default',
      grant_type: 'client_credentials',
    }),
  })
  const j = await r.json() as { access_token?: string; expires_in?: number; error_description?: string }
  if (!r.ok || !j.access_token) throw new Error(`Microsoft 365 (token): ${j.error_description ?? r.status}`)
  tokenCache = { valor: j.access_token, vence: Date.now() + (j.expires_in ?? 3600) * 1000 }
  return j.access_token
}

async function enviarGraph(opts: {
  to: string[]; cc: string[]; subject: string; html: string; replyTo?: string
}): Promise<void> {
  const dir = (address: string) => ({ emailAddress: { address } })
  // Sin «para» visible: el buzón se envía a sí mismo (misma regla que SMTP).
  const to = opts.to.length > 0 ? opts.to : [MS.sender!]
  const r = await fetch(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(MS.sender!)}/sendMail`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${await tokenGraph()}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      message: {
        subject: opts.subject,
        body: { contentType: 'HTML', content: opts.html },
        toRecipients: to.map(dir),
        ccRecipients: opts.cc.map(dir),
        replyTo: opts.replyTo ? [dir(opts.replyTo)] : [],
      },
      // No llenar «Elementos enviados» del buzón con cada aviso automático.
      saveToSentItems: false,
    }),
  })
  // 202 Accepted, sin cuerpo.
  if (!r.ok) {
    const t = await r.text().catch(() => '')
    throw new Error(`Microsoft 365 (${r.status}): ${t.slice(0, 300)}`)
  }
}

export async function sendMail(opts: {
  to: string[]
  /** Copia. Se usa para destinatarios externos que van informados, no a cargo. */
  cc?: string[]
  subject: string
  html: string
  text?: string
  replyTo?: string
}): Promise<{ ok: boolean; id?: string; error?: string }> {
  if (!mailerConfigured()) return { ok: false, error: 'Correo no configurado' }
  const cc = opts.cc ?? []
  if (opts.to.length === 0 && cc.length === 0) return { ok: false, error: 'Sin destinatarios' }

  if (usaGraph()) {
    try {
      await enviarGraph({ to: opts.to, cc, subject: opts.subject, html: opts.html, replyTo: opts.replyTo })
      return { ok: true, id: 'graph' }
    } catch (e) {
      return { ok: false, error: (e as Error).message }
    }
  }

  try {
    const info = await getTransport().sendMail({
      from: mailFrom(),
      // Un correo solo con copia no tiene destinatario visible y muchos
      // servidores lo tratan como spam: si no hay "para", el remitente se
      // pone a sí mismo.
      to: opts.to.length > 0 ? opts.to.join(', ') : mailFrom(),
      cc: cc.length > 0 ? cc.join(', ') : undefined,
      subject: opts.subject,
      html: opts.html,
      text: opts.text,
      replyTo: opts.replyTo,
    })
    return { ok: true, id: info.messageId }
  } catch (e) {
    return { ok: false, error: (e as Error).message }
  }
}
