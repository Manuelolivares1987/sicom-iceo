#!/usr/bin/env python3
# ============================================================================
# copiloto-paginas.py — renderiza a imagen las páginas de diagramas, tablas de
# fusibles/relés y pinouts, y las sube al storage del proyecto copiloto-corpus.
# ----------------------------------------------------------------------------
# Manuel, 19-09-2026: los mecánicos piden sobre todo DIAGRAMAS ("diagrama del
# sistema AdBlue", "plano hidráulico del Volvo"). Un diagrama eléctrico en
# texto extraído es una sopa de etiquetas: hay que VERLO. Con estas imágenes:
#   - el mecánico ve la página citada en el teléfono (visor con zoom), y
#   - el copiloto la LEE con visión (herramienta ver_pagina) y explica el
#     circuito concreto.
#
# Qué documentos: los que por título/sistema son diagramas, esquemas, planos,
# fusibles/relés, body builder eléctrico/PTO o implementación eléctrica.
# Se ubica el PDF local por nombre y se confirma por sha256 contra el corpus.
#
# Requiere: PyMuPDF, requests; database/.env.copiloto.local con
#   COPILOTO_SUPABASE_URL y COPILOTO_SUPABASE_SERVICE_KEY
# Aplicar antes corpus_schema_v2.sql (tabla copiloto_paginas + bucket).
#
# Uso:
#   python copiloto-paginas.py --dry-run             # qué haría y cuánto pesa
#   python copiloto-paginas.py                       # render + subida
#   python copiloto-paginas.py --doc "Accelo"        # solo títulos que calcen
#   python copiloto-paginas.py --max-mb 700          # tope total de subida
# Idempotente: salta páginas ya subidas.
# ============================================================================
import argparse
import hashlib
import os
import re
import sys
import time
from pathlib import Path

import fitz  # PyMuPDF
import requests

sys.stdout.reconfigure(encoding="utf-8")

RAIZ = Path('C:/Users/Manuel Olivares/Desktop/OPERACIONES/00_PILLADO (PRIORIDAD)/01_OPERACIONES/Mantenimiento')
CARPETAS = [RAIZ / 'Mercedes ACTROS', RAIZ / 'Manuales']
ENV = Path(__file__).resolve().parent.parent / '.env.copiloto.local'
BUCKET = 'paginas'

# Títulos que son (o contienen mayormente) diagramas / tablas visuales
PATRON_DOC = re.compile(
    r'diagram|esquema|plano|el[eé]ctric|eletric|wiring|cableado|fus[ií]ve?l|rel[eé]s?\b|pinout|conector|'
    r'body ?builder|implementa|carrocer|pto|toma de fuerza|tomada de for|vecu|bbm|bwe|bci|'
    r'hidr[aá]ulic|neum[aá]tic|circuito|schalt|electrical|layout|aporte taller', re.I)
# Documentos que SON diagramas: se renderizan completos. En el resto (manuales
# de operación, implementación, body builder) solo las páginas visuales.
PATRON_DIAGRAMA = re.compile(r'aporte taller|diagram|esquema|plano|wiring|cableado|fus[ií]ve?l|pinout|schalt|circuito', re.I)
ANCHO_PX = 1600        # suficiente para leer pines y colores con zoom
CALIDAD_JPG = 62
MAX_PAGS_DOC = 400


def ruta_larga(p: Path) -> str:
    # Windows: nombres de Mercedes ACTROS superan MAX_PATH (260)
    s = str(p.resolve())
    prefijo = '\\\\?\\'
    return s if os.name != 'nt' or s.startswith(prefijo) else prefijo + s


def es_visual(page) -> bool:
    """Página con diagrama/tabla gráfica: poco texto, mucho trazo vectorial o
    una imagen grande (escaneo de un plano)."""
    txt = len(page.get_text('text').strip())
    if txt < 400:
        return True
    try:
        trazos = len(page.get_drawings())
    except Exception:  # noqa: BLE001
        trazos = 0
    if trazos > 250 and txt < 4000:
        return True
    area = abs(page.rect)
    img = sum(abs(r) for x in page.get_images(full=True) for r in page.get_image_rects(x[0]))
    return area > 0 and img / area > 0.45 and txt < 2500


def con_reintento(fn, intentos=4, que=''):
    """La subida de cientos de páginas se corta por red: reintenta con espera."""
    for i in range(intentos):
        try:
            return fn()
        except requests.exceptions.RequestException as e:
            if i == intentos - 1:
                print(f'  ✗ {que}: {e}')
                return None
            time.sleep(2 * (i + 1))
    return None


