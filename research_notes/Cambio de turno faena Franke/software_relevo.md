# Software for shift handover / shift logs (relevo / entrega de turno) in industrial and mining operations, 2024-2026

Scope note: about 15 searches and fetches. Several vendor pages (hexagon.com, the Hexagon product-sheet PDF, the eschbach product page) returned 403/404 to the fetcher, so some j5 and Shiftconnector facts come from search-result excerpts of vendor documentation. They are flagged where that applies. Almost all feature claims are **vendor marketing** unless noted. Independent sources were HSE (UK regulator), Global Mining Review (opinion column), and MIPAC (a mining automation integrator, semi-vendor).

## Which products lead, and which are used in mining

### Takeaway
The enterprise leaders in electronic shift logs and handover come from process industries: Hexagon j5 (oil and gas, LNG, chemicals), eschbach Shiftconnector (now renamed Seqonis; chemicals and pharma), IBM Maximo operator log, IFS shift log, and Innovapptive (SAP/Maximo-centric). Mining fleet and short-interval-control suites (Pitram/Micromine, Wenco, Modular Mining, MineSuite) focus on dispatch and production tracking, and I found no public evidence of a dedicated supervisor-handover module in them. Small crews tend to use generic form or checklist apps (SafetyCulture, Connecteam) with handover templates.

