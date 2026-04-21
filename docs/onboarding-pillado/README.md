# Onboarding Pillado — Material de estudio

Carpeta con todo lo necesario para el primer día de trabajo en Pillado, operando sobre el sistema SICOM-ICEO.

## Archivos

| Archivo | Formato | Uso |
|---|---|---|
| `01-Guia-Estudio-Pillado.docx` | Word | Para estudiar. Contiene negocio, módulos, estado dual de activos, cálculo OEE (fórmula + ejemplo), normativa chilena, alertas iniciales, glosario y checklist primera semana. |
| `02-Plantilla-Notion-Preguntas.md` | Markdown | Para pegar directo en una página de Notion. Banco de preguntas por tema con checkboxes. |
| `_build_guia.py` | Python | Script que regenera el Word si necesitas actualizar contenido. Requiere `python-docx`. |

## Cómo regenerar el Word

Si editas el contenido, vuelve a generar el `.docx`:

```bash
cd docs/onboarding-pillado
python _build_guia.py
```