def cargar_env():
    env = {}
    for linea in ENV.read_text(encoding='utf-8').splitlines():
        if '=' in linea and not linea.strip().startswith('#'):
            k, v = linea.split('=', 1)
            env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--doc', help='regex extra sobre el título (reemplaza la selección por patrón)')
    ap.add_argument('--max-mb', type=float, default=800.0)
    a = ap.parse_args()

    env = cargar_env()
    url = env.get('COPILOTO_SUPABASE_URL', '').rstrip('/')
    key = env.get('COPILOTO_SUPABASE_SERVICE_KEY', '')
    if not url or not key:
        sys.exit('Faltan COPILOTO_SUPABASE_URL / COPILOTO_SUPABASE_SERVICE_KEY en ' + str(ENV))
    h = {'apikey': key, 'Authorization': f'Bearer {key}'}

    # Documentos del corpus candidatos
    docs = []
    desde = 0
    while True:
        r = requests.get(f'{url}/rest/v1/copiloto_documentos',
                         params={'select': 'id,hash,titulo,archivo,sistema,paginas,tipo_documento',
                                 'tipo_documento': 'neq.guia_tecnica_web', 'order': 'titulo'},
                         headers={**h, 'Range': f'{desde}-{desde + 999}'}, timeout=60)
        r.raise_for_status()
        lote = r.json()
        docs += lote
        if len(lote) < 1000:
            break
        desde += 1000
    patron = re.compile(a.doc, re.I) if a.doc else None
    cand = [d for d in docs if (patron.search(d['titulo']) if patron
                                else (PATRON_DOC.search(d['titulo'] or '') or d.get('sistema') == 'electrico'))]
    por_hash = {d['hash']: d for d in cand}
    nombres = {d['archivo'].lower() for d in cand}
    print(f'Corpus: {len(docs)} documentos · candidatos a imagen: {len(cand)}')

    # PDFs locales que calzan por nombre → confirmar por hash
    locales = []
    for c in CARPETAS:
        for p in c.rglob('*.pdf'):
            if p.name.lower() in nombres:
                sha = hashlib.sha256(Path(ruta_larga(p)).read_bytes()).hexdigest()
                if sha in por_hash:
                    locales.append((p, por_hash[sha]))
    print(f'PDFs locales encontrados: {len(locales)} de {len(cand)}')

    total_bytes = 0
    tope = a.max_mb * 1024 * 1024
    subidas = saltadas = 0
    for p, d in locales:
        ya = set()
        if not a.dry_run:
            r = con_reintento(lambda: requests.get(f'{url}/rest/v1/copiloto_paginas',
                              params={'select': 'pagina', 'documento_id': f'eq.{d["id"]}', 'limit': '1000'},
                              headers=h, timeout=60), que='páginas ya subidas')
            if r is None or r.status_code >= 300:
                continue
            ya = {x['pagina'] for x in r.json()}
        try:
            pdf = fitz.open(ruta_larga(p))
        except Exception as e:  # noqa: BLE001
            print(f'  ✗ {p.name}: {e}')
            continue
        n = min(pdf.page_count, MAX_PAGS_DOC)
        completo = bool(PATRON_DIAGRAMA.search(d['titulo'] or ''))
        bytes_doc = 0
        for i in range(n):
            pag = i + 1
            if pag in ya:
                saltadas += 1
                continue
            page = pdf[i]
            if not completo and not es_visual(page):
                continue
            zoom = ANCHO_PX / max(page.rect.width, 1)
            pix = page.get_pixmap(matrix=fitz.Matrix(zoom, zoom), alpha=False)
            jpg = pix.tobytes('jpeg', jpg_quality=CALIDAD_JPG)
            if total_bytes + len(jpg) > tope:
                print(f'Tope de {a.max_mb} MB alcanzado. Detenido.')
                pdf.close()
                print(f'Subidas {subidas} · ya estaban {saltadas} · {total_bytes / 1048576:.1f} MB')
                return
            total_bytes += len(jpg)
            bytes_doc += len(jpg)
            if a.dry_run:
                continue
            ruta = f'{d["id"]}/{pag:04d}.jpg'
            up = con_reintento(lambda: requests.post(f'{url}/storage/v1/object/{BUCKET}/{ruta}', data=jpg,
                               headers={**h, 'Content-Type': 'image/jpeg', 'x-upsert': 'true'}, timeout=120), que=f'subida {ruta}')
            if up is None:
                continue
            if up.status_code >= 300:
                print(f'  ✗ subida {ruta}: {up.status_code} {up.text[:120]}')
                continue
            ins = con_reintento(lambda: requests.post(f'{url}/rest/v1/copiloto_paginas',
                                json={'documento_id': d['id'], 'pagina': pag, 'storage_path': ruta,
                                      'ancho': pix.width, 'alto': pix.height, 'bytes': len(jpg)},
                                headers={**h, 'Prefer': 'resolution=merge-duplicates'}, timeout=60), que=f'registro {ruta}')
            if ins is None:
                continue
            if ins.status_code >= 300:
                print(f'  ✗ registro {ruta}: {ins.status_code} {ins.text[:120]}')
                continue
            subidas += 1
        pdf.close()
        print(f'  {"(dry) " if a.dry_run else ""}{p.name}: {n} págs · {bytes_doc / 1048576:.1f} MB')

    print(f'{"DRY-RUN · " if a.dry_run else ""}Subidas {subidas} · ya estaban {saltadas} · total {total_bytes / 1048576:.1f} MB')


if __name__ == '__main__':
    main()
