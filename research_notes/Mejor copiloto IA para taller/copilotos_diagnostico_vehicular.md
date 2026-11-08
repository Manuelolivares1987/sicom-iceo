# Commercial AI diagnostic assistants for heavy-truck and vehicle workshops (as of Nov 2026)

Scope note: research done 2026-11-08 with about 17 web searches and fetches. Most sources are vendor press releases and trade press (Heavy Duty Trucking, Fleet Maintenance, Fleet Equipment, Truck Parts & Service). I found no independent benchmarks. Several fetches were blocked (403 on fleetequipmentmag.com), so some items rest on search snippets only. Those are marked.

## 1. Which products lead, and which ones actually exist?

### Takeaway
No single heavy-duty "AI copilot" dominates. The market splits into four groups:
- **Scan-tool and repair-information vendors adding GenAI on top of large repair databases.** TEXA IDC6 has a truck edition and an AI assistant that has been on sale since 2024. Bosch ESI[tronic] adds its AI assistant at the end of 2026; truck coverage is unconfirmed. Snap-on Fast-Track and SureTrack are mostly light-vehicle. Identifix is light-vehicle.
- **Heavy-duty diagnostic software with guided, non-GenAI troubleshooting.** Noregon JPRO, with Repair Mentor and NextStep.
- **Fleet and shop-management platforms adding AI.** Samsara, Fleetio, Fullbay (with Pitstop), Cox Fleet, and Penske in-house.
- **OEM remote diagnostics.** Detroit Connect Virtual Technician, Volvo Remote Diagnostics, and DTNA's GenAI knowledge search for dealers.

"Tokay" could not be verified as a product. "Fullbay AI" does exist: Fullbay Next, "Ask Spike" and Pitstop.

### Cited Findings

