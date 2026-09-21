#!/usr/bin/env python3
# ============================================================================
# copiloto-aportes-pdf.py — convierte las FOTOS aportadas por los mecánicos
# (etiquetas de fusibles, placas, diagramas pegados en el equipo) en PDFs de
# una página: arriba la descripción como TEXTO (buscable por la ingesta), y
# abajo la foto (el copiloto la ve con ver_pagina tras copiloto-paginas.py).
#
# Flujo de jefatura (2026-09-19):
#   node copiloto-conocimiento.mjs --aportes      # baja a Manuales/_Aportes taller/
#   (revisar y borrar lo que no sirva)
#   python copiloto-aportes-pdf.py                # fotos → PDF
#   node copiloto-ingesta.mjs --dir "<...>/Manuales/_Aportes taller"
#   python copiloto-paginas.py --doc "aporte taller"
# ============================================================================
import sys
from pathlib import Path

import fitz  # PyMuPDF

sys.stdout.reconfigure(encoding="utf-8")
DIR = Path('C:/Users/Manuel Olivares/Desktop/OPERACIONES/00_PILLADO (PRIORIDAD)/01_OPERACIONES/Mantenimiento/Manuales/_Aportes taller')

n = 0
for img in sorted(DIR.glob('*')):
    if img.suffix.lower() not in ('.jpg', '.jpeg', '.png', '.webp'):
        continue
    pdf = img.with_suffix('.pdf')
    if pdf.exists():
        continue
    txt = img.with_suffix('.txt')
    desc = txt.read_text(encoding='utf-8').strip() if txt.exists() else img.stem
    doc = fitz.open()
    pix = fitz.Pixmap(str(img))
    ancho, banda = 595, 70                       # A4 de ancho, banda de texto arriba
    alto_img = ancho * pix.height / pix.width
    page = doc.new_page(width=ancho, height=alto_img + banda)
    page.insert_textbox(fitz.Rect(20, 12, ancho - 20, banda - 6),
                        f'Aporte del taller: {desc}', fontsize=10, fontname='helv')
    page.insert_image(fitz.Rect(0, banda, ancho, banda + alto_img), filename=str(img))
    doc.save(pdf)
    doc.close()
    n += 1
    print(f'  → {pdf.name}')
print(f'{n} fotos convertidas a PDF en {DIR}')
