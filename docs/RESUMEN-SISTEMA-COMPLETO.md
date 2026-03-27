# SICOM-ICEO: Sistema Integral de Control Operacional

## Resumen Ejecutivo

SICOM-ICEO es un sistema de gestion operacional de grado industrial para contratos de servicios mineros. Gestiona el ciclo completo de ordenes de trabajo (OTs), control de inventario, mantenimiento de activos, abastecimiento de combustibles/lubricantes, cumplimiento documental, y calculo automatizado de KPIs e ICEO (Indice de Cumplimiento y Excelencia Operacional).

**Estado:** Operativo en produccion
**Stack:** Next.js 14 + Supabase PostgreSQL + Tailwind CSS + React Query
**Deploy:** Netlify (frontend) + Supabase Cloud (backend)

---

## 1. Arquitectura del Sistema

### Modulos Principales (22 paginas)

| Modulo | Ruta | Funcion |
|--------|------|---------|
| Dashboard | `/dashboard` | Vista general: ICEO, KPIs, OTs activas, alertas |
| Ordenes de Trabajo | `/dashboard/ordenes-trabajo` | Crear, asignar, ejecutar, cerrar OTs de todos los tipos |
| Detalle OT | `/dashboard/ordenes-trabajo/[id]` | Checklist, fotos, materiales, costos, historial |
| Mis OTs | `/dashboard/mis-ots` | Vista del tecnico con sus OTs asignadas |
| Activos | `/dashboard/activos` | Registro de equipos con QR, certificaciones, metricas |
| Mantenimiento | `/dashboard/mantenimiento` | Plan semanal, calendario PM, pautas del fabricante |
| Inventario | `/dashboard/inventario` | Stock valorizado, movimientos, conteos, alertas de compra |
| Salida Inventario | `/dashboard/inventario/salida` | Retiro de materiales vinculado a OT |
| Conteo Fisico | `/dashboard/inventario/conteo` | Conteo con escaner de codigo de barras |
| Abastecimiento | `/dashboard/abastecimiento` | Rutas de despacho, puntos por faena, registros |
| Cumplimiento | `/dashboard/cumplimiento` | Certificaciones, vencimientos, documentos bloqueantes |
| KPI | `/dashboard/kpi` | 21 indicadores en 3 areas con drill-down |
| ICEO | `/dashboard/iceo` | Score consolidado, tendencia, incentivos, bloqueantes |
| Contratos | `/dashboard/contratos` | Gestion de contratos de servicio |
| Reportes | `/dashboard/reportes` | Exportacion de datos y reportes |
| Auditoria | `/dashboard/auditoria` | Log completo de todos los cambios del sistema |
| Administracion | `/dashboard/admin` | Gestion de usuarios y plantillas de checklist |
| Ficha Equipo | `/equipo/[id]` | Vista publica de activo (acceso via QR) |

### Capas de Software

- **13 archivos de servicios** (capa de acceso a datos via Supabase)
- **14 hooks personalizados** (React Query para estado y cache)
- **28+ funciones RPC transaccionales** (logica atomica en PostgreSQL)
- **35+ tablas** en base de datos con RLS (Row Level Security)
- **19 tipos enum** estandarizando el vocabulario del dominio
- **24 archivos SQL** de esquema en orden secuencial

---

## 2. Ordenes de Trabajo (OT) - El Centro del Sistema

### Tipos de OT (7)

| Tipo | Descripcion | Color |
|------|-------------|-------|
| Inspeccion | Revision programada de equipos | Azul |
| Preventivo | Mantenimiento segun pauta del fabricante | Verde |
| Correctivo | Reparacion de fallas detectadas | Rojo |
| Abastecimiento | Despacho de combustible a puntos | Ambar |
| Lubricacion | Servicio de lubricacion a equipos | Morado |
| Inventario | Conteo fisico y regularizacion de stock | Cyan |
| Regularizacion | Ajustes administrativos | Gris |

### Ciclo de Vida de una OT (Maquina de Estados)

```
CREADA → ASIGNADA → EN_EJECUCION → EJECUTADA_OK → CERRADA (supervisor)
                         ↓               ↓
                      PAUSADA    EJECUTADA_CON_OBSERVACIONES
                         ↓               ↓
                   EN_EJECUCION    CERRADA (supervisor)

                   NO_EJECUTADA → CERRADA (supervisor)
                   CANCELADA (terminal)
```