**TEXA IDC6 (heavy-duty truck edition exists). The closest match to "AI copilot inside the scan tool" for trucks.**
- TEXA launched the IDC6 AI Diagnostic Assistant in 2024. It "uses vehicle data and repair records to help technicians identify faults and recommends troubleshooting and repair procedures," and TEXA says thousands of repair professionals have used it — [Fleet Maintenance, 26 Oct 2026](https://www.fleetmaintenance.com/shop-operations/ai-and-software/article/55405341/how-ai-is-helping-fleets-reduce-maintenance-costs-and-speed-up-truck-repairs)
- It draws on "more than 30 years of Texa's data—error codes, validated vehicle records, technical service bulletins, and thousands of real-world repair solutions" — [Ratchet+Wrench](https://ratchetandwrench.com/site-placement/latest-news/news/55266179/texa-offering-ai-diagnostic-assistant-in-newest-idc6-platform) (search snippet)
- It has two AI functions. "AI Smart Diagnosis" guides the tech through all diagnostic stages. "Global Search" is a chat interface where mechanics ask questions and get detailed answers. It also suggests the most relevant tool functions based on the vehicle's fault codes, and shows tooltip pop-ups recommending paths — [Brake & Front End review](https://www.brakeandfrontend.com/?p=196516); [j2rauto](https://j2rauto.com/produits/idc6-de-texa-lintelligence-artificielle-au-coeur-du-diagnostic) (search snippets)
- A specific HD product is listed: "IDC6 HD Truck Diagnostics - AI Diagnostic Assist", sold with the Navigator TXT Multihub, an Axone Voice rugged tablet, IDC6 Truck Premium software and a TEX@INFO Truck support subscription — [VehicleServicePros](https://vehicleservicepros.com/directory/tools/scan-tools-and-scan-tool-accessories/product/55277362/texa-usa-idc6-hd-truck-diagnostics-ai-diagnostic-assist)

**Bosch ESI[tronic] AI Assistant (announced; ships with update 2026/4 at the end of 2026).**
- Press release dated 21 July 2026:
  - **Input:** fault codes or short keywords, with "no lengthy questionnaire".
  - **Data:** Bosch diagnostic data, repair instructions and original OEM documents. It can also search other available sources on its own.
  - **Interaction:** a running dialog. The tech can ask new questions, check specific diagnostic steps, or compare alternative fixes at any point in the repair.
  - **Output:** a repair option, a relevant document, or the requested information.
  - **Licensing:** included at no extra charge in the Advanced and Master packages. It builds on Bosch's existing "experience-based repair (EBR)" database of recurring faults.
  - **Recognition:** it won the Automechanika 2026 Innovation Award in "AI Solutions & Digitalisation".
  - **Gaps:** the release gives no performance statistics and no truck-specific statement — [Bosch press release](https://www.bosch-presse.de/pressportal/de/en/efficiently-find-the-right-repair-solution-ai-assistant-optimizes-esitronic-diagnostic-software-from-bosch-283840.html)
- Bosch describes it as a conversational tool "so the technician can systematically test a hypothesis" — [Autosphere, 23 Jul 2026](https://autosphere.ca/mechanical/2026/07/23/bosch-augments-esitronic-diagnostic-platform-with-conversational-ai-assistant/)
- The separate ESI[tronic] Truck and Off-Highway product covers more than 18,000 models from over 600 brands. It is unconfirmed whether the AI assistant runs in the Truck product — [Bosch CV press release](https://www.bosch-presse.de/pressportal/de/en/bosch-strengthens-commercial-vehicle-workshops-with-new-products-and-diagnostic-solutions-283852.html) (search snippet)

**Snap-on Fast-Track Intelligent Diagnostics and SureTrack. Mostly light-vehicle; flagged.**
- **Top Repairs graph:** "most likely parts and procedures used to fix the specific code," weighted by the vehicle's mileage.
- **Real Fixes:** how other techs fixed the same problem, from verified repair records.
- **Smart Data:** a custom PID list per code and vehicle, with automatic thresholds. Any value out of range at idle is flagged red.
- **Delivery:** everything is filtered into one troubleshooting workflow for that vehicle and code, and updated daily over Wi-Fi.
- **Data volume:** "billions of repair records and hundreds of billions of diagnostic sessions".
- **Platforms:** ZEUS, TRITON and APOLLO.
- **Trucks:** not mentioned for this feature — [Snap-on UK](https://www.snapon.com/EN/UK/Diagnostics/News-Centre/latest-news/The-Power-that-Fast-Track-Intelligent-Diagnostics-Brings-You)
- Real Fixes use a "complaint-cause-correction" format, and Snap-on cites "over 40 million Real Fixes developed, reported and validated by real technicians" — [Snap-on SureTrack page](https://www.snapon.com/EN/UK/Diagnostics/Diagnostics/Platforms/SureTrack) (search snippet)

**Identifix Direct-Hit (Solera). Light-vehicle; flagged.**
- In May 2026, Direct-Hit Mobile was upgraded to bundle OEM shop manuals with the confirmed-fix database (over 3 million technician-confirmed fixes) and an AI-assisted, mobile-first search — [Solera blog, 11 May 2026](https://www.solera.com/blog/2026/05/11/identifixs-direct-hit-mobile-brings-oem-repair-manuals-to-the-bay-transforms-how-repairs-get-done/) (search snippet)
- Identifix also runs a hotline staffed by ASE master techs. This comes from a third-party description — [Spotsaas](https://wp.spotsaas.com/?p=19620) (search snippet)

**Noregon JPRO, Repair Mentor and NextStep (heavy-duty leader in multi-brand diagnostics; no confirmed GenAI).**
- NextStep Repair is an interactive repair-procedure guide for all engine makes:
  - removal, inspection and installation steps
  - scalable images and diagrams
  - testing procedures
  - **symptom-based repairs**, chosen from what the driver reports or what was seen at inspection
  - content overseen by ASE master technicians
  - sold as a JPRO add-on or standalone — [Heavy Duty Trucking](https://www.truckinginfo.com/news/noregon-introduces-interactive-step-by-step-repair-system); [Fleet Maintenance](https://fleetmaintenance.com/shop-operations/employees-and-training/product/21150780/noregon-systems-inc-nextstep-repair)
- Repair Mentor "displays all current issues on a vehicle, alerts high-priority issues, and helps users begin a diagnostic process." It points the tech to the right starting screen, for example DPF Regen or the NextStep page — [Truck Parts & Service](https://www.truckpartsandservice.com/technology/article/15825668/new-jpro-update-integrates-repair-mentor-to-guide-technicians) (search snippet)
- JPRO Fault Guidance has a "Most Likely Repair" button for supported engine faults. This comes from a user-written guide, so treat it with caution — [writerscafe guide](https://writerscafe.org/writing/carrepair/2852894) (search snippet)
- The May 2026 JPRO update added the following. The article does not mention AI or give statistics.
  - CAN bus diagnosis, with in-software voltage and resistance measurement
  - Repair Mentor that pinpoints open circuits, disconnected wiring and shorts
  - live data graphing
  - on-screen guided troubleshooting prompts that reduce reliance on a multimeter or a senior tech
  - bidirectional tests for Cummins and Eaton
  - Mack Anthem and Volvo VNL roll call
- Sources: [Fleet Maintenance, 21 May 2026](https://www.fleetmaintenance.com/in-the-bay/diagnostic-and-repair/article/55379175/noregon-systems-inc-noregon-expands-jpro-diagnostics-and-guided-troubleshooting)
- In Noregon's 2025 voice-of-customer survey, 40% said they were interested or very interested in AI for fault triage, and 38% in AI "mentor" functions — [Heavy Duty Trucking / search snippet](https://www.truckinginfo.com/digital-cover-features/how-ai-is-transforming-truck-maintenance)
- Noregon also has a remote tech-assistance service, a human expert help line — [Heavy Duty Trucking](https://www.truckinginfo.com/news/noregon-launches-remote-tech-assistance-service)

**Mitchell 1 TruckSeries (Class 4-8): no GenAI assistant found.**
- 2026 updates were a "Did You Mean" spelling correction in 1Search Plus (March 2026), locating ABS, engine and transmission ID tags, and interactive wiring diagrams. Its diagnostic data is packaged inside Nexiq eTechnician — [Heavy Duty Trucking](https://www.truckinginfo.com/news/mitchell-1-enhances-truckseries-search-capabilities-with-did-you-mean-feature); [HDT wiring](https://www.truckinginfo.com/news/mitchell-1-makes-wiring-diagrams-interactive); [HDT Nexiq](https://www.truckinginfo.com/news/mitchell-1-collaborates-with-nexiq-to-streamline-diagnostic-information-sources-for-truck-technicians)

**Fleet and shop platforms (heavy-duty relevant).**
- **Samsara** (used by Pilot Flying J):
  - **UX:** the tech clicks a fault code for an overview, then asks plain-language questions about its impact and likely time to failure.
  - **Output:** severity, possible future problems, and a **troubleshooting tree** to trace the root cause.
  - **Data:** OEM fault-code databases, Samsara's internal database, and online search.
  - Source: [Heavy Duty Trucking, 1 Feb 2026](https://www.truckinginfo.com/digital-cover-features/how-ai-is-transforming-truck-maintenance)
- **Penske Truck Leasing** (in-house):
  - **Data:** combines repair records, warranty and inspection records, training and knowledge content, and telematics.
  - **What it does:** ML proactive diagnostics and guided repair, **embedded in existing maintenance systems; technicians don't have to write prompts or learn to interact with AI**.
  - Source: [Heavy Duty Trucking, 1 Feb 2026](https://www.truckinginfo.com/digital-cover-features/how-ai-is-transforming-truck-maintenance)
- **Cox Fleet** (repair vendor):
  - **Tools:** a smartphone app where an agentic tool drafts repair estimates. A separate AI analyzes DTCs, suggests root causes, and gives a step-by-step repair plan.
  - **Data:** internal work orders, maintenance history, and the operating conditions when the DTC appeared. It cannot see work done by other vendors.
  - Source: [Fleet Maintenance, 26 Oct 2026](https://www.fleetmaintenance.com/shop-operations/ai-and-software/article/55405341/how-ai-is-helping-fleets-reduce-maintenance-costs-and-speed-up-truck-repairs)
- **Fleetio AI Service Advisor** (open beta March 2026):
  - groups repeated or related fault codes into one issue
  - Smart Assessments for repair orders and Smart Priorities for issues
  - narrative summaries of service and approval history
  - manufacturer-specific fault-code parsing is "soon"
  - Sources: [Fleetio blog](https://www.fleetio.com/blog/introducing-ai-service-advisor); [Fleetio help](https://help.fleetio.com/en_US/service-advisor-overview) (search snippets)
- **Fullbay** (heavy-duty shop software):
  - **Fullbay Next** was unveiled 19-21 May 2026, with "an AI assistant for every major role", a technician "wrench mode", and AI writing tools. Rollout started July 2026 for small shops; shops with 3-19 employees follow in early 2027.
  - **Other AI tools:** "Ask Spike" for shop information, plus transcription and translation for ESL techs.
  - **Mangum:** "Start small."
  - Source: [Fleet Maintenance, 28 May 2026](https://www.fleetmaintenance.com/shop-operations/ai-and-software/article/55379838/fullbay-fullbay-to-release-fullbay-next-shop-platform)
  - Fullbay acquired **Pitstop** (AI predictive maintenance) on 25 March 2026. The model uses more than 10 years of Fullbay repair data from over 5,000 shops — [Heavy Duty Trucking](https://www.truckinginfo.com/news/fullbay-acquires-pitstop-to-strengthen-ai-powered-predictive-maintenance); [Fullbay blog](https://www.fullbay.com/blog/fullbay-acquires-pitstop-ai-predictive-maintenance/)
  - In a Fullbay survey, 19% of commercial shops use AI for diagnostic support today and 61% plan to — [Fullbay blog](https://www.fullbay.com/blog/diesel-goes-digital-reloaded-how-commercial-repair-shops-are-using-ai/) (search snippet)

**OEMs.**
- **DTNA (Freightliner/Detroit):**
  - Detroit Connect Virtual Technician sends remote fault-code diagnostics, service recommendations, and the nearest service location with the right parts in stock — [Heavy Duty Trucking](https://www.truckinginfo.com/news/virtual-technician-joins-detroit-brand-family)
  - DTNA announced **TechAssist**, a voice-controlled app that reads audible step-by-step repair instructions. The article is undated; launch status not verified — [Heavy Duty Trucking](https://www.truckinginfo.com/news/dtna-service-enhancements-to-further-24-hour-downtime-goal) (search snippet)
  - DTNA rolled out a Tavant GenAI warranty system. **Knowledge.AI** lets dealers search vehicle information in natural language, and there is VMRS code prediction from text — [Truck Parts & Service](https://www.truckpartsandservice.com/15677043); [Tavant Knowledge.AI](https://tavant.com/products/knowledge-ai/)
- **Volvo Trucks:** Remote Diagnostics gives proactive diagnostic and repair-planning help to 25,000 trucks in the US and Canada. The article date is unclear — [Fleet Equipment](https://www.fleetequipmentmag.com/volvo-trucks-delivers-25000th-truck-equipped-remote-diagnostics-uptime-support/) (search snippet)
- **Cummins:** shelved a multiyear AI specification-tool project. Leaders say predictive maintenance is already having a measurable service impact — [Transport Topics](https://www.ttnews.com/articles/ai-truck-specification) (search snippet)

**GenAI-native heavy-duty startups.**
- **"AI Diesel Tech"** markets itself as purpose-built for heavy-duty diesel fault diagnosis. It has no hardware interface, no live data and no bidirectional tests — [aidieseltech.com](https://aidieseltech.com/articles/best-ai-tools-for-diesel-technicians) (search snippet; vendor-adjacent, page content could not be fetched)
- **PartsNow.ai "Mike"** identifies heavy-duty parts from the phone camera — [Tennessee Journal of Technology](https://www.tennesseejournaloftechnology.com/agp-article/926365806-partsnow-ai-adds-free-ai-consultant-for-heavy-duty-truck-parts) (search snippet)
- **PartlyRepair AI** (SEMA 2026) is for collision repair. Not relevant — [01net](https://www.01net.it/partly-debuts-partlyrepair-ai-the-agentic-ai-assistant-built-for-collision-repair-shops-at-sema-2026/)

### Inferences
- For a European-brand fleet in Chile (Actros, Volvo, Scania, Renault), the two most relevant commercial references are TEXA IDC6 Truck and Bosch ESI[tronic] (Truck). Both are European, multi-brand and sold in LatAm. The US HD tools (Noregon, Mitchell 1 TruckSeries) are oriented to North American engines and brands (Cummins, Detroit, PACCAR).
- The "AI copilot" is converging into the place where the tech already works: the scan tool (TEXA, Bosch, Snap-on), the CMMS (Samsara, Fleetio, Fullbay), or the existing maintenance system (Penske). A standalone chat is the exception.

### Gaps
- **Not researched; no source collected:** Uptake (ML predictive maintenance), Decisiv, Questar (mentioned only in passing as having an AI repair-recommendation product), Tekmetric (only an unverified review claim), Scania/Volvo/MB workshop tools (XCOM/SDP3, Tech Tool, Xentry), and any GenAI features in them.
- "Tokay" could not be verified as a real product.
- No confirmation that the Bosch AI assistant works in ESI[tronic] Truck.
- Snap-on heavy-duty (commercial vehicle) software: no source found that ties Fast-Track/SureTrack or AI to trucks.

## 2. What makes the best ones good (mechanisms)

### Takeaway
The strong products do not rely on the LLM alone. Each pairs it with structured, proprietary repair data:
- confirmed-fix databases: Snap-on with billions of records, Identifix with over 3 million fixes, TEXA with 30 years of data, Bosch EBR
- fault-code-specific filtering, so the tech sees only the tests, data and documents for this vehicle and this code
- guided step-by-step procedures and component or circuit tests: Noregon, TEXA "Smart Diagnosis"
- direct use of live scan-tool data: Snap-on Smart Data, Noregon CAN tests

GenAI is then layered on as the dialog and search layer: Bosch, TEXA Global Search, Identifix AI search, Samsara.

### Cited Findings
- **Fault code → most likely fix.** Snap-on Top Repairs ranks the most likely parts and procedures for this code and mileage; Real Fixes show what other techs did — [Snap-on UK](https://www.snapon.com/EN/UK/Diagnostics/News-Centre/latest-news/The-Power-that-Fast-Track-Intelligent-Diagnostics-Brings-You). Noregon has a "Most Likely Repair" button for engine faults — [writerscafe](https://writerscafe.org/writing/carrepair/2852894) (unofficial).
- **Experience-based repair.** Bosch's AI sits on top of its EBR database of recurring faults plus OEM data — [Bosch](https://www.bosch-presse.de/pressportal/de/en/efficiently-find-the-right-repair-solution-ai-assistant-optimizes-esitronic-diagnostic-software-from-bosch-283840.html)
- **Live data with automatic thresholds.** Snap-on Smart Data highlights out-of-range PIDs in red — [Snap-on UK](https://www.snapon.com/EN/UK/Diagnostics/News-Centre/latest-news/The-Power-that-Fast-Track-Intelligent-Diagnostics-Brings-You)
- **Guided circuit tests in the tool.** Noregon measures voltage and resistance and locates open circuits and shorts, guided by on-screen prompts — [Fleet Maintenance](https://www.fleetmaintenance.com/in-the-bay/diagnostic-and-repair/article/55379175/noregon-systems-inc-noregon-expands-jpro-diagnostics-and-guided-troubleshooting)
- **Symptom-based entry**, not only DTCs: Noregon NextStep — [HDT](https://www.truckinginfo.com/news/noregon-introduces-interactive-step-by-step-repair-system)
- **Fleet's own history as context.** Cox Fleet uses work orders, maintenance history and the conditions when the DTC appeared — [Fleet Maintenance](https://www.fleetmaintenance.com/shop-operations/ai-and-software/article/55405341/how-ai-is-helping-fleets-reduce-maintenance-costs-and-speed-up-truck-repairs). Penske combines repair, warranty and inspection records, training content and telematics — [HDT](https://www.truckinginfo.com/digital-cover-features/how-ai-is-transforming-truck-maintenance)
- **Fault grouping and prioritization.** Fleetio merges related fault codes into one issue and gives Smart Priorities; Noregon Repair Mentor flags high-priority issues — [Fleetio blog](https://www.fleetio.com/blog/introducing-ai-service-advisor); [TPS](https://www.truckpartsandservice.com/technology/article/15825668/new-jpro-update-integrates-repair-mentor-to-guide-technicians)
- **Freshness.** Snap-on data updates daily — [Snap-on UK](https://www.snapon.com/EN/UK/Diagnostics/News-Centre/latest-news/The-Power-that-Fast-Track-Intelligent-Diagnostics-Brings-You)
- **Human escalation.** Noregon remote tech assistance and the Identifix ASE master tech hotline — [HDT](https://www.truckinginfo.com/news/noregon-launches-remote-tech-assistance-service); [Spotsaas](https://wp.spotsaas.com/?p=19620)

### Inferences
- The defining asset of the leaders is a **closed loop of confirmed fixes**: every completed repair (complaint, cause, correction) feeds back into the database that ranks future fixes. The in-house copilot has a natural equivalent in the fleet system's own work orders and non-conformity (NC) records. Logging, per equipment and code, "what fixed it" in complaint-cause-correction form would create a small, fleet-specific "Real Fixes".
- Bosch and TEXA treat the AI as an entry point into *existing* structured content (the right document, the right test), not as a free-text oracle.

### Gaps
- None of the vendors disclose ranking algorithms, model providers or retrieval architecture.

## 3. How they present answers to technicians (UX)

### Takeaway
The common pattern is context-first, with very little typing:
- the vehicle and fault code are already known
- the tool shows a short ranked list of likely fixes, with confirmed-fix evidence ("what other techs did")
- a guided step or test sequence follows
- the source document or wiring diagram is one tap away
- there is a dialog for follow-up questions

The best-in-class HD example (Penske) explicitly removes the need to write prompts.

### Cited Findings
- **Snap-on:** the **Top Repairs graph** shows parts and procedures by likelihood; **Real Fixes** cards use complaint-cause-correction; everything is filtered to the vehicle and code; red highlighting for out-of-range data — [Snap-on UK](https://www.snapon.com/EN/UK/Diagnostics/News-Centre/latest-news/The-Power-that-Fast-Track-Intelligent-Diagnostics-Brings-You); [Snap-on SureTrack](https://www.snapon.com/EN/UK/Diagnostics/Diagnostics/Platforms/SureTrack)
- **Bosch:** enter a fault code or keywords only, "no lengthy questionnaire"; a running dialog where the tech checks steps or compares alternative fixes; it answers with a repair option or the relevant document — [Bosch](https://www.bosch-presse.de/pressportal/de/en/efficiently-find-the-right-repair-solution-ai-assistant-optimizes-esitronic-diagnostic-software-from-bosch-283840.html)
- **Samsara:** click a fault code to get an overview, then ask plain-language questions; the output includes severity and a troubleshooting tree — [HDT](https://www.truckinginfo.com/digital-cover-features/how-ai-is-transforming-truck-maintenance)
- **TEXA:** tooltip pop-ups recommend the next function or path; functions are suggested from the fault codes; there is also a chat — [Brake & Front End](https://www.brakeandfrontend.com/?p=196516) (snippet)
- **Penske:** "Technicians don't need to write prompts or learn to interact with AI"; results appear inside systems they already use — [HDT](https://www.truckinginfo.com/digital-cover-features/how-ai-is-transforming-truck-maintenance)
- **Noregon Repair Mentor:** shows all current issues, alerts high-priority ones, and jumps to the right starting screen — [TPS](https://www.truckpartsandservice.com/technology/article/15825668/new-jpro-update-integrates-repair-mentor-to-guide-technicians)
- **DTNA TechAssist:** voice-controlled, audible step-by-step instructions, so the tech's hands stay free — [HDT](https://www.truckinginfo.com/news/dtna-service-enhancements-to-further-24-hour-downtime-goal) (snippet)
- **Fullbay:** a technician "wrench mode", voice-to-text clean-up of tech notes, and translation for ESL techs — [Fleet Maintenance](https://www.fleetmaintenance.com/shop-operations/ai-and-software/article/55379838/fullbay-fullbay-to-release-fullbay-next-shop-platform). One shop saved 10 minutes on large service orders with voice-to-text notes — [Fleet Equipment](https://www.fleetequipmentmag.com/fullbay-next-heavy-duty-repair/) (search snippet)
- **PartsNow.ai:** point the phone camera at a part instead of describing it — [TN Journal of Technology](https://www.tennesseejournaloftechnology.com/agp-article/926365806-partsnow-ai-adds-free-ai-consultant-for-heavy-duty-truck-parts) (snippet)
- **Identifix:** a mobile-first search layer that puts OEM manuals in the bay — [Solera](https://www.solera.com/blog/2026/05/11/identifixs-direct-hit-mobile-brings-oem-repair-manuals-to-the-bay-transforms-how-repairs-get-done/) (snippet)

### Inferences (for the in-house "Copiloto Taller")
- An open chat box with low adoption fits the market's lesson: the winners **start from context** (an open work order, the equipment, its active fault code or NC) and **push** a ranked answer, rather than waiting for a typed question.
- Concrete patterns to copy:
  - (a) A "Diagnose" button on the work order or NC that pre-fills the equipment, DTC, symptom and recent history, then shows 3 ranked likely causes, each with "confirmed N times in our fleet" and a link to the manual page or wiring diagram.
  - (b) A complaint-cause-correction capture at OT close, which builds the fleet's own "Real Fixes".
  - (c) A tree of guided checks the tech ticks off (the tool already has "register diagnostic checks").
  - (d) Voice input and voice read-out for hands-busy mechanics, and Spanish voice-to-text to clean up notes.
  - (e) Severity / "can it keep running?" as a first answer (Samsara).
  - (f) One-tap escalation to the jefe de taller, the human hotline equivalent.

### Gaps
- No screenshots or demo videos were reviewed in this pass, so the visual layouts are described only from text.

## 4. Published results (first-time fix rate, diagnostic time)

### Takeaway
Hard, independent numbers are almost nonexistent. The only figures are vendor-reported:
- **Fleetio:** 16% fewer shop hours, or about 2.5 h saved per repair, depending on the source.
- **Fullbay:** one shop saved 10 minutes per large service order with notes AI.
- **Cox Fleet:** approval emails about 5 minutes after the work order.

Bosch, TEXA, Snap-on and Noregon publish no first-time-fix or time-saving statistics for their AI features. Generic "30-60% faster / first-time fix 55% → 85%" claims come from low-quality blogs.

### Cited Findings
- **Fleetio AI Service Advisor:** early results show "assets spending 16% fewer hours in the shop" (self-reported) — [Fleetio press release](https://www.fleetio.com/resources/press/fleetio-launches-ai-service-advisor-to-simplify-and-accelerate-fleet-maintenance-approvals) (snippet). Fleet Maintenance reports that customers averaged 2.5 hours saved per individual repair — [Fleet Maintenance, 26 Oct 2026](https://www.fleetmaintenance.com/shop-operations/ai-and-software/article/55405341/how-ai-is-helping-fleets-reduce-maintenance-costs-and-speed-up-truck-repairs). The two figures are different metrics from different sources, so they do not necessarily conflict, but neither is independently verified.
- **Cox Fleet:** approval emails with PM forms and repair recommendations go out about 5 minutes after the work order is submitted — [Fleet Maintenance](https://www.fleetmaintenance.com/shop-operations/ai-and-software/article/55405341/how-ai-is-helping-fleets-reduce-maintenance-costs-and-speed-up-truck-repairs)
- **Fullbay:** a shop saved 10 minutes on large service orders with AI note clean-up — [Fleet Equipment](https://www.fleetequipmentmag.com/fullbay-next-heavy-duty-repair/) (snippet)
- **Bosch:** no figures on time savings or accuracy — [Bosch](https://www.bosch-presse.de/pressportal/de/en/efficiently-find-the-right-repair-solution-ai-assistant-optimizes-esitronic-diagnostic-software-from-bosch-283840.html). **Snap-on:** no time or success claims — [Snap-on UK](https://www.snapon.com/EN/UK/Diagnostics/News-Centre/latest-news/The-Power-that-Fast-Track-Intelligent-Diagnostics-Brings-You). **HDT AI feature:** no first-time-fix, diagnostic-time or downtime figures from any source — [HDT](https://www.truckinginfo.com/digital-cover-features/how-ai-is-transforming-truck-maintenance)
- **Noregon** context stat: technicians per diagnostic tool fell from about 6 (2016) to 2.5 (2025) — [HDT](https://www.truckinginfo.com/digital-cover-features/how-ai-is-transforming-truck-maintenance)
- **Low-quality claims, cited only to flag them:** 47% diagnostic-time reduction at one shop — [heavyvehicleinspection.com](https://heavyvehicleinspection.com/blog/post/solving-mechanic-shortage-ai-maintenance); "60% or more" — [shopview.com](https://shopview.com/blog/ai-powered-diesel-diagnostics-for-heavy-duty-repair). First-time fix "55-65% → 80-90%" and similar figures come from field-service vendor blogs with no methodology — [technician.dev](https://technician.dev/knowledge/what_is_agentic_ai_first_time_fix_rate_and_how_does_it_affect_field_service_operations.php); [aiventic](https://www.aiventic.ai/blog/ai-powered-diagnostics-benefits-for-field-services)
- **Cautionary note:** Cummins shelved a multiyear AI tool project — [Transport Topics](https://www.ttnews.com/articles/ai-truck-specification) (snippet). Fullbay's advice: "Start small" — [Fleet Maintenance](https://www.fleetmaintenance.com/shop-operations/ai-and-software/article/55379838/fullbay-fullbay-to-release-fullbay-next-shop-platform)

### Inferences
- Because vendors measure **time-in-shop and hours per repair** rather than "queries", the in-house copilot should track outcomes tied to work orders: time from OT open to diagnosis, repeat repairs or comebacks within 30 days, and the share of OTs where the copilot was used. Query count is not a success metric.

### Gaps
- No peer-reviewed or independent heavy-duty study of AI diagnostic assistants was found.
- No OEM (Daimler, Volvo, Cummins) published first-time-fix numbers attributable to AI.
