#!/usr/bin/env python3
# Exporta la hoja Flota_Pesada de la Biblioteca Maestra a
# database/copiloto/conocimiento/flota_pesada.json (ExcelJS no lee ese .xlsx).
# Uso: python copiloto-flota-json.py [ruta.xlsx]
import json
import sys
from pathlib import Path

import openpyxl

sys.stdout.reconfigure(encoding="utf-8")

xlsx = sys.argv[1] if len(sys.argv) > 1 else r'C:\Users\Manuel Olivares\Downloads\Biblioteca_Maestra_Mantenimiento_Pillado.xlsx'
destino = Path(__file__).resolve().parent.parent / 'copiloto' / 'conocimiento' / 'flota_pesada.json'
ws = openpyxl.load_workbook(xlsx, data_only=True)['Flota_Pesada']
filas = list(ws.iter_rows(values_only=True))
cab = [str(c).strip() for c in filas[0]]
equipos = [{cab[i]: (v if v is None or isinstance(v, (int, float)) else str(v).strip()) for i, v in enumerate(r)}
           for r in filas[1:] if r[0]]
destino.write_text(json.dumps({'fuente': f'{Path(xlsx).name} (hoja Flota_Pesada)', 'equipos': equipos},
                              ensure_ascii=False, indent=1), encoding='utf-8')
print(f'{len(equipos)} equipos → {destino}')
