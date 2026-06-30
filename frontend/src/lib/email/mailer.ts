import nodemailer from 'nodemailer'

// Envío de correo por SMTP (Gmail gratuito por defecto).
// Variables de entorno (Netlify → Site settings → Environment):
//   SMTP_USER  → la dirección Gmail que envía (ej. taller.pillado@gmail.com)
//   SMTP_PASS  → la "Contraseña de aplicación" de 16 caracteres (NO la del correo)
//   SMTP_HOST  → opcional, default smtp.gmail.com
//   SMTP_PORT  → opcional, default 465 (SSL)
//   MAIL_FROM  → opcional, default "PILLADO ICEO <SMTP_USER>"
// Para Gmail: activar verificación en 2 pasos y crear una App Password.

export function mailerConfigured(): boolean {
  return !!(process.env.SMTP_USER && process.env.SMTP_PASS)
}

export function mailFrom(): string {
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

// Lee una lista de correos desde una variable de entorno (separados por coma/;)
export function parseRecipients(envValue: string | undefined): string[] {
  if (!envValue) return []
  return envValue.split(/[,;]/).map((s) => s.trim()).filter(Boolean)
}

export async function sendMail(opts: {
  to: string[]
  subject: string
  html: string
  text?: string
  replyTo?: string
}): Promise<{ ok: boolean; id?: string; error?: string }> {
  if (!mailerConfigured()) return { ok: false, error: 'SMTP no configurado' }
  if (opts.to.length === 0) return { ok: false, error: 'Sin destinatarios' }
  try {
    const info = await getTransport().sendMail({
      from: mailFrom(),
      to: opts.to.join(', '),
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
