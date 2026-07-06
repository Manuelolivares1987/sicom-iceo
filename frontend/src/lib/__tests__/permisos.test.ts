import { describe, it, expect } from 'vitest'
import { defaultPermsForRole, ALL_ROLES } from '@/hooks/use-permissions'

const MODULOS = ['contratos', 'activos', 'ordenes_trabajo', 'inventario', 'mantenimiento', 'flota', 'comercial', 'admin', 'auditoria', 'prevencion', 'reporte_diario']

// Prioridad CI: helper de permisos. Estas pruebas fijan el CONTRATO de los
// defaults que el guard server-side (fn_tiene_permiso_modulo) usa como
// fuente de verdad (MIG126/185/189). Un cambio accidental rompe el gate.
describe('permisos: defaults por rol', () => {
  it('administrador tiene acciones amplias en módulos núcleo', () => {
    expect(defaultPermsForRole('administrador', 'ordenes_trabajo')).toContain('approve')
    expect(defaultPermsForRole('administrador', 'contratos')).toContain('edit')
  })

  it('cierre diario (flota/approve): NINGÚN rol lo tiene por default (fail-closed; admin pasa por anti-lockout del guard)', () => {
    const conApprove = ALL_ROLES.filter((r) => defaultPermsForRole(r, 'flota').includes('approve'))
    expect(conApprove).toEqual([])
  })

  it('un rol operativo NO tiene edit de contratos (evita IDOR de contrato)', () => {
    expect(defaultPermsForRole('bodeguero', 'contratos')).not.toContain('edit')
    expect(defaultPermsForRole('tecnico_mantenimiento', 'contratos')).not.toContain('edit')
  })

  it('las acciones declaradas están dentro del vocabulario canónico', () => {
    const validas = new Set(['view', 'create', 'edit', 'delete', 'approve', 'export'])
    for (const rol of ALL_ROLES) {
      for (const mod of MODULOS) {
        for (const a of defaultPermsForRole(rol, mod)) {
          expect(validas.has(a)).toBe(true)
        }
      }
    }
  })
})