**Reglas clave:**
- Toda OT genera un folio unico automatico: `OT-YYYYMM-XXXXX`
- Se genera un codigo QR para trazabilidad
- El checklist se pre-popula desde la pauta del fabricante (si es preventiva)
- No se puede finalizar sin evidencia fotografica
- No se puede finalizar sin completar items obligatorios del checklist
- Al cerrar el supervisor, se congelan los costos y se recalculan los KPIs automaticamente
- Una OT cerrada es INMUTABLE (no se puede modificar nada)

### Que se puede hacer en cada OT

1. **Checklist interactivo:** Marcar items como OK / NO OK / N/A, agregar observaciones, subir fotos por item
2. **Evidencias fotograficas:** Subir fotos antes/durante/despues con descripcion
3. **Registro de materiales:** Seleccionar productos del inventario de la bodega, registrar consumo (descuenta stock automaticamente)
4. **Valorizacion de costos:** Registrar horas hombre y tarifa, ver desglose de materiales + mano de obra + total
5. **Edicion de campos:** Cambiar prioridad, fecha, responsable y observaciones (solo en estado creada/asignada)
6. **Historial:** Timeline completo de todos los cambios de estado

### Priodidades (5 niveles)

Emergencia > Urgente > Alta > Normal > Baja

---

## 3. Plan Semanal de Trabajo

### Concepto

El encargado de sucursal (faena) planifica semanalmente TODAS las ordenes de trabajo. El mantenimiento preventivo es una **sugerencia automatica** basada en los planes de mantenimiento, pero el encargado puede:

- **Aceptar** sugerencias PM (crea OT preventiva automaticamente)
- **Descartar** sugerencias que no aplican esa semana
- **Agregar OTs manuales** de cualquier tipo (correctiva, abastecimiento, lubricacion, etc.)
- **Modificar** OTs ya creadas (cambiar fecha, prioridad, responsable)

### Vista del Plan Semanal

- **Selector de semana:** Navegar entre semanas (anterior/actual/siguiente)
- **Vista por dia:** Cada dia muestra sugerencias PM + OTs planificadas
- **Boton "+ Agregar OT"** por dia con fecha pre-seteada
- **Resumen semanal:** Conteo por tipo de OT + materiales/repuestos necesarios consolidados

### Flujo

1. Lunes: El planificador revisa las sugerencias PM de la semana
2. Acepta las que corresponden, descarta las que no
3. Agrega OTs correctivas, de abastecimiento, lubricacion, etc.
4. Asigna responsables y prioridades
5. Los tecnicos ven sus OTs asignadas en "Mis OTs"
6. Al ejecutar y cerrar cada OT, los KPIs se recalculan automaticamente

---

## 4. Inventario y Bodega

### Estructura

- **Bodegas** por faena (cada sitio minero tiene su(s) bodega(s))
- **Productos:** Combustibles, lubricantes, filtros, repuestos, consumibles
- **Stock por bodega:** Cantidad actual, stock minimo, stock maximo, costo promedio ponderado
- **Valorizacion:** Metodo CPP (Costo Promedio Ponderado)

### Tipos de Movimiento (8)

| Tipo | Descripcion |
|------|-------------|
| Entrada | Recepcion de compra/proveedor |
| Salida | Consumo vinculado a OT (obligatorio) |
| Ajuste positivo | Correccion al alza |
| Ajuste negativo | Correccion a la baja (requiere motivo) |
| Transferencia entrada | Recepcion desde otra bodega |
| Transferencia salida | Envio a otra bodega |
| Merma | Perdida por deterioro/evaporacion |
| Devolucion | Material devuelto |

### Regla critica: Toda salida requiere OT

No se puede retirar material de bodega sin una OT en estado `en_ejecucion` o `asignada`. Esto asegura trazabilidad total del consumo de materiales y alimenta los KPIs de inventario.

### Conteo Fisico

1. Se crea sesion de conteo (ciclico, general o selectivo)
2. Se escanean productos con codigo de barras o camara
3. El sistema compara stock fisico vs stock sistema
4. Se calculan diferencias y valor de la variacion
5. Supervisor aprueba → se generan ajustes automaticos

### Alertas de Compra

- Tab "Alertas" muestra productos bajo stock minimo
- Para cada producto: stock actual, minimo, maximo, cantidad sugerida a comprar, costo estimado
- Boton "Exportar Lista de Compra" genera CSV con toda la informacion

---

## 5. Activos y Mantenimiento Preventivo

### Tipos de Activos (15)