### Cited Findings
**Hexagon j5 (Shift Operations Management: Operations Logbook + Shift Handover + Standing Orders + Action Management)**
- j5 Shift Handover is a digital tool for shift-to-shift communication. The vendor describes "a structured shift handover process with checklists, digital sign-offs and workflows, which can be configured using j5 IndustraForm Templates" (spreadsheet-like template designer). Vendor marketing, seen as a search excerpt. — [Hexagon j5 Operations Logbook](https://hexagon.com/products/j5-operations-logbook); [j5 SOM product sheet](https://bynder.hexagon.com/m/51c130045a97962b/original/Hexagon_PPM_j5_ShiftOperationsManagement_ProductSheet_A4.pdf)
- Product sheet: keeps an audit trail of the team members who received and acknowledged handover items. The connected logbook auto-collects much of the handover content, and reports can be emailed to several recipients. Search excerpt; direct fetch failed. — [j5 SOM product sheet](https://bynder.hexagon.com/m/51c130045a97962b/original/Hexagon_PPM_j5_ShiftOperationsManagement_ProductSheet_A4.pdf)
- j5 docs (v30): shift reports have an approval window in which the handover must take place. If it isn't completed in time, the report is marked "Not Approved" and the next shift report is created automatically. Important logbook entries appear in a handover "sublog" and can be imported into the shift report. Search excerpt of the docs; the page returned 404 on fetch. — [j5 SOM Help v30](https://docs.hexagonppm.com/r/en-US/j5-Shift-Operations-Management-Help/Version-30/1046051); [j5 standard shift report template sections](https://docs.hexagonppm.com/r/en-US/j5-Shift-Operations-Management-Configuration/28.0/1046118)
- The logbook links to j5 Standing Orders, Work Instructions, Event Manager and Action Management. — [Hexagon j5 Operations Logbook](https://hexagon.com/products/j5-operations-logbook)
- Case study: INPEX (LNG and upstream oil and gas) used the j5 logbook and handover modules to standardize data entry and automate reporting. Vendor case study. — [casestudies.com INPEX](https://www.casestudies.com/company/hexagon/case-study/improved-operations-management-at-liquefied-natural-gas-lng-and-upstream-oil-and-gas-company)
- Hexagon also publishes "Ten reasons for web-based logbooks" collateral. — [PPM j5 WebBasedLogbooks TenReasons](https://bynder.hexagon.com/m/443c9b35ec821efc/original/PPM_j5_WebBasedLogbooks_TenReasons_A4.pdf)

**eschbach Shiftconnector, now Seqonis**
- The product was renamed Seqonis ("formerly Shiftconnector"). eschbach says only the name changed, not the vendor, hosting or certifications. — [eschbach Seqonis announcement](https://www.eschbach.com/en/topics/seqonis-announcement.php)
- A digital shift book with electronic signatures, "for example for 'read and understood'", and clearly marked high-priority tasks. Vendor marketing. — [eschbach shiftlog page](https://www.eschbach.com/en/shiftlog/)
- Listings say every verified handover is electronically signed and includes an overview of all new and updated information since the previous shift. It also offers direct shift-team messaging (notes, tasks, directives), compiled views for supervisors, shift scheduling and task planning, and OEE analysis on the stored data. — [Capterra Shiftconnector](https://www.capterra.com/p/179148/Shiftconnector/)
- Customer: Covestro's CTO is quoted saying it is used company-wide to improve shift handovers. Vendor quote. — [get.eschbach.com/shiftconnector](https://get.eschbach.com/shiftconnector)
- Price: "Starting at US$1,000" plus "contact vendor" (unclear whether per month, per site or per licence). From a third-party directory, not verified. — [Capterra](https://www.capterra.com/p/179148/Shiftconnector/); [Krowdbase](https://www.krowdbase.com/software/shiftconnector)

**IBM Maximo (oil and gas operator log), IFS shift log**
- IBM Maximo has an "operator log" with documented shift log handover steps. — [IBM docs: Managing shift log handovers](https://www.ibm.com/docs/en/SS5GME_cd/hse/plusglog/t_prep_shift_handover.html)
- IFS markets a shift log for energy and resources. — [IFS E&R shift log PDF](https://www.ifs.com/-/media10/project/ifs/ifs/assets/p2-assets/ifs-energy-and-resources-shift-log.pdf)

**Innovapptive (connected-worker handover; SAP/Maximo)**, vendor marketing:
- "Swipe-to-Acknowledge" with identity and timestamp, "Carried-Over Issue Flagging", "Out-of-Range Reading Alerts", "Automatic Exception Capture", "Exception Trend Graphs", "Integrated Media Capture", "Voice-to-Text Notes", "Offline Mobile Execution" (RapidSync), "Automated PDF and Email Distribution", "Searchable Shift Report Archive", and write-back to SAP PM / Maximo, where exceptions become notifications or work orders. The page publishes no escalation workflow and no handover KPI figures. — [Innovapptive shift handover software](https://www.innovapptive.com/software/shift-handover-software)

**Mining-specific suites**
- Pitram (Micromine): its Shift Planner splits planned work into small linked tasks, and a short-interval-control panel compares planned and actual start and finish times and progress for the current shift. I found no description of a handover step. — [Mining Magazine: Micromine improves Pitram's Shift Planner](https://miningmagazine.com/operations/news/1344191/micromine-improves-pitrams-shift-planner)
- Groundhog (digital SIC for mining): at shift change, supervisors use SIC to see production against plan and assign tasks, headings and equipment. Vendor. — [Groundhog SIC](https://groundhogapps.com/getting-started-with-a-digital-short-interval-control-system-in-mining/)
- Smaller mining-fleet vendors in 2026 (FleetRabbit, HVI) market handover tools. FleetRabbit offers a carry-forward status board per asset (condition, open defects, pending work orders), safety-critical fields (lockouts, grounded machines) that require a named receiver and digital acknowledgment, and auto summaries. HVI's guide says a handover "is not closed until both signatures are captured" and describes a hot-seat handover at the machine. Vendor blogs. — [FleetRabbit 2026](https://fleetrabbit.com/industry/mining-fleet-software/best-mining-operator-shift-handover-software-2026); [HVI mining shift handover guide](https://heavyvehicleinspection.com/industries/mining/mining-shift-handover-equipment-status-communication)
- iFactory markets mandatory electronic acknowledgment of each safety flag and open action item for Nevada mines. Vendor. — [iFactory Nevada mining shift logbooks](https://ifactoryapp.com/shift-logbook/nevada-mining-shift-logbooks)

**Generic / SME tools**
- SafetyCulture (iAuditor): its public library has many handover templates, including mining ones ("Production Supervisor Shift Handover"). Most are community-made, and SafetyCulture says it has not verified community content. — [SafetyCulture mining handover template](https://safetyculture.com/library/mining/production-supervisor-shift-handover-golding-swc-z6tossysuirq2e86)
- SafetyCulture pricing: Premium about US$24/seat/month annual (about $29 monthly), Enterprise custom. A July 2026 change log reports AI credits bundled into plans. Third-party aggregators, so verify. — [G2 SafetyCulture pricing](https://www.g2.com/products/safetyculture-iauditor/pricing); [PricingSaaS diff 2026W30](https://pricingsaas.com/companies/safetyculture/diffs/2026W30)
- Connecteam: free plan for up to 10 users. Paid plans are per hub; Operations Basic is about US$29/month for up to 30 users billed annually, with Advanced about $49 and Expert about $99. Aggregators disagree slightly. — [Dupple Connecteam pricing](https://dupple.com/pricing/connecteam); [Noon.ai](https://www.noon.ai/blog/articles/431-connecteam-pricing-2026)
- Microsoft Teams Shifts has no dedicated handover object, only shift notes and activities. A Microsoft Q&A answer notes there is no worker confirmation step, so sign-off must happen elsewhere (a channel post or a form). — [Microsoft support: add shifts](https://support.microsoft.com/en-us/office/fill-out-a-schedule-in-shifts-2d58df9b-1c6c-4c84-b0c3-835de7ad13ea); [MS Q&A](https://learn.microsoft.com/en-us/answers/questions/5811654/hello-i-am-looking-into-the-shifts-app-as-a-possib)
- Augmentir: handover marketing is generic (mobile, GenAI assistant, free template), with no documented carry-forward or acknowledgment mechanics. Workerbase markets automatic carry-forward of unresolved tasks and a timestamped log. — [Augmentir](https://www.augmentir.com/?p=14254); [Workerbase Digital Shift Handover](https://www.workerbase.com/en/marketplace/digital-shift-handover)
- Opralog (Infotechnics): appears only in a 2011 SPE presentation as an example of electronic logging. No current mining material found. — [SPE 2011 slides](https://de.slideshare.net/AndyBrazier/2011-spe-electronic-logging-to-improve-safety)

### Inferences
- For a crew of about 8 people per roster (A/B, 7x7), enterprise suites like j5 and Seqonis are oversized and quote-only. Their value is the pattern: template + logbook + carry-forward actions + signed acknowledgment + approval window. SICOM can copy that pattern.
- Mining dispatch and FMS vendors handle the machine and production side (who drives which truck, plan vs actual), while human handover is left to forms. That matches SICOM building its own handover tied to its equipment status board.
- The "Not Approved" state plus an automatically created next report (j5) is a cheap, high-value mechanic: a missed handover becomes visible instead of silently skipped.

### Gaps
- No public detail found for Honeywell (Experion/Forge operator logbook), AspenTech, Mobideo, Nexus/DeepIQ, Fluix, Siemens Opcenter, Wenco, Modular Mining (Cat) or MineSuite handover features. Searches returned nothing specific.
- No public pricing for j5, Seqonis (beyond a $1,000 "starting" directory figure), Innovapptive or IFS.
- No independent (G2 or analyst) head-to-head comparison of handover products found.

## What features define good handover

### Takeaway
The regulator (HSE) defines good handover as face-to-face, two-way, both verbal and written, based on the incoming person's information needs, given enough time, and in three steps: prepare, exchange, cross-check. The software features that turn this into practice are: a structured template; open items carried forward until closed, with an owner; item-level acknowledgment by the incoming person with identity and timestamp; dual sign-off; an approval window that flags missed handovers; photos and evidence; a per-asset status board; mandatory safety-critical fields; offline mobile; a searchable archive; and data-driven improvement.

### Cited Findings
- HSE: handover should be "conducted face-to-face", "two-way, with both participants taking joint responsibility", "done using both verbal and written communication", based on "an analysis of the information needs of incoming staff", and "given as much time and resource as necessary". It describes three phases: outgoing staff prepare, both exchange task information, and incoming staff cross-check when taking over responsibility. — [HSE: Shift handover](https://www.hse.gov.uk/humanfactors/topics/shift-handover.htm)
- HSE singles out risk points such as maintenance that continues across a shift change and periods when safety systems are overridden. — [HSE Core topic 3 PDF](https://www.hse.gov.uk/humanfactors//assets/docs/common3.pdf)
- Energy Institute briefing note: handovers face-to-face where possible, with written procedures setting out the key information and staff trained in the handover process. — [EI Human factors briefing note 10](https://publishing.energyinst.org/topics/process-safety/leadership/human-factors-briefing-note-no.-10-communications)
- Structured logbook design: a structured logbook sets out each key information category the incoming shift must receive, which prompts operators to cover each one. — [Yokogawa blog](https://blog.yokogawa.com/blog/shift-handover-structured-logbook-design)
- MIPAC's five practices: standardize with a checklist; real-time software with an auditable record; training; accountability with clear expectations of what must be communicated; analysis of handover data for continuous improvement. Integrator article, no statistics. — [MIPAC](https://www.mipac.com.au/insights/5-ways-to-improve-your-shift-handover-process/)
- Global Mining Review (Oct 2026, opinion by G. Tsipursky): carried-over issues should use a record with observed evidence (equipment ID, time, value, link to original entry), any AI interpretation clearly labelled, alternatives and unknowns, and a human escalation decision with a named owner. The incoming supervisor should do an independent first read before reading any summary. AI summaries must not replace the verbal handover. Measure more than speed, including whether unresolved exceptions reached the right person. — [Global Mining Review](https://www.globalminingreview.com/mining/26102026/a-mine-shift-handover-needs-more-than-an-ai-summary/)
- Feature set seen across vendors (marketing):
  - Item-level acknowledgment with timestamp ([Innovapptive](https://www.innovapptive.com/software/shift-handover-software); [iFactory](https://ifactoryapp.com/shift-logbook/nevada-mining-shift-logbooks))
  - "Read and understood" e-signature ([eschbach](https://www.eschbach.com/en/shiftlog/))
  - Acknowledgment audit trail ([j5 sheet](https://bynder.hexagon.com/m/51c130045a97962b/original/Hexagon_PPM_j5_ShiftOperationsManagement_ProductSheet_A4.pdf))
  - Carry-forward until formally closed ([Kissflow pending-action app](https://kissflow.com/appstore/shift-handover-pending-action-tracking); [Workerbase](https://www.workerbase.com/en/marketplace/digital-shift-handover))
  - Supervisor approval of the logbook ([Kissflow logbook with approval](https://kissflow.com/appstore/shift-logbook-with-approval))
  - Completion-rate and open-item dashboards ([Evotix](https://evotix.com/solutions/safety/shift-handover-management-software))
  - Offline, photos, voice-to-text, PDF and email distribution ([Innovapptive](https://www.innovapptive.com/software/shift-handover-software))
  - Per-asset status board and safety-critical items with a named receiver ([FleetRabbit](https://fleetrabbit.com/industry/mining-fleet-software/best-mining-operator-shift-handover-software-2026))
  - Dual signature ([HVI](https://heavyvehicleinspection.com/industries/mining/mining-shift-handover-equipment-status-communication))
- Symestic warns that digitizing without redesigning the process reproduces the same gaps, and recommends two-way confirmation rather than one-way transmission. — [Symestic: digital shift log](https://www.symestic.com/en-us/what-is/digital-shift-log)

### Inferences
Minimum feature set for SICOM Franke, ranked by value for cost:
1. A fixed template per role (supervisor, mechanic, driver) with mandatory sections: safety and incidents, equipment status by truck, fuel and stock, pending items, client requests.
2. Pending items as records (not free text), each with an owner, due date and priority, carried into every following handover until closed.
3. Item-level acknowledgment by the incoming supervisor, with user and time, and dual sign-off to close the handover.
4. An approval window: if the handover is unsigned by T+X hours, mark it "Not acknowledged" and escalate to the operations head.
5. A "verbal handover done" checkbox, to keep face-to-face handover per HSE.
6. Photos per item, an offline PWA, and a searchable history.
7. KPIs: percentage of handovers signed on time, pending items aged more than N shifts, and items reopened.

The 7x7 roster means the handover between A and B happens once a week, after a 7-day gap. That makes carry-forward and the status board more important than a daily chat, because the incoming supervisor has been away for 7 days. This is an inference; no source addresses 7x7 specifically.

### Gaps
- No independent, quantified study found on the effect of electronic handover on incidents or KPIs. FleetRabbit's "40% of incidents tied to handover" and "20-40% performance drop" figures are unsourced vendor claims and should not be used.
- No vendor publishes a standard "handover quality KPI" definition. The KPIs above are inferred.

## How products address communication failures between supervisors (missed information, no accountability)

### Takeaway
Products tackle missed information with structure (a template prompts every category, and logbook entries flow into the report automatically) and with persistence (open items survive until closed). They tackle accountability with identity-stamped acknowledgment, e-signatures, audit trails and approval windows. Escalation of unacknowledged items is marketed by some vendors but rarely documented in detail.

### Cited Findings
- Failure of information transfer at shift handover was one of the factors in Piper Alpha (Cullen Report). A communication failure between shifts led to the 1983 Sellafield discharge to sea. — [HSE: Shift handover](https://www.hse.gov.uk/humanfactors/topics/shift-handover.htm)
- MIPAC: in many operations, handover is left to individual teams or managers, so there is little standardization. — [MIPAC](https://www.mipac.com.au/insights/5-ways-to-improve-your-shift-handover-process/)
- Mechanisms by product:
  - j5 records who received and acknowledged each item and creates a "Not Approved" state if the handover window is missed ([j5 sheet](https://bynder.hexagon.com/m/51c130045a97962b/original/Hexagon_PPM_j5_ShiftOperationsManagement_ProductSheet_A4.pdf); [j5 docs](https://docs.hexagonppm.com/r/en-US/j5-Shift-Operations-Management-Help/Version-30/1046051)).
  - eschbach uses "read and understood" e-signatures and an overview of what is new or updated since the last shift ([eschbach](https://www.eschbach.com/en/shiftlog/); [Capterra](https://www.capterra.com/p/179148/Shiftconnector/)).
  - Innovapptive turns open exceptions into tracked work orders in SAP or Maximo, so they don't live only in the log ([Innovapptive](https://www.innovapptive.com/software/shift-handover-software)).
  - Some tools escalate items that stay unresolved past a set window to a supervisor. This is configurable and not universal ([Kissflow](https://kissflow.com/appstore/shift-handover-pending-action-tracking)).
- Global Mining Review recommends named owners for observations, escalation decisions and corrections, and checking that unresolved exceptions "reach the right person". — [Global Mining Review](https://www.globalminingreview.com/mining/26102026/a-mine-shift-handover-needs-more-than-an-ai-summary/)

### Inferences
- The accountability gap SICOM must close is less about "a log exists" and more about "the incoming supervisor provably accepted each open item, and an unaccepted item escalates." So SICOM needs acknowledgment per item plus an escalation timer, as well as a document-level signature.
- Linking pending items to existing SICOM objects (non-conformities, work orders, fuel records) mirrors Innovapptive's write-back and avoids a separate list that dies.

### Gaps
- No vendor documentation found that details escalation rules (timers, recipients) for unacknowledged handover items. Escalation logic will need to be designed in-house.

## Pricing where public

### Takeaway
Only SME tools publish prices: SafetyCulture about US$24/seat/month; Connecteam free up to 10 users and about US$29/month per hub up to 30 users. Enterprise handover suites (j5, Seqonis, Innovapptive, IFS, Honeywell, AspenTech) are quote-only. The only figure seen is a third-party "from US$1,000" listing for Shiftconnector.

### Cited Findings
- SafetyCulture Premium about $24/seat/month (annual) or $29 (monthly); Enterprise custom. — [G2](https://www.g2.com/products/safetyculture-iauditor/pricing)
- Connecteam free for up to 10 users; Operations hub Basic $29, Advanced $49, Expert $99 per month (annual billing), about $35, $59 and $119 monthly; extra users beyond 30 about $0.80-1.00 each. — [Dupple](https://dupple.com/pricing/connecteam); [Noon.ai](https://www.noon.ai/blog/articles/431-connecteam-pricing-2026); [Shifton](https://shifton.com/blog/connecteam-alternatives/)
- Shiftconnector "Starting price US$1,000, contact eschbach". — [Capterra](https://www.capterra.com/p/179148/Shiftconnector/)

### Inferences
- For about 10-16 Franke users, a generic tool would cost US$0-400/month, but it wouldn't integrate with SICOM's equipment, fuel and work-order data. Building in SICOM is justified if it reuses those records.

### Gaps
- No public pricing for j5, Seqonis (current), Innovapptive, IFS, Honeywell, AspenTech, Mobideo, Pitram, Wenco or Modular Mining.
