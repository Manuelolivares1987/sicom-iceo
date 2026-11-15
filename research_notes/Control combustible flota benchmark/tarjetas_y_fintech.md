# Fuel card issuers and fleet fintech/software: fraud controls benchmark (WEX, Corpay/Fuelman, Coast, AtoB, Motive, Geotab, Fleetio, Shell)

Research date: 2026-11-15. Most sources are vendor marketing or vendor help docs; independent verification is scarce and flagged where relevant. Labels used: [DOC] = vendor help/technical documentation or press release describing a shipped feature; [MKT] = marketing claim; [3P] = third-party review/trade press.

## Card-side controls (limits, product, time, geo, PIN/driver ID, odometer, tank capacity, telematics location match, decline vs alert)

### Takeaway
Classic card controls (amount/volume/frequency limits, product category, day/time, merchant/location, driver ID/PIN, odometer prompt) are standard across all issuers. Since 2022-2026 the differentiator is telematics-linked authorization: AtoB (100 m radius + tank capacity, auto-decline opt-in), Coast (GPS Auto Decline), Motive Card (location/fuel-type/fuel-level mismatch), Geotab Fleet Card (Oct 2026, built on AtoB, card locked until driver unlocks at the merchant) and WEX SecureFuel (GA July 2026) all check vehicle position (and sometimes tank level) before approving. Several vendors deliberately start in "alert only" mode before enabling hard declines.