Puntos fijos: surtidor, dispensador, estanque, bomba, manguera, punto_fijo
Puntos moviles: camion_cisterna, lubrimovil, camioneta, camion, punto_movil
Otros: equipo_bombeo, herramienta_critica, pistola_captura, equipo_menor

### Datos del Activo

- Codigo, nombre, tipo, criticidad (critica/alta/media/baja)
- Numero de serie, marca, modelo con especificaciones tecnicas (JSON)
- Estado: operativo, en_mantenimiento, fuera_servicio, dado_baja, en_transito
- Metricas: kilometraje actual, horas de uso, ciclos
- QR code unico para identificacion y trazabilidad
- Certificaciones vinculadas (SEC, SEREMI, SOAP, etc.)

### Pautas del Fabricante

Cada modelo de equipo tiene pautas de mantenimiento que definen:
- Tipo de plan: por tiempo, por km, por horas, por ciclos, mixto
- Frecuencia (ej: cada 250 horas, cada 10.000 km, cada 90 dias)
- Items de checklist predefinidos
- Materiales estimados necesarios
- Duracion estimada en horas

### Planes de Mantenimiento

- Vinculan un activo especifico con una pauta del fabricante
- Registran la ultima y proxima ejecucion
- Generan sugerencias automaticas en el Plan Semanal
- Se actualizan automaticamente al cerrar la OT preventiva

---

## 6. Abastecimiento y Lubricacion

### Rutas de Despacho

Las rutas programan el recorrido de un camion cisterna o lubrimovil por los puntos de servicio de una faena:
- Faena, fecha programada, puntos programados, km programados
- Estado: programada → en_ejecucion → completada/incompleta
- Seguimiento: puntos completados, km reales, litros despachados

### Registros de Abastecimiento

Cada parada en la ruta genera un registro con:
- Punto destino (activo que recibe combustible/lubricante)
- Producto despachado
- Cantidad programada vs cantidad real
- Operador, fecha/hora

### Puntos por Faena

Vista que muestra todos los puntos de servicio (surtidores, estanques, bombas) de una faena con:
- Capacidad del tanque (desde especificaciones del modelo)
- Ultimo abastecimiento (fecha y cantidad)
- Nivel estimado con barra visual (verde >50%, amarillo 20-50%, rojo <20%)
- Cantidad sugerida a rellenar

---

## 7. Cumplimiento Documental

### Certificaciones

Cada activo puede tener multiples certificaciones:
- **Tipos:** SEC, SEREMI, SISS, Revision Tecnica, SOAP, Calibracion, Licencia, Otro
- **Estados:** Vigente (verde), Por Vencer (amarillo, 30 dias antes), Vencido (rojo)
- **Bloqueante:** Si una certificacion es bloqueante y esta vencida, impide cerrar OTs del activo

### Operaciones

- Crear nueva certificacion con upload de archivo
- Renovar certificacion (pre-llena datos de la anterior)
- Filtrar por estado, tipo, faena
- Dashboard con estadisticas: total, vigentes, por vencer, vencidas

---

## 8. KPIs - 21 Indicadores en 3 Areas

### Area A: Administracion Combustibles y Lubricantes (peso 35%)

| KPI | Nombre | Fuente de Datos |
|-----|--------|-----------------|
| A1 | Diferencia inventario combustibles | Conteos de inventario |
| A2 | Diferencia inventario lubricantes | Conteos de inventario |
| A3 | Exactitud inventario IRA | Items sin diferencia / total |
| A4 | Cumplimiento normativo | Certificaciones vigentes / requeridas |
| A5 | Cumplimiento abastecimiento programado | OTs abastecimiento ejecutadas / programadas |
| A6 | Rotacion de stock anualizada | Movimientos de inventario |
| A7 | Despacho oportuno | Rutas completadas a tiempo |

### Area B: Mantenimiento Puntos Fijos (peso 35%)

| KPI | Nombre | Fuente de Datos |
|-----|--------|-----------------|
| B1 | OTs preventivas ejecutadas | OTs preventivas ejecutadas / programadas |
| B2 | MTTR (Mean Time To Repair) | Historial de OTs correctivas |
| B3 | Disponibilidad equipos fijos | Horas operativas / horas totales |
| B4-B7 | Otros indicadores operacionales | OTs, incidentes, activos |

### Area C: Mantenimiento Puntos Moviles (peso 30%)

| KPI | Nombre | Fuente de Datos |
|-----|--------|-----------------|
| C1 | OTs preventivas flota ejecutadas | OTs preventivas ejecutadas / programadas |
| C2-C7 | Otros indicadores de flota | OTs, disponibilidad, incidentes |

