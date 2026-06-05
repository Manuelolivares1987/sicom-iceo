'use client'

import { FiabilidadAnalisis } from '@/components/fiabilidad/fiabilidad-analisis'

// El reporte completo vive en el componente reutilizable FiabilidadAnalisis
// (también lo embebe la Vista Comercial en modo solo lectura).
export default function FiabilidadPage() {
  return <FiabilidadAnalisis />
}
