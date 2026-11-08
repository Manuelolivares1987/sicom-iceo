# RAG técnico para taller: buenas prácticas implementables (2025-2026)

Contexto del sistema objetivo: ~700 PDFs (manuales de taller ES/EN/DE, diagramas eléctricos, muchos escaneados sin texto), Supabase Postgres con FTS `spanish_unaccent` sobre ~10k chunks, sin vectores; Claude como agente con herramientas (search_chunks, códigos de falla, historial de equipo, web search); entrada de fotos; debe citar documento+página y no inventar valores físicos.

Nota metodológica: investigación hecha el 2026-11-08 con unas 15 consultas web. Las fuentes primarias son la documentación de Anthropic y Supabase, el blog de ingeniería de Anthropic, el blog de Snowflake y papers de arXiv. Muchos benchmarks de modelos (embeddings, rerankers, OCR, STT) los publican los propios proveedores o agregadores, y se marcan como tales.

## 1. Búsqueda híbrida (FTS + embeddings), reranking, embeddings multilingües, contextual retrieval y chunking

### Takeaway
Las cifras más sólidas vienen de Contextual Retrieval de Anthropic. Partiendo de una tasa de fallo base de 5,7% (top-20), los embeddings contextuales la bajan 35%, sumar BM25 contextual la baja 49% y agregar reranking la baja 67%. Lo recomendado es recuperar unos 150 candidatos, reranquear y pasar 20 al modelo. Supabase documenta un patrón listo de búsqueda híbrida con RRF en SQL, que encaja directamente sobre el FTS existente.

