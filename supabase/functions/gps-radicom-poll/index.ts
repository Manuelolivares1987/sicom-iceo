// ============================================================================
// supabase/functions/gps-radicom-poll/index.ts
// ----------------------------------------------------------------------------
// Edge Function (Deno) que consulta Navixy (backend de Radicom) y guarda
// posiciones + counters (odometro/horometro) en gps_eventos_log via la RPC
// `rpc_ingestar_gps_batch`.
//
// Estrategia de polling:
//   - Cada invocacion llama a Navixy tracker/get_states para TODOS los trackers
//     en 1 request -> liviano. Idealmente cron cada 60s.
//   - Si recibe el query param ?counters=1, ademas itera tracker/get_counters
//     por cada tracker (mas costoso). Recomendado: cron separado cada 5 min.
//
// Variables de entorno requeridas (Supabase las setea automaticamente):
//   - SUPABASE_URL
//   - SUPABASE_SERVICE_ROLE_KEY
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const PROVEEDOR_NOMBRE = "Radicom";

interface NavixyState {
  source_id?: number;
  gps?: {
    updated?: string;
    location?: { lat: number; lng: number };
    speed?: number;
    heading?: number;
    alt?: number;
    signal_level?: number;
  };
  connection_status?: string;
  movement_status?: string;
  ignition?: boolean;
  battery_level?: number;
  gsm?: { network_name?: string; signal_level?: number };
  inputs?: boolean[];
  outputs?: boolean[];
  last_update?: string;
}

interface NavixyCounter {
  type: string;
  value: number;
  update_time: string;
}

function tsNavixyToISO(s?: string): string | null {
  if (!s) return null;
  // Navixy entrega "YYYY-MM-DD HH:MM:SS" en UTC. Convertir a ISO.
  return s.replace(" ", "T") + "Z";
}

Deno.serve(async (req: Request) => {
  const tStart = performance.now();
  const url = new URL(req.url);
  const includeCounters = url.searchParams.get("counters") === "1";

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !serviceKey) {
    return new Response(
      JSON.stringify({ error: "Faltan envs SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY" }),
      { status: 500, headers: { "content-type": "application/json" } }
    );
  }

  const supabase = createClient(supabaseUrl, serviceKey);

  // 1. Leer config Radicom (api_base_url + api_token)
  const { data: proveedor, error: errProv } = await supabase
    .from("config_gps_proveedor")
    .select("id, api_base_url, api_token, activo")
    .eq("nombre", PROVEEDOR_NOMBRE)
    .single();

  if (errProv || !proveedor) {
    return new Response(
      JSON.stringify({ error: `Proveedor ${PROVEEDOR_NOMBRE} no configurado`, detail: errProv?.message }),
      { status: 500, headers: { "content-type": "application/json" } }
    );
  }

  if (!proveedor.activo) {
    return new Response(
      JSON.stringify({ skipped: true, reason: "Proveedor inactivo" }),
      { status: 200, headers: { "content-type": "application/json" } }
    );
  }

  if (!proveedor.api_base_url || !proveedor.api_token) {
    return new Response(
      JSON.stringify({ error: "Proveedor sin api_base_url o api_token" }),
      { status: 500, headers: { "content-type": "application/json" } }
    );
  }

  const baseUrl = proveedor.api_base_url.replace(/\/+$/, "");
  const hash    = proveedor.api_token;

  try {
    // 2. tracker/list -> obtener IDs activos
    const listRes = await fetch(`${baseUrl}/tracker/list`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ hash }),
    });
    const listJson = await listRes.json();
    if (!listJson.success) throw new Error(`tracker/list fallo: ${JSON.stringify(listJson)}`);

    const trackerIds: number[] = (listJson.list ?? []).map((t: { id: number }) => t.id);
    if (trackerIds.length === 0) {
      return new Response(JSON.stringify({ ok: true, trackers: 0 }), { status: 200 });
    }

    // 3. tracker/get_states con todos los IDs (Navixy acepta arrays grandes)
    const statesRes = await fetch(`${baseUrl}/tracker/get_states`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        hash,
        trackers: trackerIds,
        allow_not_exist: true,
        list_blocked: true,
      }),
    });
    const statesJson = await statesRes.json();
    if (!statesJson.success) throw new Error(`get_states fallo: ${JSON.stringify(statesJson)}`);

    // 4. (Opcional) get_counters por cada tracker. Costoso, solo cuando ?counters=1.
    const countersByTracker: Record<string, NavixyCounter[]> = {};
    if (includeCounters) {
      for (const tid of trackerIds) {
        try {
          const cRes = await fetch(`${baseUrl}/tracker/get_counters`, {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({ hash, tracker_id: tid }),
          });
          const cJson = await cRes.json();
          if (cJson.success) countersByTracker[String(tid)] = cJson.list ?? [];
        } catch (_) {
          // Skip — no romper el batch por un counter
        }
      }
    }

    // 5. Construir eventos para rpc_ingestar_gps_batch
    const eventos: Record<string, unknown>[] = [];
    for (const [tid, raw] of Object.entries(statesJson.states ?? {})) {
      const st = raw as NavixyState;
      const counters = countersByTracker[tid] ?? [];
      const odo = counters.find((c) => c.type === "odometer")?.value;
      const eh  = counters.find((c) => c.type === "engine_hours")?.value;

      eventos.push({
        gps_device_id: tid,
        ts_gps:        tsNavixyToISO(st.gps?.updated ?? st.last_update),
        lat:           st.gps?.location?.lat ?? null,
        lng:           st.gps?.location?.lng ?? null,
        speed:         st.gps?.speed ?? null,
        heading:       st.gps?.heading ?? null,
        altitude:      st.gps?.alt ?? null,
        ignition:      st.ignition ?? null,
        movement:      st.movement_status ?? null,
        connection:    st.connection_status ?? null,
        odometer_km:   odo ?? null,
        engine_hours:  eh ?? null,
        battery_pct:   st.battery_level ?? null,
        gsm_network:   st.gsm?.network_name ?? null,
        gsm_signal:    st.gsm?.signal_level ?? null,
        inputs:        st.inputs ?? null,
        outputs:       st.outputs ?? null,
        payload:       st,
      });
    }

    // 6. Llamar RPC bulk insert
    const { data: rpcRes, error: errRpc } = await supabase.rpc("rpc_ingestar_gps_batch", {
      p_proveedor_nombre: PROVEEDOR_NOMBRE,
      p_eventos:          eventos,
    });

    if (errRpc) throw new Error(`RPC fallo: ${errRpc.message}`);

    const elapsedMs = Math.round(performance.now() - tStart);

    return new Response(
      JSON.stringify({
        ok:           true,
        trackers:     trackerIds.length,
        eventos:      eventos.length,
        counters:     includeCounters,
        rpc:          rpcRes,
        elapsed_ms:   elapsedMs,
      }),
      { status: 200, headers: { "content-type": "application/json" } }
    );

  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { "content-type": "application/json" } }
    );
  }
});