### Calculo de KPIs

Cada KPI tiene:
- **Formula:** Funcion SQL dedicada que consulta datos reales
- **Meta:** Valor objetivo a alcanzar
- **Tramos:** Bandas de puntaje (ej: >=98% = 100pts, 95-97% = 90pts, etc.)
- **Peso:** Contribucion al ICEO de su area
- **Direccion:** Mayor es mejor (default) o menor es mejor (ej: diferencias de inventario)
- **Bloqueante:** Si activa, puede anular el ICEO completo

### Disparo del Calculo

- **Automatico:** Al finalizar una OT o al cerrarla el supervisor, el sistema recalcula KPIs del mes
- **Manual:** Boton "Calcular KPIs" en las paginas de KPI e ICEO
- **Programado:** Job de pgcron mensual

---

## 9. ICEO - Indice de Cumplimiento y Excelencia Operacional

### Formula

```
ICEO = (Puntaje_Area_A × 0.35) + (Puntaje_Area_B × 0.35) + (Puntaje_Area_C × 0.30)
```

Donde cada puntaje de area es la suma ponderada de los KPIs de esa area.

### Clasificacion

| Rango | Clasificacion | Significado |
|-------|---------------|-------------|
| >= 95 | Excelencia | Operacion de clase mundial |
| 85 - 94 | Bueno | Cumple estandares satisfactoriamente |
| 70 - 84 | Aceptable | Cumple minimamente, hay areas de mejora |
| < 70 | Deficiente | Requiere accion correctiva inmediata |

### Bloqueantes

Algunos KPIs son **bloqueantes** - si su cumplimiento cae bajo un umbral critico, el efecto puede ser:

1. **Anular:** ICEO = 0 (mas severo, ej: documentacion legal al 0%)
2. **Penalizar:** ICEO × factor (ej: ICEO × 0.5 = 50% de penalizacion)
3. **Descontar:** ICEO - puntos (ej: restar 20 puntos)
4. **Bloquear incentivo:** ICEO no cambia pero se bloquea el pago de incentivos

### Incentivos

El ICEO alimenta el calculo de incentivos del personal:
- Si ICEO >= umbral minimo Y no hay bloqueantes activos → incentivo habilitado
- El monto del incentivo depende del tramo de ICEO alcanzado
- Se muestra en el dashboard de ICEO con desglose por persona

### Flujo Completo

```
1. Tecnico ejecuta OT → completa checklist, sube fotos, registra materiales
2. Tecnico finaliza OT → sistema recalcula KPIs del mes automaticamente
3. Supervisor cierra OT → costos congelados, KPIs recalculados
4. KPIs alimentan ICEO → score 0-100 con clasificacion
5. ICEO determina incentivos → habilitado/bloqueado segun bloqueantes
6. Dashboard muestra todo en tiempo real
```

---

## 10. Roles de Usuario (10)

| Rol | Acceso Principal |
|-----|-----------------|
| Administrador | Acceso total a todos los modulos |
| Gerencia | Dashboard, KPI, ICEO, reportes (solo lectura) |
| Subgerente Operaciones | Operaciones, abastecimiento, supervision |
| Supervisor | Cierre de OTs, aprobacion de conteos, certificaciones |
| Planificador | Creacion de OTs, plan semanal, asignacion |
| Tecnico Mantenimiento | Ejecucion de OTs, checklist, evidencias |
| Bodeguero | Inventario completo: entradas, salidas, conteos |
| Operador Abastecimiento | Ejecucion de rutas de despacho |
| Auditor | Lectura de auditoria y todos los modulos |
| RRHH Incentivos | ICEO e incentivos |

---

## 11. Seguridad y Auditoria

### Autenticacion
- Supabase Auth con email/password
- JWT tokens en cookie HTTP-only
- Sesion persistente con refresh automatico

### Autorizacion
- Row Level Security (RLS) en todas las tablas
- Politicas por rol: cada usuario solo ve datos de su faena/contrato
- Funciones RPC con SECURITY DEFINER para operaciones transaccionales

### Auditoria
- Trigger automatico en todas las tablas captura: tabla, operacion, datos anteriores/nuevos, usuario, timestamp
- Log inmutable (no se puede eliminar)
- Vista de auditoria con filtros por tabla, usuario, fecha

### Inmutabilidad
- OTs cerradas: trigger bloquea cualquier UPDATE
- Movimientos de inventario: append-only (no se editan ni eliminan)
- Mediciones KPI: se sobreescriben por periodo pero con timestamp

