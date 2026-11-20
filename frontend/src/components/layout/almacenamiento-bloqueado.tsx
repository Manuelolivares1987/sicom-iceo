'use client'

// Pantalla para el teléfono cuyo Chrome no deja guardar datos a SICOM (20-11-2026).
// Sin estilos de Tailwind a propósito: también se usa desde global-error.

export function PantallaAlmacenamientoBloqueado() {
  const paso = { textAlign: 'left' as const, margin: '6px 0', fontSize: 15, lineHeight: 1.4 }
  return (
    <div style={{ fontFamily: 'system-ui, sans-serif', maxWidth: 420, margin: '0 auto', padding: '32px 20px', color: '#111827' }}>
      <p style={{ fontSize: 20, fontWeight: 700, margin: '0 0 8px' }}>Chrome no deja que SICOM guarde datos en este teléfono</p>
      <p style={{ fontSize: 15, color: '#374151', margin: '0 0 16px' }}>
        La app necesita guardar su sesión y su trabajo en el teléfono (así funciona sin señal). Hay que permitirlo una vez:
      </p>
      <ol style={{ paddingLeft: 20, margin: 0 }}>
        <li style={paso}>Abra <b>Chrome</b> y toque los <b>tres puntos ⋮</b> (arriba a la derecha).</li>
        <li style={paso}>Entre a <b>Configuración</b> → <b>Configuración de sitios</b>.</li>
        <li style={paso}>Toque <b>Datos del sitio en el dispositivo</b> (o <b>Cookies</b>) y déjelo en <b>Permitir</b>.</li>
        <li style={paso}>Si más abajo aparece <b>pilladoiceo.netlify.app</b> en «Bloqueados», tóquelo y elija <b>Permitir</b>.</li>
        <li style={paso}>Vuelva a abrir SICOM.</li>
      </ol>
      <a href="/instalar/" style={{ display: 'block', marginTop: 20, padding: 14, borderRadius: 10, background: '#111827', color: '#fff', fontSize: 15, fontWeight: 600, textAlign: 'center', textDecoration: 'none' }}>
        Mejor: instalar la app SICOM Terreno (no depende de Chrome)
      </a>
      <button type="button" onClick={() => window.location.reload()}
              style={{ marginTop: 20, width: '100%', padding: 14, borderRadius: 10, border: 0, background: '#16a34a', color: '#fff', fontSize: 15, fontWeight: 600 }}>
        Ya lo permití · abrir de nuevo
      </button>
    </div>
  )
}
