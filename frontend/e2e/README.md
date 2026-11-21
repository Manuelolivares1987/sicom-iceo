# Pruebas E2E de la app de terreno

La app de Franke abierta en un **Android simulado** (Pixel 5, Chromium) con un
**Supabase simulado** (`https://e2e.supabase.co`, ver `fake-supabase.ts`). Ninguna
prueba toca la base real ni usa claves de nadie.

## Correr

```bash
cd frontend
npm run e2e:build          # compila con Supabase simulado (no usar el build normal)
npm run e2e                # levanta `next start -p 3100` y corre todo
npx playwright test --ui   # para mirar paso a paso
```

En GitHub corren solas en cada PR (job `e2e-terreno` de `ci.yml`). Si fallan,
el informe con capturas y trazas queda como artefacto `informe-e2e-terreno`.

## Qué cubren

| Archivo | Situación de faena |
|---|---|
| `arranque.spec.ts` | Abrir con señal la 1ª vez; en **modo avión** desde el ícono y las 9 pantallas; sesión vencida sin señal; Chrome con datos bloqueados; `/instalar/` y `/reparar/` |
| `sincronizacion.spec.ts` | Novedad escrita sin señal sube sola; **respuesta perdida** (el servidor guardó, el teléfono no se enteró) → no duplica; servidor caído → espera, no rechaza |
| `entrega.spec.ts` | [F4] Abrir una entrega **nueva** sin señal con la plantilla; periodo sin datos → mensaje claro |
| `flujos.spec.ts` | En modo avión y de punta a punta: **carga del camión** con foto del ticket (y respuesta perdida sin duplicar), **despacho** con foto del medidor, **bodega** con el lector, **pauta** NO OK con foto (sin foto no cierra). Se revisa qué llegó al servidor: una vez y con su foto |
| `actualizacion.spec.ts` | **Versión nueva** con pendientes en el teléfono: se aplica (sola al abrir o con «Actualizar»), no pierde nada y sigue abriendo sin señal. Va sola al final: cambia `public/sw.js` y lo restaura |

## Agregar una prueba

- El simulador contesta `[]` / `null` a lo que no conoce y lo lista al final
  («sin respuesta preparada»). Prepare en la prueba lo que la pantalla necesita:
  `fake.tablas.<tabla> = [...]` o `fake.rpcs.<rpc> = (args, db) => ...`.
- `fake.perderRespuesta.add('<rpc>')`: el servidor procesa pero el teléfono no recibe respuesta.
- `fake.caido = true`: todo responde 503.
- `modoAvion(true)`: modo avión. Corta la página **y** el service worker (el `setOffline` de Playwright no corta lo que pide el service worker).
- `subirHastaTerminar(page)`: en Pendientes aprieta «Subir ahora» hasta «Todo subido».