### Cited Findings
- Contextual Retrieval: con una tasa de fallo base de 5,7% en top-20, los embeddings contextuales la bajan a 3,7% (−35%), los embeddings contextuales más BM25 contextual a 2,9% (−49%), y todo eso más reranking a 1,9% (−67%) — [Anthropic, Contextual Retrieval](https://www.anthropic.com/engineering/contextual-retrieval)
- Pasar los top-20 chunks al modelo rindió mejor que pasar 5 o 10. Para reranking se recuperaron 150 candidatos y se quedaron los 20 mejores. El reranker fue Cohere — [Anthropic](https://www.anthropic.com/engineering/contextual-retrieval)
- Generar los chunks contextualizados cuesta una sola vez unos $1,02 por millón de tokens de documento, usando prompt caching (documento completo en caché y un chunk por llamada). El modelo usado fue Claude 3 Haiku con un prompt que envuelve el documento en `<document>` y el chunk en `<chunk>`, pidiendo "un contexto breve y sucinto para situar este chunk dentro del documento". El ejemplo de costo supone chunks de 800 tokens y documentos de 8k — [Anthropic](https://www.anthropic.com/engineering/contextual-retrieval)
- En esas pruebas los mejores embeddings fueron Gemini (text-004) y Voyage — [Anthropic](https://www.anthropic.com/engineering/contextual-retrieval)
- Patrón de búsqueda híbrida de Supabase: una función SQL `hybrid_search` con dos CTE (FTS con `websearch_to_tsquery` + `ts_rank_cd`, y búsqueda vectorial), unidas con FULL OUTER JOIN y fusionadas con Reciprocal Rank Fusion: score = Σ peso/(rrf_k + rank). Valores por defecto: rrf_k = 50 y pesos full_text_weight / semantic_weight = 1 (ajustables, por ejemplo 2:1 para favorecer palabras clave). Usa un índice GIN sobre el tsvector y un índice HNSW sobre el embedding, cuyo operador debe coincidir con la métrica (`vector_ip_ops` para `<#>`, cosine para `<=>`) — [Supabase Hybrid Search](https://supabase.com/docs/guides/ai/hybrid-search)
- Advertencias de Supabase. La configuración de FTS de la consulta (`websearch_to_tsquery` sin config explícita) debe coincidir con la de indexación; si no, cambian el stemming y las stopwords. Cada lado aporta como máximo 60 candidatos y la función devuelve como máximo 30. El ejemplo de Edge Function usa la service role, que se salta RLS. Para cadenas exactas como códigos de error, la búsqueda solo por palabras clave puede ser mejor — [Supabase](https://supabase.com/docs/guides/ai/hybrid-search)
- Embeddings multilingües: Qwen3-Embedding-8B reporta 70,58 en MMTEB Multilingual (primer lugar según sus autores, por encima de Gemini-Embedding). Es una cifra autorreportada, y la comparación comercial del paper solo incluye Cohere multilingual v3 — [Qwen3 Embedding, arXiv 2506.05176](https://arxiv.org/pdf/2506.05176)
- En un benchmark cross-lingual de terceros (Zilliz, 2026) el orden fue Gemini Embedding 2 (0,997), Qwen3-VL-2B (0,988), Jina v4 (0,985), Voyage Multimodal 3.5 (0,982), OpenAI 3-large (0,967) y Cohere Embed v4 (0,955). Mide inglés-chino, no español — [Zilliz](https://zilliz.com/blog/choose-embedding-model-rag-2026)
- Rerankers: Voyage afirma que rerank-2.5 supera a Cohere Rerank 3.5 en ~7,9% sobre 93 datasets, y que rerank-2.5-lite supera a Qwen3-Reranker-8B en NDCG@10 (cifras del proveedor) — [Vercel AI Gateway, rerank-2.5](https://vercel.com/ai-gateway/models/rerank-2.5/about); [rerank-2.5-lite](https://vercel.com/ai-gateway/models/rerank-2.5-lite/about)
- Un leaderboard comunitario tipo ELO (Agentset, 2026-07) ubica a Cohere Rerank 4 Pro, Voyage 2.5 y Qwen3-Reranker-8B por delante de Cohere Rerank 3.5 y bge-reranker-v2-m3. La metodología no está verificada — [benchmarklist Agentset](https://benchmarklist.com/benchmarks/agentset_reranker_leaderboard/)
- Opciones open-weight: bge-reranker-v2-m3 (568M parámetros, Apache 2.0, multilingüe) y Qwen3-Reranker (Apache 2.0, más de 100 idiomas, contexto de 32k) — [FutureAGI best rerankers 2026](https://futureagi.com/blog/best-rerankers-for-rag-2026/); [Mixpeek](https://www.mixpeek.com/curated-lists/best-rerankers)
- Citas de Claude: cada chunk RAG puesto como documento de texto plano permite citar oraciones individuales. Los documentos "custom content" se citan por índice de bloque, sin re-chunking — [Anthropic Citations](https://platform.claude.com/docs/en/build-with-claude/citations)

### Inferences
- Paso inmediato de bajo riesgo: agregar una columna `embedding` (pgvector) a los ~10k chunks existentes y una función `hybrid_search` RRF adaptada para usar `to_tsvector('spanish_unaccent', …)` en ambos lados. El FTS actual pasa a ser la mitad "BM25" del sistema.
- Códigos de falla (SPN/FMI, DTC P0xxx) y números de parte son tokens exactos. Conviene que el agente los derive a búsqueda léxica pura o con más peso léxico (full_text_weight 2:1), o a una columna normalizada con índice trigram, siguiendo la propia advertencia de Supabase.
- Con ~10k chunks, contextualizar con un modelo chico (Haiku) y caché es barato: unos 10k chunks × 800 tokens ≈ 8M tokens de chunk, más el documento cacheado. El orden de magnitud es de decenas de dólares como máximo. Vale la pena hacerlo antes de embeber, porque Anthropic muestra que el contexto mejora tanto embeddings como BM25.
- Chunking para manuales: un chunk por página o por sección de procedimiento, sin partir tablas de especificaciones (torque, presiones). Cada chunk debe guardar `doc_id`, `page`, modelo de equipo, sistema e idioma como metadatos filtrables. La cita por página exige que el chunk nunca cruce páginas, o que guarde un rango.
- Embedding multilingüe para ES/EN/DE: a falta de un benchmark de español técnico, los candidatos más razonables son Voyage (3.5 / multilingual / multimodal-3.5), Cohere Embed v4, Gemini Embedding o Qwen3-Embedding (open-weight, autohospedable). La decisión debe salir de un eval propio con 50-100 preguntas reales.
- Límite de dimensiones: verificar el máximo que pgvector permite indexar en HNSW y usar `halfvec` o una dimensión reducida (Matryoshka) si el modelo da más de 2000 dimensiones. No lo verifiqué en esta sesión.

### Gaps
- No encontré benchmarks independientes de retrieval en español técnico (manuales automotrices) para embeddings ni para rerankers. Todas las cifras son generales o del proveedor.
- No verifiqué el límite de dimensiones de los índices HNSW de pgvector en Supabase ni el soporte actual de `halfvec`.
- No encontré cifras publicadas de chunking por página vs por sección específicas de manuales técnicos.

## 2. Multimodal: diagramas eléctricos, despieces y páginas escaneadas

### Takeaway
La evidencia indica que embeber la página como imagen (ColPali, DSE, Voyage multimodal, Cohere Embed v4) iguala o supera al OCR+texto en contenido visual: diagramas, tablas y gráficos. El caso más cercano es un set de manuales técnicos evaluado por Snowflake. Lo que rinde más es el híbrido de imagen, palabras clave y reranking de texto. Claude 4.7+ lee imágenes de hasta 2.576 px de lado largo, lo que permite "mostrar la página" al modelo y al mecánico. Hay una limitación importante: Claude no puede citar imágenes de PDFs, así que los escaneos sin texto necesitan OCR para tener citas formales.

### Cited Findings
- ColPali (ICLR 2025) recupera páginas como imágenes con embeddings multi-vector (late interaction) usando un VLM. Supera a los sistemas comparados en el benchmark ViDoRe, con las mayores ganancias en figuras, tablas e infografías. ViDoRe V1 estaba cerca de la saturación y en 2025 salió ViDoRe V2, más difícil — [ColPali arXiv 2407.01449](https://arxiv.org/abs/2407.01449); [ViDoRe V2 arXiv 2505.17166](https://arxiv.org/pdf/2505.17166.pdf)
- Snowflake comparó Voyage Multimodal 3, GME-Qwen2-VL y Nomic-Embed-Multimodal contra OCR+Voyage Multilingual 2 sobre manuales técnicos (27.000 páginas, 143 consultas sobre gráficos y 69 sobre texto), SEC filings y SlideVQA. Resultados: el multimodal gana en manuales con gráficos y en slides (mejor rango de la página correcta y mayor throughput), el texto+OCR gana en documentos de texto limpio con tablas (SEC), y el híbrido (multimodal + keyword + rerank de texto) "mejoró significativamente Recall@5". No publica cifras exactas en el texto — [Snowflake engineering](https://www.snowflake.com/en/engineering-blog/arctic-agentic-rag-multimodal-pdf-retrieval)
- En IRPAPERS (2026), las imágenes de página con Cohere Embed v4 lograron 58% de Recall@1, frente a 52% del texto transcrito con Voyage 3 Large y 46% de un pipeline híbrido de texto. Los embeddings de imagen open-source llegaron a 43% — [IRPAPERS arXiv 2602.17687](https://arxiv.org/html/2602.17687v1)
- DSE (Document Screenshot Embedding): las capturas de página superaron al OCR+texto por más de 15 puntos de nDCG@10 en recuperación de slides — [DSE arXiv 2406.11251](https://arxiv.org/pdf/2406.11251v2.pdf)
- Visión de Claude: el costo es ⌈ancho/28⌉ × ⌈alto/28⌉ tokens visuales. Claude 4.7 y posteriores tienen un tier de alta resolución (lado largo de 2.576 px, hasta 4.784 tokens visuales); el resto, 1.568 px y 1.568 tokens. Ejemplo: 1000×1000 px ≈ 1.296 tokens, unos $5,18 por mil imágenes en Opus 5.5 — [Anthropic Vision](https://platform.claude.com/docs/en/build-with-claude/vision)
- Límites de visión: hasta 600 imágenes por request. Con más de 20 imágenes aplica un tope por imagen más estricto (mantenerlas bajo 3.000 px). El request completo no puede pasar de 128 MB. En conversaciones multi-turno se recomienda la Files API (`file_id`) para no reenviar bytes en base64. También advierte que la compresión JPEG fuerte puede volver ilegible el texto, que las imágenes rotadas o de menos de 200 px se leen mal, y que la localización espacial es aproximada — [Anthropic Vision](https://platform.claude.com/docs/en/build-with-claude/vision)
- Citas sobre PDF: el texto extraído se trocea en oraciones y se cita con `page_location`. Citar imágenes de PDFs no está soportado, y los PDFs escaneados sin texto extraíble no se pueden citar — [Anthropic Citations](https://platform.claude.com/docs/en/build-with-claude/citations)
- OCR, según olmOCR-Bench (Allen AI, 1.403 PDFs, solo inglés): Mistral OCR API logra 72,0 general y 60,6 en tablas, pero apenas 29,3 en escaneos antiguos. PaddleOCR-VL aparece con 80,0 general y 84,1 en tablas según un agregador (no verificado). En OmniDocBench v1.6, según un agregador, Mistral OCR llega a 85,66 y Marker a 78,44 — [olmOCR-bench README](https://huggingface.co/datasets/allenai/olmOCR-bench/blob/eaa828947384ffce68f08c223a0f5f4e2f2df624/README.md); [alphaxiv olmOCR-bench](https://alphaxiv.org/benchmarks/allen-institute-for-ai/olmocr-bench); [codesota OmniDocBench](https://www.codesota.com/browse/computer-vision/document-parsing/omnidocbench)
- Docling, Marker, MinerU y olmOCR-2 (7B) son las librerías open-source habituales en comparativas de 2026 — [Unstract 2026](https://unstract.com/blog/best-opensource-ocr-tools/); [Needl technical note](https://needl.ai/technical-notes/benchmarking-pdf-extraction-tools)

### Inferences
- Arquitectura de dos capas para los escaneados. (a) Pasar OCR (Mistral OCR, o un VLM como Claude Haiku/Sonnet transcribiendo la página a Markdown) para tener texto indexable en FTS y embeddings, y para que haya citas `search_result` con número de página. (b) Guardar el PNG de cada página en Supabase Storage (por ejemplo a 150-200 dpi) y, cuando la respuesta dependa de un diagrama o despiece, adjuntar la imagen de la página al tool_result para que Claude la lea directamente.
- "Que el mecánico vea la página": cada cita debe llevar a un visor (pdf.js con `#page=N`, o el PNG de la página) en la app móvil. El mecánico verifica en el original los valores de torque o pinout en vez de confiar en el texto generado.
- Un pipeline ColPali multi-vector exige almacenamiento y MaxSim que pgvector no resuelve de forma nativa a bajo costo. En Supabase lo pragmático es un embedding single-vector por página (Voyage multimodal-3.5 o Cohere Embed v4) en una tabla `pagina_embedding`, combinado por RRF con los chunks de texto.
- Diagramas eléctricos: el OCR captura códigos de cable y conector, que sirven para la búsqueda léxica, pero no la topología. La topología requiere enviar la imagen al modelo, y como su localización espacial es aproximada (doc de Vision), las respuestas sobre pinout deberían remitir al original y no afirmar valores sin cita textual.

### Gaps
- No encontré benchmarks específicos de diagramas eléctricos o despieces automotrices, ni de OCR en español o alemán técnico (olmOCR-Bench es solo inglés).
- No encontré un head-to-head publicado de voyage-multimodal-3.5 frente a Cohere Embed v4 en manuales técnicos multilingües.
- No verifiqué en esta sesión los límites actuales de la PDF support API de Anthropic (páginas por request, tamaño).

## 3. Patrones de RAG agéntico: reescritura de consultas, multi-hop, citas/grounding y rechazo sin evidencia

### Takeaway
La API de Claude ya trae la herramienta clave para el grounding: los bloques `search_result` devueltos desde un tool_result, con citations activado, producen citas `search_result_location` con fuente, título e índices. El `cited_text` no se cobra como output y los punteros quedan garantizados como válidos. Con esto, "documento + página" pasa a ser estructural y no algo que dependa del prompt. Queda una restricción: las citas son incompatibles con structured outputs.

### Cited Findings
- Los bloques `search_result` (con `source`, `title` y `content` como lista de bloques de texto, más `citations: {enabled: true}`) se pueden devolver desde herramientas propias. Claude los cita como cita resultados web, con `search_result_location` (`source`, `title`, `search_result_index`, `start_block_index`, `end_block_index`, `cited_text`). Todos los search_result de un request deben tener la misma configuración de citations. Si el prompt pide solo JSON, puede haber pocas citas o ninguna — [Anthropic Search results](https://platform.claude.com/docs/en/build-with-claude/search-results)
- Citations: el `cited_text` no cuenta como tokens de output, ni como input cuando se reenvía. Las citas tienen punteros garantizados como válidos. Activarlas sube un poco el input. Funcionan junto con prompt caching y batch. Son incompatibles con structured outputs: combinarlas da error 400 — [Anthropic Citations](https://platform.claude.com/docs/en/build-with-claude/citations)
- Activar o desactivar citations invalida la caché de system y messages, no la de tools — [Anthropic Prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)
- La búsqueda léxica pura puede ser mejor para cadenas exactas como códigos de error — [Supabase](https://supabase.com/docs/guides/ai/hybrid-search)

### Inferences
- `search_chunks` debería devolver cada chunk como `search_result` con `source = "<doc_id>#page=<n>"` (o una URL del visor) y `title = "<nombre manual> — p. <n>"`. Así toda afirmación queda con documento y página verificables en la UI.
- Reescritura de consultas: antes de buscar, normalizar códigos (SPN 520/FMI 3, "P0 299" → "P0299"), expandir sinónimos ES/EN/DE (inyector / injector / Einspritzdüse) y agregar marca y modelo desde el historial del equipo. Esto se puede hacer con un modelo chico (Haiku) o con reglas, y lanzar varias consultas en paralelo (léxica exacta + semántica).
- Multi-hop: dejar que el agente encadene código de falla → procedimiento de diagnóstico → especificación o tabla → diagrama, con un tope de rondas de herramientas.
- Regla de no inventar valores físicos, en tres capas. (1) En el prompt: todo número con unidad (Nm, bar, psi, V, Ω, pin) debe estar respaldado por una cita. (2) Verificación posterior en código: extraer con regex los números con unidad de la respuesta y comprobar que aparecen en el `cited_text` de alguna cita, o en los chunks recuperados. Si no aparecen, marcar o ocultar el valor y mostrar "ver página X". (3) Si no hay evidencia, responder explícitamente "no encontré el valor en los manuales cargados" y ofrecer web search marcada como fuente externa no verificada.
- La incompatibilidad con structured outputs obliga a que la respuesta final al mecánico sea texto con citas, no JSON estricto. Si se necesita estructura (por ejemplo, una lista de pasos), conviene pedirla en Markdown.

### Gaps
- No encontré estudios cuantitativos publicados sobre reescritura de consultas para códigos de falla o números de parte en dominio automotriz.
- No encontré una métrica publicada del efecto de un verificador numérico post-hoc sobre las alucinaciones de valores técnicos.

## 4. Evaluación: eval sets, LLM-as-judge de groundedness, regresión de prompts y modelos

### Takeaway
Lo que hay que hacer, por orden: un golden set con fuentes relevantes etiquetadas, medir retrieval (recall@k / context recall) por separado de la generación (faithfulness), calibrar el juez LLM contra etiquetas humanas, y correr el suite ante cada cambio de prompt, modelo, retriever o chunking. Faithfulness por sí sola engaña si el retrieval falla.

### Cited Findings
- Construir primero un golden set de preguntas con respuesta conocida. Se pueden generar preguntas sintéticas con RAGAS o ARES, pero hay que revisarlas a mano para no inflar los puntajes — [Maxim AI guide](https://www.getmaxim.ai/articles/complete-guide-to-rag-evaluation-metrics-methods-and-best-practices-for-2025/); [Kili](https://kili-technology.com/blog/rag-evaluation-guide-measuring-retrieval-and-generation-as-separate-problems)
- Context recall = chunks necesarios recuperados / total de chunks necesarios. Requiere chunks relevantes etiquetados por humanos — [FutureAGI metrics 2025](https://futureagi.com/blog/rag-evaluation-metrics-2025/)
- Ejemplo de un proveedor: un RAG legal con 0,91 de faithfulness offline pero solo 0,62 de context recall, donde los clientes reportaban leyes omitidas. Una faithfulness alta no detecta un retrieval malo (fuente de proveedor) — [FutureAGI](https://futureagi.com/blog/rag-evaluation-metrics-2025/); [Comet](https://www.comet.com/site/blog/rag-evaluation/)
- Concordancia de jueces LLM con humanos: un proveedor cita 56-72%, comparable a la concordancia entre humanos, en referencia al TREC 2024 RAG Track. No verifiqué la fuente primaria. La recomendación es medir la concordancia de tu propio juez — [PremAI 2026](https://blog.premai.io/rag-evaluation-metrics-frameworks-testing-2026); [Towards Data Science](https://towardsdatascience.com/building-trustworthy-production-rag-systems-through-continuous-evaluation/)
- Costo: 500 preguntas × 5 métricas ≈ 2.500 llamadas al juez por corrida. Se sugiere eval completo en CI sobre el golden set y muestrear 5-10% del tráfico de producción — [PremAI](https://blog.premai.io/rag-evaluation-metrics-frameworks-testing-2026)
- Anthropic usó como métrica de retrieval la tasa de fallo en top-20 (1 − recall@20) — [Anthropic Contextual Retrieval](https://www.anthropic.com/engineering/contextual-retrieval)
- Snowflake midió mRR, Recall@5 y un "answerability score" con LLM-as-judge revisado por humanos — [Snowflake](https://www.snowflake.com/en/engineering-blog/arctic-agentic-rag-multimodal-pdf-retrieval)

### Inferences
- Para el copiloto, el eval existente (memoria: `.copiloto-test/eval.mjs`, 20 preguntas) debería crecer a 100-200 preguntas reales de mecánicos. Cada una con (doc_id, página) esperados, el valor físico esperado si existe, y casos "sin respuesta en corpus" para medir rechazo.
- Métricas mínimas: recall@20 de la página correcta (sin LLM, determinista), un check numérico (¿el valor de la respuesta coincide con el esperado?), faithfulness/groundedness con juez LLM, y tasa de rechazo correcto en preguntas sin evidencia. Usar como juez un modelo distinto o más barato, con rúbrica, y calibrarlo contra unas 50 etiquetas humanas.
- Correr el eval como regresión antes de cada cambio de modelo, prompt, embedding o chunking, y guardar los resultados por versión.

### Gaps
- No verifiqué la fuente primaria del TREC 2024 RAG Track ni la documentación oficial de RAGAS.
- No encontré datasets públicos de QA sobre manuales de taller en español.

## 5. Control de costo y latencia: prompt caching, modelos chicos para retrieval, streaming

### Takeaway
Prompt caching: escribir en caché cuesta 1,25× (TTL 5 min) o 2× (1 h), y leer cuesta 0,1× (0,05× en Opus/Sonnet 5.5). Hay hasta 4 breakpoints, y existe caching automático con un solo campo de nivel superior. Para el agente conviene cachear tools y system (estables) y nunca modificar las definiciones de herramientas por request.

### Cited Findings
- Multiplicadores: escritura 5 min 1,25×, escritura 1 h 2×, lectura 0,1× en la mayoría de los modelos, 0,05× en Opus 5.5 y Sonnet 5.5, y 0,025× en Fable/Mythos 5.1. El mínimo cacheable es 512 tokens en Opus 5.5 / Sonnet 5.5 / Haiku 5.5 y 4.096 en Haiku 4.5. Hay hasta 4 breakpoints `cache_control`, y el caching automático (`cache_control` de nivel superior, con `ttl` opcional de 1h) mueve el breakpoint a medida que crece la conversación — [Anthropic Prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)
- Jerarquía de invalidación tools → system → messages: cambiar las definiciones de herramientas invalida todo; activar o desactivar web search o citations invalida system y messages; agregar o quitar imágenes, o cambiar `tool_choice`, invalida solo messages — [Anthropic Prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)
- Con prompt caching, el costo baja hasta 90% y la latencia más de 2× (contexto de contextual retrieval) — [Anthropic](https://www.anthropic.com/engineering/contextual-retrieval)
- Las imágenes en base64 se reenvían en cada turno, y conviene usar la Files API. Bajar la resolución de las imágenes reduce tokens y latencia, y una imagen de alta resolución puede costar unas 3× más tokens que en el tier estándar — [Anthropic Vision](https://platform.claude.com/docs/en/build-with-claude/vision)
- El ejemplo de Contextual Retrieval usó Claude 3 Haiku (modelo chico) para el paso de contexto de cada chunk — [Anthropic](https://www.anthropic.com/engineering/contextual-retrieval)

### Inferences
- Orden de los bloques: tools (fijo), system (instrucciones + reglas de seguridad, fijo, con cache_control 1h si el tráfico es esporádico), y luego la conversación con caching automático. Mantener fija la configuración de citations y web search para no romper la caché.
- Usar un modelo chico (Haiku) para reescribir consultas, contextualizar chunks en la ingesta, el OCR de VLM y el juez de eval, y el modelo grande solo para la respuesta final o el razonamiento multi-hop. Hacer streaming de la respuesta final al móvil. Enviar las imágenes de página solo cuando se necesiten y reducidas (~1.500 px).
- Indexación offline (OCR, contexto, embeddings): procesar en el PC o en batch y cargar de una vez, en línea con la regla del proyecto de "no topar la base". La Batch API de Anthropic es compatible con citas y caché.

### Gaps
- No consulté los precios por token vigentes de cada modelo, salvo los ejemplos de la doc de Vision ($1/M Haiku 4.5 y $4/M Opus 5.5 de input).
- No medí ni encontré cifras de latencia de reranking en Edge Functions de Supabase (un proveedor menciona 80-150 ms p50 para Cohere Rerank 3.5 — [FutureAGI](https://futureagi.com/blog/evaluating-cohere-rerank-rag-2026/)).

## 6. Voz: speech-to-text en español para talleres ruidosos y UX manos libres

### Takeaway
En los benchmarks disponibles, casi todos de proveedores o terceros comerciales, ElevenLabs Scribe (v2) aparece entre los mejores en español, incluido español latinoamericano conversacional. Deepgram Nova-3 es rápido pero más débil en multilingüe. No hay evidencia sólida sobre gpt-4o-transcribe en español con ruido. No encontré ningún benchmark independiente de ruido de taller.

### Cited Findings
- En el BRIDGE report (conversaciones reales, incluye tres dialectos de español latinoamericano), Scribe v2 tuvo ~8,5% de WER y Nova-3 ~13,7%. El ~47% de OpenAI GPT-4o corresponde al corpus mixto completo — [Humyn Labs BRIDGE](https://humynlabs-bridge-report.pages.dev/)
- En MU-bench de Sierra (llamadas reales en inglés y español), Google Chirp-3 fue el más preciso, mientras Deepgram Nova-3 fue más rápido pero menos preciso en multilingüe. Se probó GPT-4o Mini Transcribe — [Sierra MU-bench](https://sierra.ai/es/blog/mu-bench-an-open-multilingual-transcription-benchmark)
- En habla con alternancia español-inglés (code-switching), Scribe V2 quedó entre los dos mejores en WER y Nova-3 quedó abajo — [Hugging Face / ServiceNow](https://huggingface.co/blog/ServiceNow-AI/code-switching)
- En Multilingual LibriSpeech Spanish (habla leída y limpia), Scribe v2 tuvo ~3,2% de WER — [Gladia benchmarks](https://gladia.io/competitors/benchmarks)
- Cifras de proveedores: ElevenLabs reporta 2,0% de WER para Scribe v1 en FLEURS español (frente a 5,6% de Deepgram Nova 2). Soniox reporta 1,25% frente a 3,24% de OpenAI y afirma que OpenAI sufre con el ruido. Ninguna está verificada de forma independiente — [ElevenLabs](https://elevenlabs.io/nl/speech-to-text/spanish); [Soniox vs OpenAI](https://soniox.com/compare-stt/soniox-vs-openai/spanish); [Soniox benchmarks 2025](https://soniox.com/media/SonioxSTTBenchmarks2025.pdf)

### Inferences
- Los términos técnicos (marcas, códigos SPN/FMI, números de parte, jerga chilena) son el mayor riesgo. Conviene elegir un proveedor que acepte vocabulario personalizado o keyterms, y pasar la transcripción por el LLM para normalizarla antes de buscar. Además, mostrar la transcripción editable antes de enviar.
- UX manos libres: pulsar para hablar (botón grande) en vez de escucha continua por el ruido, confirmación visual de la consulta transcrita, y respuestas cortas leídas en voz alta (TTS) con "ver página X" en pantalla para los valores físicos. Los números críticos nunca deberían darse solo por voz.
- Probar 2-3 proveedores con unas 30 grabaciones reales del taller de Coquimbo (con ruido de compresor y motores) antes de decidir.

### Gaps
- No encontré ningún benchmark de STT con ruido industrial o de taller en español, ni cifras independientes de gpt-4o-transcribe o de Whisper large-v3 en ese contexto.
- No verifiqué el soporte actual de vocabulario personalizado de cada proveedor ni su precio por minuto.