---

## 12. Integraciones Tecnicas

### Base de Datos
- **35+ tablas** organizadas por dominio
- **19 enums** estandarizando el vocabulario
- **28+ funciones RPC** para logica transaccional atomica
- **82+ funciones SQL** de calculo de KPIs
- **Triggers** para auditoria, actualizacion de timestamps, inmutabilidad

### Frontend
- **22 paginas** con Next.js 14 App Router
- **13 archivos de servicios** abstrayendo la comunicacion con Supabase
- **14 hooks personalizados** para estado, cache y mutaciones
- **React Query** para cache inteligente e invalidacion automatica
- **Tailwind CSS** para diseño responsive (mobile-first)
- **Recharts** para graficos de KPI e ICEO
- **html5-qrcode** para escaneo de codigos de barras con camara
- **React PDF** para exportacion de reportes

### Almacenamiento
- **Bucket evidencias-ot:** Fotos de checklist y evidencias de OTs
- **Bucket certificaciones:** Documentos de certificaciones de activos

---

## 13. Metricas del Sistema

| Categoria | Cantidad |
|-----------|----------|
| Paginas/Rutas frontend | 22 |
| Tablas en base de datos | 35+ |
| Enumeraciones SQL | 19 |
| Funciones RPC transaccionales | 28+ |
| Funciones SQL totales | 82+ |
| Archivos de servicios | 13 |
| Hooks React personalizados | 14 |
| Roles de usuario | 10 |
| KPIs definidos | 21 |
| Areas de KPI | 3 |
| Tipos de OT | 7 |
| Estados de OT | 9 |
| Tipos de movimiento inventario | 8 |
| Tipos de activo | 15 |
| Archivos SQL de esquema | 24 |
| Archivos de documentacion | 10+ |

---

## 14. Reglas de Negocio Criticas

1. **La OT es el centro:** Toda operacion (consumo de materiales, abastecimiento, mantenimiento) debe estar vinculada a una OT
2. **Sin evidencia no hay ejecucion:** No se puede finalizar una OT sin al menos 1 foto de evidencia
3. **Sin inventario no hay salida sin OT:** Toda salida de bodega requiere una OT valida en ejecucion
4. **Aislamiento por faena:** No se puede retirar material de una bodega de otra faena
5. **OT cerrada = inmutable:** Una vez cerrada por supervisor, nada se puede modificar
6. **Maquina de estados estricta:** Solo se permiten transiciones validas (creada→asignada→en_ejecucion→...)
7. **KPIs de datos reales:** No hay entrada manual de KPIs, todo se calcula desde las operaciones
8. **ICEO automatico:** Se calcula a partir de los 21 KPIs con pesos y bloqueantes
9. **Auditoria total:** Cada cambio en cada tabla se registra con usuario y timestamp
10. **Bloqueantes bloquean:** Si una certificacion bloqueante esta vencida, impide operaciones del activo

---

## 15. Propuesta de Valor

### Problema que Resuelve
Las empresas de servicios mineros gestionan operaciones complejas (mantenimiento, abastecimiento, inventario) en multiples faenas remotas, con equipos criticos que requieren alta disponibilidad. La falta de un sistema integrado genera:
- Perdida de trazabilidad en consumo de materiales
- Incumplimiento de mantenimientos preventivos
- Inventarios con diferencias no detectadas
- Imposibilidad de medir rendimiento operacional objetivamente
- Riesgo de incumplimiento de certificaciones legales

### Como lo Resuelve SICOM-ICEO
- **Planificacion semanal** con sugerencias automaticas de PM y OTs multi-tipo
- **Ejecucion trazable** con checklist, fotos, materiales vinculados
- **Inventario en tiempo real** con alertas de stock bajo y sugerencias de compra
- **KPIs automaticos** calculados desde datos operacionales reales
- **ICEO consolidado** que mide la excelencia operacional en un solo score
- **Cumplimiento documental** con alertas de vencimiento y bloqueo automatico
- **Auditoria completa** para responder ante fiscalizaciones

### Diferenciador
El ICEO no es un indicador subjetivo - se construye matematicamente desde 21 KPIs que se alimentan de las operaciones diarias reales del sistema. Cada OT cerrada, cada litro despachado, cada certificacion vigente o vencida, impacta directamente en el score. Esto crea un circulo virtuoso: mejor operacion → mejor ICEO → mejores incentivos.
