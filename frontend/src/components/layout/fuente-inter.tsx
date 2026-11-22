'use client'

// [22-11-2026] Tipografía Inter sin bloquear el primer dibujo y sin depender de
// la red al COMPILAR. next/font/google la bajaba durante el build: un corte
// hacia Google rompía la compilación (pasó en CI). Una hoja de estilos normal
// en el <head> bloqueaba el primer dibujo ~2 s en 4G lenta. Aquí se pide
// después de montar: mientras tanto (y sin señal) se ve la letra del sistema.
import { useEffect } from 'react'

const HREF = 'https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap'

export function FuenteInter() {
  useEffect(() => {
    if (document.querySelector(`link[href="${HREF}"]`)) return
    const l = document.createElement('link')
    l.rel = 'stylesheet'
    l.href = HREF
    document.head.appendChild(l)
  }, [])
  return null
}
