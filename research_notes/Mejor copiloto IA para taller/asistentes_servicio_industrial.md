# Leading AI assistants for field service and industrial maintenance technicians (late 2026)

Scope note: the research used 17 tool calls (web search and fetch). Nearly all sources are vendor pages, vendor-commissioned case studies or press releases. No independent analyst ranking (Gartner, IDC, Verdantix) was found that names a single "best" technician troubleshooting assistant in 2026. Every metric below is a vendor claim unless marked otherwise.

## Which products exist (verification) and which is considered best for troubleshooting

### Takeaway
Most of the named products exist and are shipping (Komatsu could not be verified). Aquant is the only vendor built *only* for service troubleshooting (history plus expert knowledge), and it has the most published first-time-fix case studies. That makes it the de facto reference for "service intelligence". MaintainX Assist and ServiceMax AI are the closest analogues to an in-house CMMS copilot: an assistant embedded in the work order or asset record, grounded on manuals plus past work orders, with citations.

### Cited Findings
- **Aquant (Service Co-Pilot / generative service intelligence)**: exists. It is a GenAI platform that reads structured and unstructured service records (work orders, machine logs, manuals, free-text notes) plus parts data and tickets, and adds captured expert knowledge — [Aquant capture-critical-knowledge](https://aquant.ai/solutions/capture-critical-knowledge); [Qumra / BusinessWire May 2023 launch](https://qumracapital.com/news/aquants-service-co-pilot-delivers-generative-ai-purpose-built-for-service/)
- Aquant's analyst recognition is modest. CB Insights rated it a "Challenger" (Agent Support Tools), Gartner gave it a mention in a 2024 Emerging Tech GenAI report, and Frost & Sullivan gave it a 2023 Technology Innovation Leadership award. There is no Gartner/IDC/Verdantix "leader" placement — [Aquant news: CB Insights](https://www.aquant.ai/resources/post/aquant-ranked-promising-vendor-agent-support-tools); [Aquant: Gartner 2024 mention](https://www.aquant.ai/resources/post/aquant-featured-2024-gartner-generative-ai-report)
- Aquant customers named: Waters, Beckman Coulter, Makino, Comfort Systems, Powerscreen, Terex Materials Processing, RATIONAL, 3D Systems, Hologic — [Aquant capture knowledge](https://aquant.ai/solutions/capture-critical-knowledge); [casestudies.com RATIONAL](https://www.casestudies.com/company/aquant/case-study/rational-transforms-service-provider-performance-with-aquant)
- **MaintainX Assist (formerly CoPilot)**: exists. The help center now calls it "MaintainX Assist", and the old `/ask-your-asset` help URL 301-redirects to `/maintainx-assist`, which confirms the rename — [MaintainX help: Assist](http://help.getmaintainx.com/maintainx-assist); [MaintainX AI basics](https://help.getmaintainx.com/ai-basics)
- A Pulse 2.0 interview reports that Autodesk's acquisition of MaintainX closed in August 2026. This is a single source and unverified — [Pulse 2.0](https://pulse2.com/maintainx-profile-chris-turlica-interview/)
- **Siemens Industrial Copilot for maintenance**: exists (announced March 2025). It is packaged with Senseye Predictive Maintenance on Azure in an "Entry" package (AI repair guidance and troubleshooting plus basic predictive features) and a "Scale" package — [Manufacturing.net](https://www.manufacturing.net/artificial-intelligence/news/22936898/siemens-expands-industrial-copilot-with-new-generative-aipowered-maintenance-offering); [Automation.com](https://www.automation.com/en-us/products/march-2025/siemens-industrial-copilot-generative-ai)
- **IBM Maximo Assistant / Maximo AI Service**: exists. It requires watsonx.ai and provides an AI assistant, problem-code recommendations, "similar work orders" (embedding model from Watson NLP) and Reliability Strategies recommendations — [IBM docs Maximo AI Service](https://www.ibm.com/docs/SSRHPA_cd/appsuite/admin/c_ctr_ai_integrattion_manage.html); [IBM: Introducing Maximo Assistant](https://www.ibm.com/new/announcements/introducing-maximo-assistant-an-ai-resource-for-teams)
- **Rockwell Fiix MAX**: exists (2026). It is an AI assistant embedded in the Fiix CMMS. GenAI "prescriptive work orders" in Asset Risk Predictor date from April 2024, and integration of the Augury Reliability Agent with Fiix MAX was expected from September 2026 — [Fiix MAX blog](https://fiixsoftware.com/blog/fiix-max/); [iTWire 2024](https://itwire.com/business-it-news/enterprise-solutions/flix-by-rockwell-automation-announces-gen-ai-prescriptive-work-orders.html); [ARC: Rockwell + Augury](https://www.arcweb.com/blog/rockwell-automation-augury-connect-industrial-ai-insights-maintenance-execution)
- **PTC ServiceMax AI**: exists. It includes a Troubleshooting Agent and an Asset Service History Agent, configured in the "ServiceMax AI Console" — [PTC docs AI agents](https://support.ptc.com/help/servicemaxcore/en/articles/ai/ai-agents.html); [PTC ServiceMax AI](https://www.ptc.com/en/products/servicemax/ai-service)
- **Salesforce Agentforce for Field Service**: exists. On-site troubleshooting has been generally available since June 2025, and Pre-Work Brief, voice and job wrap-up are part of Einstein for Field Service — [Field Technologies, Apr 2025](https://www.fieldtechnologiesonline.com/doc/salesforce-brings-agentic-ai-to-the-field-service-sector-tackle-reporting-job-troubleshooting-0001)
- **Microsoft Dynamics 365 Field Service Copilot**: exists. Its main technician feature is the work order and booking "recap" in the mobile app (general availability announced January 2025 in MC991996), with configurable summary data. The Learn page is still titled "(preview)", which is inconsistent — [Microsoft Learn: work order recap](https://learn.microsoft.com/en-us/dynamics365/field-service/work-order-recap); [MC991996](https://mc.merill.net/message/MC991996)
- **Augmentir "Augie"**: exists (relaunched at Hannover Messe 2025). It is a GenAI copilot inside a connected-worker platform that turns SOPs into structured work instructions and does real-time troubleshooting from documents — [IEB Media](https://iebmedia.com/new-products/automation/generative-ai-assistant); [Augmentir product](https://augmentir.com/product)
- **Cat AI Assistant (Caterpillar)**: exists, announced at CES on 6 January 2026. It is a voice, text, image and video assistant over O&M manuals, parts catalogs, purchase history and "experience from millions of assets". The off-board version was planned for Q1 2026 and the in-cab version (NVIDIA Jetson Thor) was in validation — [Caterpillar press release](https://www.caterpillar.com/en/news/corporate-press-releases/h/cat-ai-assistant.html); [Construction Equipment](https://www.constructionequipment.com/industry-news/news/55341835/caterpillar-unveils-cat-ai-assistant)
- **ServiceNow FSM AI and Komatsu dealer AI**: not researched or not found in this pass (see Gaps).

### Inferences
- "Best for troubleshooting" in a defensible sense means Aquant. It is the only one positioned purely on diagnosis quality, it has the most first-time-fix case studies, and its thesis (history alone is not enough, so expert knowledge must be added) is directly relevant. The CMMS and FSM suites (MaintainX, ServiceMax, Salesforce, Dynamics, Maximo, Fiix) treat the assistant as a feature embedded in the work order. Embedding is their main adoption advantage.
- For a small in-house copilot, the architecture to copy is closer to MaintainX Assist and the ServiceMax Troubleshooting Agent (embedded, context-aware, citing past work orders). The *knowledge strategy* to copy is Aquant's (expert capture plus a curated case base).

### Gaps
- No independent head-to-head evaluation or analyst ranking of troubleshooting accuracy was found for any product.
- ServiceNow Field Service AI (Now Assist) was not researched within the tool budget.
- No source was found for a Komatsu dealer or technician GenAI troubleshooting tool. Cat sources do not mention SIS (Service Information System) integration.

## How the leaders ground answers (manuals, historical work orders, tribal knowledge, weighting, contradictions)

### Takeaway
All of them combine manuals with past closed work orders for the same or similar asset, and the better ones show citations to the specific work orders or manual sections. None publicly documents how it weights technician-confirmed fixes against documents, or how it resolves contradictions. The only concrete signal is Aquant's statement that experts add knowledge that history lacks, and that "the best answers are provided by service experts".

### Cited Findings
- MaintainX Assist searches manuals, asset details and maintenance history, parts, purchase orders and comments. It can retrieve information for "any similar asset in your organization". When a manual is attached it uses both the manual and the history; without one it relies on history. Responses include **inline source references** to the manuals, work orders or comments used — [MaintainX Assist help](http://help.getmaintainx.com/maintainx-assist)
- MaintainX Assist uses the entity being viewed (asset, work order, part, purchase order) as context, "so you don't need to restate context" — [MaintainX Assist help](http://help.getmaintainx.com/maintainx-assist)
- MaintainX (July 2026) lets Enterprise customers draw on work summaries and manuals from **identical assets at other MaintainX organizations**, a cross-customer knowledge pool — [MaintainX What's new July 2026](https://webflow.getmaintainx.com/blog/whats-new-at-maintainx-july-2026)
- MaintainX states that answer quality depends on data quality, since incomplete work orders and comments give less useful answers, and tells users to "separate confirmed facts from assumptions" — [MaintainX Assist help](http://help.getmaintainx.com/maintainx-assist); [AI basics](https://help.getmaintainx.com/ai-basics)
- The ServiceMax Troubleshooting Agent retrieves "similar closed Work Orders", matched on problem description, solution and parts used, and returns them with their solutions. It works only on the Work Order object — [PTC: defining AI action troubleshooting](https://support.ptc.com/help/servicemaxcore/en/articles/ai/defining-ai-action-troubleshooting.html)
- The ServiceMax Asset Service History Agent answers questions about past work, problem and solution notes, replaced parts, and technicians for an installed product — [ServiceMax AI intro r24.2](https://supporttest.ptc.com/help/servicemaxcore/r24.2/en/articles/ai/ai-intro.html)
- Aquant calls manuals "typically your cleanest data sources" and the starting point, then adds work orders, video tutorials, technician notes and expert knowledge. It describes a "two-phased modeling approach" combining service data and expert data to "close data gaps", and gives no weights — [Aquant: value of personalized AI](https://www.aquant.ai/resources/post/value-personalized-ai-in-field-service)
- Aquant claims "on average, 30% of correct solutions aren't found in historical service data", which is its justification for expert input. This is a vendor statistic with no methodology published — [Aquant capture knowledge](https://aquant.ai/solutions/capture-critical-knowledge)
- Aquant personalizes responses to the specific asset, part, customer and user, and routes questions by intent to sub-agents (parts suggestion, error-code identification, similar past cases) — [Aquant capture knowledge](https://aquant.ai/solutions/capture-critical-knowledge)
- IBM Maximo finds similar work orders with an embedding model, and Work Order Intelligence proposes failure codes from the work order description **with a description and a confidence level for each option** — [IBM docs](https://www.ibm.com/docs/SSRHPA_cd/appsuite/admin/c_ctr_ai_integrattion_manage.html); [IBM Maximo add-ons](https://www.ibm.com/products/maximo/add-ons)
- Agentforce troubleshooting queries manuals, similar repairs and sensor data plus unstructured previous chats and emails, and can analyze photos to adjust its guidance — [Field Technologies](https://www.fieldtechnologiesonline.com/doc/salesforce-brings-agentic-ai-to-the-field-service-sector-tackle-reporting-job-troubleshooting-0001)
- Fiix prescriptive work orders are generated from "asset data, completed work orders and trusted maintenance sources" — [iTWire](https://itwire.com/business-it-news/enterprise-solutions/flix-by-rockwell-automation-announces-gen-ai-prescriptive-work-orders.html)
- Cat AI Assistant grounds on manuals, parts catalogs, purchase history and fleet-wide asset experience — [Caterpillar](https://www.caterpillar.com/en/news/corporate-press-releases/h/cat-ai-assistant.html)

### Inferences
- The common pattern is to scope retrieval to the asset in context first (same unit, then same model or make, then documents), cite each source, and show similar past work orders explicitly as a list rather than burying them in prose.
- Confidence display (IBM: confidence per suggested code) and "confirmed facts vs assumptions" (MaintainX) are the only visible mechanisms against hallucination or contradiction. An in-house copilot could go further, for example by labelling each claim as manual, past work order confirmed as fixed, or model reasoning, and preferring a work order whose fix was verified (closed without repeat within N days) over manual text when the symptom matches the same unit or model.

### Gaps
- No vendor documents explicit weighting of "technician-confirmed fix" against "manual", or a contradiction-resolution policy. Treat any claim of this as undocumented.
- MaintainX does not state priority when a manual and history conflict.

## Knowledge capture (closed work orders, technician notes, voice, expert curation, feedback loops)

### Takeaway
The leaders capture knowledge at two points. **Closeout**: an AI-drafted summary or post-work report written into the work order, which becomes future retrieval data. **Expert elicitation**: Aquant "datafies" subject-matter-expert knowledge, and IBM recommends missing failure codes on closed work orders. Feedback loops are claimed (Aquant) but never described in detail.

### Cited Findings
- Agentforce drafts a Post-Work Summary at the end of the job from the data the technician collected. The technician refines it with natural-language requests ("the agent changes only what was requested") and it is saved to the work order. iPhone users can trigger it through a Siri shortcut — [Field Technologies](https://www.fieldtechnologiesonline.com/doc/salesforce-brings-agentic-ai-to-the-field-service-sector-tackle-reporting-job-troubleshooting-0001)
- Dynamics 365 Copilot produces work order recaps in the mobile app, and a vendor partner says technicians can update work orders by voice (unverified against Microsoft primary sources) — [Microsoft Learn](https://learn.microsoft.com/en-us/dynamics365/field-service/work-order-recap); [MTC (partner)](https://mtccrm.com/?p=9779)
- MaintainX Assist accepts written or recorded voice prompts (voice notes limited to 2 minutes) and can generate or improve work orders and procedures, always with human review — [MaintainX Assist](http://help.getmaintainx.com/maintainx-assist); [AI basics](https://help.getmaintainx.com/ai-basics)
- MaintainX also has "work order summaries" that it uses as a knowledge source, including cross-organization summaries — [MaintainX July 2026](https://webflow.getmaintainx.com/blog/whats-new-at-maintainx-july-2026)
- IBM Expert Labs offers services that analyze completed work orders and **recommend accurate failure codes**, and that detect duplicate work orders, to clean history for future use — [IBM Expert Labs AI offerings](https://www.ibm.com/new/announcements/introducing-ai-offerings-for-maximo-application-suite-from-ibm-expert-labs)
- Aquant "extracts the tribal knowledge of your subject matter experts and 'datafies' it", converting expert knowledge into synthetic data, and says the approach is "designed to minimize the efforts of subject matter experts" — [Aquant capture knowledge](https://aquant.ai/solutions/capture-critical-knowledge); [Aquant personalized AI](https://www.aquant.ai/resources/post/value-personalized-ai-in-field-service)
- Aquant says Service Co-Pilot "ingests user feedback, so the tool gets even more accurate through continuous use", but the mechanism is not described — [BusinessWire via Qumra](https://qumracapital.com/news/aquants-service-co-pilot-delivers-generative-ai-purpose-built-for-service/)
- Aquant has a Training Agent that builds scenarios from historical cases (symptom, diagnosis, resolution) and quizzes technicians, and a Control Center where supervisors monitor and can intervene — [Aquant capture knowledge](https://aquant.ai/solutions/capture-critical-knowledge)
- Augmentir Augie converts paper or digital SOPs into structured work instructions. Its claim of 76% faster digitization of SOPs is a vendor figure — [IEB Media](https://iebmedia.com/new-products/automation/generative-ai-assistant)

### Inferences
- The highest-leverage capture point is **closeout**: have the AI draft the "problem / cause / fix / parts" summary from what the technician already entered (notes, photos, parts used), and let the technician confirm it with one tap. This creates clean, structured "resolved case" records without asking for extra effort, which is what ServiceMax needs (problem, solution and parts fields) to find similar work orders.
- Expert curation can be lightweight. A workshop chief (for example the jefe de taller) reviews and promotes good cases or marks them "verified fix", which is the Aquant idea scaled down.
- Zero feedback is typical when feedback is a separate, optional thumbs button. Vendors that capture outcome do it implicitly through the work order (solution applied, parts used, repeat visit or not).

### Gaps
- No vendor documents how feedback or ratings actually change ranking or retrieval.
- No published detail on how Aquant interviews or elicits experts (forms, sessions, review of AI drafts).

## Guided troubleshooting (symptom to ranked causes to next test)

### Takeaway
Shipped products offer ranked troubleshooting steps or cause suggestions derived from similar past resolutions (ServiceMax), clarifying questions drawn from past cases (Aquant), and confidence-ranked failure codes (IBM). Fully generated decision trees are not documented by any vendor.

### Cited Findings
- ServiceMax: when the technician opens a work order and enters a problem description, the agent returns similar work orders with their solutions and **suggested troubleshooting steps in priority order, based on successful resolutions in past work orders**. Validated solutions and required parts can be added to the current work order — [PTC docs](https://support.ptc.com/help/servicemaxcore/en/articles/ai/defining-ai-action-troubleshooting.html)
- Aquant suggests **clarifying questions based on past cases** to narrow down to root cause, then gives step-by-step guidance tailored to the asset plus repair history and manuals or schematics. The page does not mention a ranked-cause list explicitly — [Aquant capture knowledge](https://aquant.ai/solutions/capture-critical-knowledge)
- Aquant offers "Intelligent Triage" and "Self-Service Triage", including for end customers — [BusinessWire via Qumra](https://qumracapital.com/news/aquants-service-co-pilot-delivers-generative-ai-purpose-built-for-service/)
- Agentforce guides technicians step by step in a back-and-forth dialogue and adapts using photos — [Field Technologies](https://www.fieldtechnologiesonline.com/doc/salesforce-brings-agentic-ai-to-the-field-service-sector-tackle-reporting-job-troubleshooting-0001)
- IBM: the technician reports damage, the assistant assigns codes, and it summarizes "relevant work history, failure patterns, and suggested repairs" for a supervisor to confirm. Failure codes come with confidence levels — [IBM Maximo Assistant](https://www.ibm.com/new/announcements/introducing-maximo-assistant-an-ai-resource-for-teams); [IBM add-ons](https://www.ibm.com/products/maximo/add-ons)
- Cat AI Assistant guides troubleshooting by voice in the cab and pulls the right manual section — [Caterpillar](https://www.caterpillar.com/en/news/corporate-press-releases/h/cat-ai-assistant.html)

### Inferences
- A practical design for a fleet workshop:
  1. Symptom plus unit.
  2. Retrieve closed work orders on the same unit, then the same model.
  3. Output the top 3 probable causes, each with how often it was the fix and links to the work orders.
  4. Ask one clarifying question or propose the cheapest discriminating test next.
  5. Give manual references for the procedure.

  This mirrors ServiceMax (ranking by past successful resolutions) and Aquant (clarifying questions).

### Gaps
- No vendor documents automatically generated decision trees from history. The claim could not be verified.

## Metrics reported and how vendors drive adoption

### Takeaway
Vendors report first-time fix, repeat visits, parts per job and reactive maintenance time, almost all self-published. Adoption is driven by **embedding** (a button inside the work order or asset screen, context pre-filled), **voice and audio** (Pre-Work Brief, Siri, in-cab "Hey Cat"), and **proactive output** the technician did not ask for (a pre-job brief, similar work orders shown automatically, an auto-drafted closeout). Hard adoption-rate numbers are almost never published.

### Cited Findings
- RATIONAL with Aquant: +21% first-time fix and −34% parts per job over 18 months (vendor case study) — [casestudies.com](https://www.casestudies.com/company/aquant/case-study/rational-transforms-service-provider-performance-with-aquant)
- Comfort Systems with Aquant: +9% first-time fix (vendor) — [Aquant customer story](https://www.aquant.ai/customer-stories/comfort-systems)
- 3D Systems (Aquant with ServiceMax): −62% parts usage, −39% repeat visits (vendor) — [casestudies.com 3D Systems](https://www.casestudies.com/company/aquant/case-study/manufacturing-leader-3d-systems-increases-uptime-drives-improved-service-profitability-with-servicemax-aquant)
- An unnamed Aquant customer went from 35% to 84% first-time fix in 18 months (unnamed, least verifiable) — [Business Reporter](https://www.business-reporter.co.uk/improving-business-performance/how-ai-could-close-the-growing-gap-in-field-service-efficiency)
- Makino reportedly went from 65% to 88% first-time fix in 18 months after changing knowledge capture and sharing. **Junior technicians were initially hesitant, fearing the system was there to evaluate them** (seen only in a search snippet; the full article returned 403) — [CustomerThink](https://customerthink.com/?p=1080461)
- Aquant claims "up to 50% faster resolutions" and improvements "within weeks of go-live", with no baseline given — [Aquant capture knowledge](https://aquant.ai/solutions/capture-critical-knowledge)
- Aquant's 2026 benchmark (self-published, 161 service organizations): average first-time fix 77%, top performers 88%, bottom performers 60%, and up to 26% service cost savings from scaling knowledge — [Aquant 2026 benchmark](https://aquant.ai/resources/post/aquants-2026-field-service-benchmark-companies-can-unlock-up-to-26-in-service-cost-savings-by-scaling-knowledge-across-the-workforce)
- Aquant's 2025 benchmark claims AI enables 39% faster machinery repairs (vendor) — [SalesTechStar](https://salestechstar.com/predictive-ai-artificial-intelligence/aquants-2025-field-service-benchmark-report-reveals-ai-enabling-39-faster-machinery-repairs-and-more/)
- Siemens: pilots cut reactive maintenance time by an average of 25% (pilot result, vendor) — [Manufacturing.net](https://www.manufacturing.net/artificial-intelligence/news/22936898/siemens-expands-industrial-copilot-with-new-generative-aipowered-maintenance-offering)
- Augmentir claims about one-third more productivity on average (vendor) — [IEB Media](https://iebmedia.com/new-products/automation/generative-ai-assistant)
- Powerscreen (Aquant): fewer repeat visits and up to 1 hour saved per technician per day (vendor) — [Aquant capture knowledge](https://aquant.ai/solutions/capture-critical-knowledge)
- Embedding: MaintainX places an "Ask MX Assist" button in the Assets, Parts, Purchase Orders and Work Orders modules on mobile and desktop, and it inherits the current record as context — [MaintainX Assist](http://help.getmaintainx.com/maintainx-assist)
- MaintainX also recommends procedures inside work orders (April 2026) and attaches procedures at work order creation (May 2026) — proactive and unprompted — [MaintainX April 2026](https://help.getmaintainx.com/help-center-updates/april-2026); [May 2026](https://www.getmaintainx.com/blog/whats-new-at-maintainx-may-2026)
- Salesforce: an audio Pre-Work Brief before arrival, voice commands, a Siri shortcut and an auto-drafted post-work summary — [Field Technologies](https://www.fieldtechnologiesonline.com/doc/salesforce-brings-agentic-ai-to-the-field-service-sector-tackle-reporting-job-troubleshooting-0001)
- Dynamics: the Copilot recap appears in the agenda view of the mobile app — [Microsoft Learn](https://learn.microsoft.com/en-au/dynamics365/field-service/enable-work-order-recap)
- Cat: voice-first in the cab ("Hey Cat") — [Equipment World video](https://www.equipmentworld.com/technology/video/15817627/video-caterpillar-demos-incab-ai-voice-assistant-on-excavator)
- Pricing and positioning (brief): Aquant claims a Co-Pilot can launch "in just two weeks". Siemens sells Entry and Scale packages. Maximo requires watsonx.ai. MaintainX cross-organization knowledge is Enterprise-tier only. Public prices were not found — [Aquant](https://www.aquant.ai/resources/post/value-personalized-ai-in-field-service); [Manufacturing.net](https://www.manufacturing.net/artificial-intelligence/news/22936898/siemens-expands-industrial-copilot-with-new-generative-aipowered-maintenance-offering); [IBM docs](https://www.ibm.com/docs/SSRHPA_cd/appsuite/admin/c_ctr_ai_integrattion_manage.html); [MaintainX July 2026](https://webflow.getmaintainx.com/blog/whats-new-at-maintainx-july-2026)

### Inferences
- Low use (about 27 queries a month) with zero feedback matches the "separate chat tab" anti-pattern. The leaders put the assistant where the technician already is: the work order or OT screen. They pre-fill the context (unit, symptom, history) and **push** output without waiting for a question: similar past work orders shown when an OT opens, a pre-job brief, a draft closeout.
- Makino's anecdote suggests messaging matters: position the copilot as help, not surveillance. Do not show per-technician usage rankings at first.
- The metric to track is not query count but first-time fix and repeat work orders on the same unit within N days, plus the share of OTs closed with a structured cause and fix. This is how vendors justify value, and it ties directly to feedback captured implicitly at closeout.

### Gaps
- No vendor publishes technician adoption rates (share of active users, queries per technician).
- No independently audited first-time-fix or MTTR results were found. All figures are vendor-published, and several rely on unnamed customers.
- The full Makino and CustomerThink article could not be fetched (403), so the adoption detail rests on a search snippet.