### Cited Findings
**WEX**
- WEX Fleet Card prompts drivers for a unique driver ID before every purchase; transaction won't authorize without it; customer program docs show Driver ID + odometer prompts [DOC/3P] — [WEX resource](https://www.wexinc.com/?p=9331); [Univ. of Missouri WEX program doc (2019, older)](https://www.umsystem.edu/media/fa/procurement/WEX_Fleet_Prgm_doc_02-11-2019.pdf)
- WEX controls: product type, dollar amount, time of day; daily and weekly dollar limits and fuel quantity per day; fraud checklist recommends gallon or dollar caps per transaction and limits on transactions per day/week; "automatic pump shut-offs when limits are exceeded" [DOC/MKT] — [WEX Closed Loop Fleet Card White Paper (2025-09)](https://www.wexinc.com/wp-content/uploads/2025/09/WEX-Closed-Loop-Fleet-Card-White-Paper.pdf); [WEX fraud prevention checklist](https://www.wexinc.com/resource/fraud-prevention-checklist); [WEX buyer's guide gov fleets](https://www.wexinc.com/resource/buyers-guide-fleet-cards-vs-credit-cards-for-government-fleets/)
- WEX Dynamic Prompt (2FA): driver generates a time-sensitive code in a mobile app and enters it at the pump; aimed at skimming/cloned cards [DOC/MKT] — [WEX: fuel card fraud on the rise, 2FA and telematics](https://www.wexinc.com/resource/fuel-card-fraud-is-on-the-rise-how-two-factor-authentication-and-telematics-help-protect-your-trucking-fleet); [WEX skimming/2FA blog](https://www.wexinc.com/resources/blog/keep-your-fleet-cards-secure-from-skimming-with-added-features-including-two-factor-authentication/)
- WEX SecureFuel (press release 2026-07-29, rollout to eligible North American customers from Aug 3, 2026): combines Level-III card data (fuel quantity, fuel type, merchant location) with real-time telematics and WEX AI models to "identify and stop potentially unauthorized fuel purchases before they are approved"; benefits listed: reduce unnecessary declines, confirm purchases using current vehicle location, one workflow for card + telematics, visibility into exceptions and attempted purchases; activated in WEXOnline with WEX-supplied telematics or supported third parties (Geotab Premier Partner); WEX network ~95% of US stations, ~30 M fleet transactions/month; ~a decade of telematics-based fraud prevention in its OTR business [DOC press release; outcomes are MKT] — [WEX SecureFuel press release PDF](https://s25.q4cdn.com/997382257/files/doc_news/WEX-Introduces-SecureFuel-AI-Powered-Fraud-Prevention-for-Commercial-Fleets-2026.pdf); [BusinessWire](https://www.businesswire.com/news/home/20260729382983/en/); [WEX SecureFuel product page](https://www.wexinc.com/products/fuel-cards-fleet/securefuel/)
- WEX OTR telematics workflow (older material): compares truck location with card-use location; if legitimate truck not at site, alerts manager who can disable card; fleets can opt to auto-decline suspicious transactions [MKT] — [WEX 2FA + telematics article](https://www.wexinc.com/resource/fuel-card-fraud-is-on-the-rise-how-two-factor-authentication-and-telematics-help-protect-your-trucking-fleet); [WEX telematics + fuel card combo](https://www.wexinc.com/resource/how-the-telematics-and-fuel-card-combo-beats-fraud/)

**Corpay (ex-Fleetcor) / Fuelman / Corpay One**
- Corpay One fuel card: custom spend limits by driver or vehicle, real-time alerts, per-card on/off toggle, PIN management; integrations with Geotab, Verizon Connect, GPS Insight, Azuga, Fleetio [MKT] — [Corpay One fuel](https://cp.corpayone.com/fuel/)
- Corpay on Geotab Marketplace: limits by merchant type, day of week, time of day; driver ID/PIN validation; GPS-vs-merchant location matching; disclaimer that it "cannot predict or prevent all fraud" and needs a qualifying card + participating telematics partner [DOC/MKT] — [Geotab Marketplace: Corpay](https://marketplace.geotab.com/solutions/corpay/)
- Corpay whitepaper lists GPS-based transaction blocking among today's layered protections (whether Corpay itself hard-declines on GPS in all programs is not specified) [MKT] — [Corpay whitepaper "From Fuel Cards to Fleet Intelligence"](https://www.corpay.com/en-LU/resources/whitepapers/from-fuel-cards-to-fleet-intelligence-what-todays-programs-must-deliver)
- Fuelman: limits by fuel grade, location, day, time of day; driver ID prompts and odometer entry [3P] — [FreightWaves Fuelman review 2026](https://www.freightwaves.com/checkpoint/fuelman-review/)
- Comdata (Corpay brand; 2019, older): odometer prompt is "strictly capture only" while other prompts are validated at POS; day-of-week, time-of-day, transaction-count restrictions [DOC] — [Comdata Understanding Card Fuel Controls (2019)](https://resourcecenter.comdata.com/wp-content/uploads/sites/4/2019/10/Understanding_Card_Fuel_Controls.pdf)

**Coast**
- Limits on total spend or number of purchases; limits by time and day; allow/block specific stations/merchants; spend categories toggled per individual/team; rules per user and per vehicle, combinable [MKT/DOC] — [Coast card controls](https://www.coastpay.com/controls/)
- "Flag transactions when they exceed tank capacity or use the wrong fuel grade" (flag, not decline) [MKT] — [Coast card controls](https://www.coastpay.com/controls/)
- GPS: "Decline payments automatically when the transaction and the company vehicle location do not match"; works with Samsara, Motive, Fleet Complete; odometer auto-captured from telematics (no manual driver input) [MKT] — [Coast card controls](https://www.coastpay.com/controls/); [Samsara KB (Coast integration)](https://kb.samsara.com/hc/articles/4415140452621)
- Live notification for declined/suspicious transactions; manager can authorize legitimate payment in real time from phone; digital receipts, memos, job codes [MKT] — [Coast card controls](https://www.coastpay.com/controls/)
- Fraud protection up to $25,000/year when advanced security features enabled [MKT] — [Coast card controls](https://www.coastpay.com/controls/)

**AtoB**
- Telematics one-pager (created Dec 2022, older): verifies authorized vehicle is within 100 m of merchant for every transaction; outside radius → automatically blocked; real-time tank capacity and level tracking to ensure transactions do not exceed capacity; Suspicious Activity Report auto-collects flagged transactions; SMS/email real-time alerts; transaction blocking is opt-in and fleets "must use the Suspicious Activity Report for a month before turning on transaction blocking"; targets personal vehicles, non-fuel purchases, jerry cans, fueling non-employee vehicles [DOC] — [AtoB Advanced Telematics one-pager (Fleetio app directory)](https://marketing-cdn.fleetio.com/documents/app-directory/AtoB-Advanced-Telematics.pdf)
- Integrations with Motive, Samsara, Azuga [DOC] — [Motive Marketplace: AtoB](https://marketplace.gomotive.com/app/atob); [Azuga AtoB integration](https://fleet-azuga.helpscoutdocs.com/article/1261-atob-integration-with-azuga-setup-benefits-troubleshooting)

**Geotab Fleet Card (built on AtoB, launched Oct 1, 2026)**
- Card stays locked until driver unlocks it in Geotab Drive while vehicle is parked at merchant; declines if vehicle not at fueling location or tank lacks room for the purchase; limits by amount, time frame, location, merchant category; fraud guarantee up to $250,000 (AtoB-provided) for eligible accounts on telematics-verified transactions [3P trade press] — [FreightWaves 2026-10-02](https://www.freightwaves.com/news/geotab-launches-fleet-card-as-diesel-prices-pressure-trucking)

**Motive Card (Dec 2024)**
- AI "Vehicle & Spend Location Mismatch" with auto-decline + instant alert; "Fuel Type Mismatch" and "Fuel Level & Spend Mismatch" alerts; category spend limits by merchant type, time of day, day of week, billing cycle, transaction location; after alert manager can lock card or block merchant; 30-day trial found >$250,000 across >1,200 unauthorized transactions [3P reporting vendor claim] — [FleetOwner 2024-12-09](https://www.fleetowner.com/technology/article/55248008/motive-card-introduces-ai-powered-fraud-controls-to-prevent-fuel-theft)

**Shell Fleet Solutions (US)**
- Purchase controls by product, location, amount, frequency; Level III data (fuel grade, driver ID, time); chip cards; Safer Payments suspicious activity detection; Shell Account Manager Online to shut cards, change PINs, set alerts; DriverDash app with biometric authentication and automatic receipt capture; ClearView analytics "powered by AI from WEX" [3P summarizing Shell, Oct 2025] — [Fleet Maintenance 2025-10-09](https://www.fleetmaintenance.com/in-the-bay/fluids-and-chemicals/article/55322088/shell-fueling-services-shell-releases-fuel-fraud-and-misuse-report-fuel-control-tools)
- Shell Fleet Hub (Europe/Asia/Canada): alerts by email/SMS configurable at account, card-group, or card level, e.g. declined transactions, lower odometer, specific amount or location; block cards instantly [MKT] — [Shell Canada safeguarding your fleet](https://www.shell.ca/en_ca/business-customers/shell-fuel-card/data-and-insights/safeguarding-your-fleet.html); [Shell Singapore security](https://www.shell.com.sg/business/mobility/fleet-solutions/security.html)

### Inferences
- Control maturity ladder visible in market: (1) static limits/prompts at POS → (2) post-transaction exception alerts → (3) telematics match pre-authorization with opt-in hard decline → (4) AI scoring + "unlock at pump" (Geotab/AtoB). An internal tool without card-issuer authorization hooks can only operate at levels 1-2 (or simulate 3 by requiring GPS/photo evidence before dispensing at own tanks).
- AtoB's "one month in report-only mode before blocking" is a useful pattern: calibrate false positives before enforcing.
- Odometer prompts are usually captured but not validated at POS (Comdata explicitly) — validation happens afterward in software; telematics odometer (Coast) removes driver input entirely.
- Tank-capacity rule is the most common volume control; implemented as hard decline only where live fuel level from telematics exists (AtoB/Geotab, Motive alert); otherwise a flag (Coast, Fleetio).

### Gaps
- Exact default/configurable radius and time window for Coast, WEX SecureFuel, Corpay GPS matching not published (AtoB 100 m is from a 2022 one-pager; may have changed).
- No primary documentation found confirming liter/gallon-per-day caps on Fuelman specifically.
- No independent data on false-decline rates of telematics-linked authorization.
- Corpay "DriverDNA" or similar named product: nothing found.

## Software-side controls (anomaly rules, exception workflow, audit trail, driver accountability)

### Takeaway
Fleet software (Fleetio as reference) does post-transaction validation: imported card transactions are checked against tank capacity, vehicle location (vendor-location radius), and meter plausibility (auto-void of odometer jumps). Exception handling is light: flags/icons, filters, email/push notifications, report columns and manual override — not a formal case workflow. Card issuers increasingly embed the exception workflow (AtoB Suspicious Activity Report, Coast real-time approve, Motive lock card/block merchant, WEX "attempted purchases" visibility).

### Cited Findings
- Fleetio Vendor Location Alerts: requires fuel card integration + supporting GPS integration; compares merchant address (from card provider) with vehicle location at time of fuel entry; alert if distance > user-chosen radius (drop-down in Settings > Fuel & Energy); generated when entry is recorded; email/push notifications; icon in Fuel History, filter by "Fuel Entry Alert Type", column in reports; guidance: compare with vehicle Location History, ignore if invalid; no documented resolve/comment workflow [DOC] — [Fleetio help: Vendor Location Alerts](https://fleetio.helpjuice.com/en_US/vendor-location-alerts); [Fleetio developer: fuel entry location](https://developer.fleetio.com/docs/guides/GPS-integrations/fuel-entry-location-introduction)
- Fleetio capacity alert: notification when fuel volume purchased > listed fuel capacity of the asset; capacity auto-imported via VIN decoding [DOC/MKT] — [Fleetio blog: reduce fuel theft with alerts](https://www.fleetio.com/blog/reduce-fuel-theft-with-alerts) (fetch blocked; content from search snippet and [mirror](https://fleetio-www.netlify.app/blog/reduce-fuel-theft-with-alerts))
- Fleetio Fuel Exception Alerts require active fuel + telematics integration; a true/false "generated fuel exception alert" column available in Fuel History, Fuel Entry by Vehicle, Fuel Summary, Fuel Summary by Location reports (update ~6 years old) [DOC, older] — [Fleetio updates](https://updates.fleetio.com/fuel-location-exception-updates-1WUzrG)
- Fleetio Auto Void: algorithm detects and excludes meter-entry anomalies tied to fuel entries from card integrations or imports (example: 15,000-mile jump in one day voided); users can un-void; email notice only for card-integration entries [DOC] — [Fleetio help: Auto Void Fuel Entry](https://help.fleetio.com/en_US/auto-void-fuel-entry)
- Fleetio fuel entry stores fuel type/grade defaulting from vehicle settings (basis for type mismatch checks; no documented mismatch alert found) [DOC] — [Fleetio help: Fuel Entry Overview](https://help.fleetio.com/en_US/fuel-entry-overview)
- Fleetio-Motive integration: every Motive Card fuel transaction auto-imported into Fleetio for cost tracking, budgeting, IFTA [3P] — [Automotive Fleet](https://www.automotive-fleet.com/10246589/fleetio-and-motive-announce-integration-to-improve-fuel-cost-control-and-mainten)
- Shell warning-sign example: purchases > 100 gallons can indicate tank-capacity mismatch; red flags per WEX include purchases outside business hours, non-fuel items, card sharing [3P/MKT] — [Fleet Maintenance (Shell report)](https://www.fleetmaintenance.com/in-the-bay/fluids-and-chemicals/article/55322088/shell-fueling-services-shell-releases-fuel-fraud-and-misuse-report-fuel-control-tools); [WEX fuel card fraud types](https://www.wexinc.com/resource/fuel-card-fraud-understanding-the-types-of-fraud-and-how-to-protect-your-business)
- WEX suggests comparing actual fuel use vs expected mileage (telematics/odometer) to catch anomalies; exception reports highlight transactions outside policy (over limits, unauthorized locations) [MKT] — [WEX fraud prevention: fortify your fleet](https://www.wexinc.com/resource/fraud-prevention-fortify-your-fleet); [WEX smarter fraud detection](https://www.wexinc.com/resource/leveraging-smarter-fraud-detection-for-better-fleet-management/)
- Common alert noise comes from master-data errors (e.g., wrong tank capacity entered at setup) [3P] — [Autosist: what fuel card exceptions reveal](https://autosist.com/blog/what-fuel-card-exceptions-reveal-about-your-fleet/); [Mansfield 2026-06-03: exception reporting](https://mansfield.energy/2026/06/03/whats-that-exception-reporting/)
- Driver accountability: driver ID/PIN per transaction (WEX, Corpay), biometric auth in Shell DriverDash, per-driver + per-vehicle rules (Coast), driver unlock in app at the pump (Geotab) — see sources in section 1.

### Inferences
- Rule set an internal tool should match as baseline: tank capacity exceeded; location mismatch (vehicle GPS vs dispensing point within radius at timestamp); fuel type mismatch; odometer/hourmeter regression or implausible jump (auto-void with override); out-of-hours; frequency (too many fills per day); consumption outliers (L/100km or L/h vs vehicle baseline). Duplicate-fill and MPG-outlier rules are commonly described by third parties but I did not find them documented by Fleetio specifically.
- Market gap: none of the reviewed tools publicly documents a full case workflow (assign → investigate → justify → close with evidence and audit trail). A tool with that would exceed the benchmark on accountability.

### Gaps
- Fleetio's exact list of fuel anomaly rules (MPG outliers, duplicates) not found in official docs.
- Audit-trail specifics (who overrode an alert, when) undocumented for all vendors reviewed.

## Management reports / KPIs surfaced

### Takeaway
Vendors surface spend per vehicle/driver, cost per mile, fuel economy, transaction exception reports, suspicious-activity reports, and savings (discount cents/gallon). Explicit "exception rate" KPIs are rarely public.

### Cited Findings
- Fleetio: fuel card integrations auto-import transactions, compute cost-per-mile, flag invalid odometer; reports Fuel Entry by Vehicle, Fuel Summary, Fuel Summary by Location, with exception column [3P/DOC] — [Fleetio pricing roundup (spotsaas)](https://www.spotsaas.com/blog/fleetio-pricing); [Fleetio updates](https://updates.fleetio.com/fuel-location-exception-updates-1WUzrG)
- WEX: exception reports, transaction summary and detail reports; Level III data; "Actionable Insights" AI recommendations in beta (July 2026) to identify savings and waste [DOC/MKT] — [WEX SecureFuel press release](https://s25.q4cdn.com/997382257/files/doc_news/WEX-Introduces-SecureFuel-AI-Powered-Fraud-Prevention-for-Commercial-Fleets-2026.pdf); [WEX Level III data PDF](https://wexinc.com/wp-content/uploads/2024/06/WEXMF_All-Retail-Partners_1090950-Level-III-data-fleet-managers-fundamental.pdf)
- Shell: ClearView analytics for behavior trends; real-time card activity reports [3P/MKT] — [Fleet Maintenance](https://www.fleetmaintenance.com/in-the-bay/fluids-and-chemicals/article/55322088/shell-fueling-services-shell-releases-fuel-fraud-and-misuse-report-fuel-control-tools)
- AtoB: Suspicious Activity Report; claim vehicle location tracking saved customers avg 11¢/gal [MKT] — [AtoB one-pager](https://marketing-cdn.fleetio.com/documents/app-directory/AtoB-Advanced-Telematics.pdf)
- Geotab: station price variation analytics (419,000 fill-ups, 660 fleets: up to 77¢/gal difference in same town; small fleets choose cheaper station ~17% of the time; est. ~$4,700/truck/yr savings) [3P reporting vendor analysis] — [FreightWaves 2026-10-02](https://www.freightwaves.com/news/geotab-launches-fleet-card-as-diesel-prices-pressure-trucking)

### Inferences
- Suggested KPI set for benchmark: cost/km and L/100km (or L/h) per vehicle; spend per vehicle/driver/site; exceptions per 100 transactions by rule type; % exceptions closed with justification and time-to-close; estimated recovered/avoided liters; price paid vs best available.

### Gaps
- No vendor publishes exception-rate benchmarks (e.g., typical % of transactions flagged).

## Published fraud / misuse statistics

### Takeaway
Most-cited figures: 2-5% of annual fuel spend lost to misuse (Shell 2025), up to 12% (NAFA, cited by WEX 2026), 5-10% of consumption (AssetWorks, cited by WEX). Misuse (internal) ≈ 80% of incidents; external fraud fewer but larger ($60-80k per incident). All are vendor-cited with unclear methodology.

### Cited Findings
- Shell "From Detection to Prevention: Reducing Fuel Fraud & Misuse" (Fleet Trends Survey, Oct 2025): 2-5% of fleet fuel spend lost to misuse/year; 80% of incidents misuse vs 20% fraud; single fraud incident $60,000-$80,000; FBI estimates white-plastic (cloned card) fraud ~$1 B/yr; 58% of fleet managers rank security among top card benefits; sample size not disclosed — [Fleet Maintenance 2025-10-09](https://www.fleetmaintenance.com/in-the-bay/fluids-and-chemicals/article/55322088/shell-fueling-services-shell-releases-fuel-fraud-and-misuse-report-fuel-control-tools); [Automotive Fleet](https://www.automotive-fleet.com/10248517/fuel-fraud-prevention-strategies-reducing-costs-and-risks-for-fleets)
- NAFA (as cited by WEX, July 2026): fraud and misuse can drain as much as 12% of total fuel spend (original NAFA source not located) — [WEX SecureFuel press release](https://s25.q4cdn.com/997382257/files/doc_news/WEX-Introduces-SecureFuel-AI-Powered-Fraud-Prevention-for-Commercial-Fleets-2026.pdf)
- AssetWorks (cited by WEX): 5-10% of annual fuel consumption lost to theft or misallocation — [WEX: how to stop fuel theft](https://www.wexinc.com/resources/blog/how-to-stop-fuel-theft-in-its-tracks/)
- Coast 2024 survey: >40% of respondents report fuel fraud weekly or monthly; avg ~10¢/gal lost to fraud; main threat shifted to internal misuse (search-snippet; page now 404, methodology not verified) — [Coast fuel fraud survey 2024](https://coastpay.com/blog/fuel-fraud-survey-2024)
- WEX-cited driver survey: 44% say other drivers exploit loyalty programs for personal use; 39% say there is intentional misuse of company cards (year/sample unclear) — [WEX: is fleet fraud draining your profits](https://www.wexinc.com/resource/is-fleet-fraud-draining-your-profits)
- Motive Card trial (2024): >$250,000 across >1,200 unauthorized transactions in 30 days (customer base size undisclosed) — [FleetOwner](https://www.fleetowner.com/technology/article/55248008/motive-card-introduces-ai-powered-fraud-controls-to-prevent-fuel-theft)
- Geotab illustration uses an assumed 7% fraud rate (assumption, not measured): ~$2.19 M/yr for a 500-truck fleet spending $31.3 M — [FreightWaves 2026](https://www.freightwaves.com/news/geotab-launches-fleet-card-as-diesel-prices-pressure-trucking)

### Inferences
- A defensible planning range for a benchmark is 2-5% of fuel spend (Shell, most specific), with 10%+ as an upper-bound vendor claim. All figures come from card sellers with an interest in inflating the problem.

### Gaps
- No independent (non-vendor) peer-reviewed or NAFA primary study located; no Latin America/Chile mining-fleet data found.

## Pricing / fees (public)

### Takeaway
Fintech cards charge per card/user per month; legacy issuers (WEX, Corpay, Shell) quote per account. Telematics-linked controls are generally bundled for card customers but require a supported telematics subscription.

### Cited Findings
- AtoB: Unlimited (prepaid) $3/active card/month + $35 setup; Flex (credit) $15/month for first 1-5 cards, +$3/card after; optional Premium $3/account/month; AtoB says pricing varies by account [3P] — [ExpertMarket AtoB review](https://www.expertmarket.com/fleet-cards/atob-fuel-card-review); [FreightWaves AtoB review](https://www.freightwaves.com/checkpoint/atob-fuel-card-review/)
- Coast: $4/active user/month (active = ≥1 completed transaction that month), no setup, no per-gallon/transaction/reporting fees; discounts 3-9¢/gal at partner stations [3P] — [FreightWaves Coast review 2026](https://www.freightwaves.com/checkpoint/coast-card-review/); [ExpertMarket Coast review 2025](https://www.expertmarket.com/?p=44579)
- Fleetio: per vehicle, ~ $4 (Essential, annual) / $7 Professional / $10 Premium per vehicle/month, unlimited users, fuel card + telematics integrations included in paid plans; one source lists different tiers ($3/$5 + free ≤5 vehicles) — conflicting [3P] — [spotsaas Fleetio pricing](https://www.spotsaas.com/blog/fleetio-pricing); [Capterra](https://capterra.com/p/120855/Fleetio/)
- Geotab Fleet Card, WEX SecureFuel, Motive Card fraud controls: no public pricing found; Motive controls only for Motive Card customers — [FreightWaves](https://www.freightwaves.com/news/geotab-launches-fleet-card-as-diesel-prices-pressure-trucking); [FleetOwner](https://www.fleetowner.com/technology/article/55248008/motive-card-introduces-ai-powered-fraud-controls-to-prevent-fuel-theft)

### Inferences
- Software-side fuel exception monitoring is commoditized (~US$4-10/vehicle/month incl. other fleet features), so value of an internal tool lies in fitting own-tank dispensing, hourmeter-based equipment, and faena-specific workflows that card issuers don't cover.

### Gaps
- WEX, Corpay/Fuelman, Shell fee schedules (card fees, late fees, out-of-network fees) not retrieved from primary sources.
- Coverage outside US/Canada (e.g., Chile) not researched; all reviewed telematics-decline features are North America-centric.
