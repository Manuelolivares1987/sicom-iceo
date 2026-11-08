# MaintainX: preventive maintenance, meters, parts/inventory and purchasing (benchmark for SICOM)

Research date: 2026-11-08. Main source: MaintainX Help Center (help.getmaintainx.com), read live; the pages carry "Copyright © 2026" but give no per-article update dates. Marketing and blog pages are flagged where used. Snippets from the older Intercom help center (intercom.help/maintainx) may be outdated.

## 1. PM triggers: calendar, meter, whichever-first, fixed vs floating, forecasting, missed PMs, compliance

### Takeaway
PM in MaintainX is built on **Maintenance Plans**, not on recurring work orders. A plan is a planning layer that generates *non-recurring* WOs of Work Type "Preventive" ahead of time, up to a **scheduling horizon**. You choose fixed ("based on original schedule") or floating ("based on last completion"). Time, usage, or "Time or Usage, whichever first" is supported, but **whichever-first is only allowed in floating mode**. "Nested PM" covers ladders such as A/B/C/D services, and a safety cap stops runaway generation when a meter jumps.

### Cited Findings
- A Maintenance Plan "sets recurrence rules for PM tasks and controls when work orders are generated". "Work orders generated from maintenance plans are non-recurring" and get Work Type = Preventive. Planners can change or skip one upcoming WO without touching the rest of the series. — [About Maintenance Plans](https://help.getmaintainx.com/about-maintenance-plans)
- **Schedule Behavior** has two options. "Based on original schedule" (fixed) keeps milestones on the original schedule whenever the WO is completed. "Based on last completion" (floating) calculates each new milestone from the previous WO's completion date. — [Create a Maintenance Plan](https://help.getmaintainx.com/create-a-maintenance-plan)
- **Schedule Type** is Time based, Usage based (meter readings), or "Time or Usage based", which creates WOs "by whichever comes first". The third option is **only available with "Based on last completion"**. — [Create a Maintenance Plan](https://help.getmaintainx.com/create-a-maintenance-plan)
- Under fixed intervals several WOs can be open at once. Floating intervals restart from the completion date **or meter reading** of the last completed WO. — [About Maintenance Plans](https://help.getmaintainx.com/about-maintenance-plans)
- Time trigger fields:
  - Recurrence.
  - "Work Order start date" is an offset before the due date (for example, 3 days = start 3 days before due).
  - "First work order due date" is "the anchor point for the maintenance plan".
  - Scheduling Horizon.
  - Source: [Create a Maintenance Plan](https://help.getmaintainx.com/create-a-maintenance-plan)
- Usage trigger fields:
  - Meter, Condition, Value (the interval).
  - **"Next due meter reading"** can be changed after setup. Their example: the asset is at 1,300 h and the next due is set to 1,500 h instead of being calculated from the current reading.
  - **"Create Work Order ahead by"**: lead time in meter units, so the WO is created before the threshold.
  - Start and Due timing relative to creation.
  - Source: [Create a Maintenance Plan](https://help.getmaintainx.com/create-a-maintenance-plan)
- **Scheduling horizon** sets how far ahead WOs are created, in days or weeks. A weekly plan with a 4-week horizon creates 5 WOs. No maximum is stated. Generation can take "a few minutes" for long horizons. — [Create a Maintenance Plan](https://help.getmaintainx.com/create-a-maintenance-plan)
- Future WOs are generated from projected due dates "regardless of whether earlier work orders are open, overdue, skipped, or canceled". — [About Maintenance Plans](https://help.getmaintainx.com/about-maintenance-plans)
- **Nested PM ("Add work at longer frequencies")**: one plan holds up to **10 templates** (the base plus 9 nested). "Run every" goes up to 100 WOs per template. A "Current maintenance state" label (A–E in their example) sets which step of the ladder the asset is on now. Their example is monthly inspections with extra tasks at 3, 6, 9 and 12 months. The docs do not say what wins when nested tasks fall on the same date. — [Create a Maintenance Plan](https://help.getmaintainx.com/create-a-maintenance-plan); [About Maintenance Plans](https://help.getmaintainx.com/about-maintenance-plans)
- **Safety cap for meter jumps**: a fixed usage-based plan generates at most **5 WOs per evaluation**. Older milestones beyond that are skipped, and the affected WOs show an **"unusual meter activity" banner**. — [Create a Maintenance Plan](https://help.getmaintainx.com/create-a-maintenance-plan)
- "Copy to new plan" duplicates a plan. Edits to one generated WO do not affect the series. — [Create a Maintenance Plan](https://help.getmaintainx.com/create-a-maintenance-plan)
- Maintenance Plans availability: **web only** (cannot be created on mobile), Premium and Enterprise plans, Full User and Admin. Custom roles can grant maintenance-plan permissions. — [Create a Maintenance Plan](https://help.getmaintainx.com/create-a-maintenance-plan); [About Maintenance Plans](https://help.getmaintainx.com/about-maintenance-plans)
- Older/simple mechanism: WO-level **Recurrence**. Options are Daily; Weekly (N weeks plus weekdays); Monthly by date or by weekday (for example, last Tuesday); Yearly; "Periodically" (minutes). A WO needs a due date before it can recur. Sub-WOs follow the parent's recurrence. This page has no meter or completion-based options. — [Set Work Order Recurrence](https://help.getmaintainx.com/set-work-order-recurrence)
- In older community posts users asked for "next due dates based on last completion" for recurring WOs, and noted that weekday settings don't apply to meter-triggered WOs. This was before Maintenance Plans existed; the floating option now covers the first request. The posts are undated in the search results. — [Community feature request](https://community.getmaintainx.com/product-q-a-6/feature-request-275); [Community post 414](https://community.getmaintainx.com/product-q-a-6/day-of-week-condition-for-automation-work-orders-414)
- **PM compliance** as defined by MaintainX = on-time PMs ÷ scheduled PMs. Reports cited: "On time vs. overdue" (split into Reactive vs Repeating WOs) and "Created vs. Completed". These sources are blog and marketing pages, not help docs. — [MaintainX blog: PM compliance](https://www.getmaintainx.com/blog/preventive-maintenance-pm-compliance); [6 CMMS reports](https://www.getmaintainx.com/blog/6-cmms-reports-to-help-you-run-leaner-maintenance)
- Benchmarks MaintainX cites: 90% schedule compliance is "world class" (learning center, Apr 2026). The blog cites Reliable Plant: PM schedule compliance 100%, planned work above 90%. — [Schedule compliance](https://getmaintainx.com/learning-center/schedule-compliance); [PM compliance blog](https://www.getmaintainx.com/blog/preventive-maintenance-pm-compliance)
- MaintainX's own guide recommends a calendar backstop on meter triggers, for example a runtime trigger plus a 90-day PM. — [Meter-based maintenance best practices](https://getmaintainx.com/blog/meter-based-maintenance-best-practices)

### Inferences
- Ideas SICOM could copy:
  - (a) An explicit **"Next due reading" field you can override**. This handles re-baselining after a certificate or an out-of-system service, a pain SICOM already handles through MIG640/645/646.
  - (b) **"Create WO ahead by X hours"**, a lead time in meter units, separate from the date offset.
  - (c) **Pre-generated future WOs up to a horizon**, which gives a forecast calendar for free.
  - (d) A **cap on WOs per evaluation plus an "unusual meter activity" flag** when a GPS hour meter jumps.
  - (e) **Nested templates with a "current maintenance state" pointer**, the same concept as SICOM's 300h/400h ladder with "absorption".
- Notable restriction: MaintainX forces whichever-first to be floating. In fixed mode, mixing calendar and meter anchors makes the next due ambiguous. SICOM's hours/date whichever-first should state which anchor it resets from.
- Weaknesses where SICOM may be ahead:
  - Projected dates for meter-based PMs (an average-usage forecast) are not documented.
  - Overdue escalation is not documented.
  - Fixed plans keep generating even when earlier WOs are overdue, which can pile up open PMs.

### Gaps
- Whether meter-based PMs get a projected calendar date from average daily usage, and whether a forecast or calendar view of plans exists. Neither is in the help articles reviewed.
- What wins when nested templates coincide (does the 12-month service suppress the monthly?).
- Any built-in PM compliance KPI screen inside the product. Only blog descriptions were found.
- The release date of Maintenance Plans. It is not stated; it appears to be a 2024–2026 feature that replaced WO recurrence for PM, but this is unconfirmed.

## 2. Meters: manual vs automatic, validation, alerts

### Takeaway
Meters can be manual, **automated** (REST API, sensors via an OT Data Connector, telematics integrations) or legacy IoT. Triggers are defined as conditions on readings. Validation is AI anomaly detection, not hard rules. No documented rollback or decreasing-reading rule was found. Telematics (Samsara/Motive) sync engine hours and odometer **daily**, and these integrations are Enterprise-only.

### Cited Findings
- Meter types:
  - **Manual**: entered by a technician.
  - **Automated** (web): readings arrive via the REST API or an integrated source such as a sensor through an **OT Data Connector**. Setup is done with a MaintainX rep.
  - **IoT**: "replaced by automated meters".
  - **Monitoring points** group several automated meters from the same physical point on an asset.
  - Meters are on Premium and Enterprise only.
  - Source: [About Meters](https://help.getmaintainx.com/about-meters)
- Meter trigger conditions:
  - is above / is below / is equal to.
  - **increases by** ("every time the meter reading increases by the set value", with a configurable first trigger point).
  - decreases by.
  - **increases/decreases by (from last reading)**: the delta between the last two readings, which works as a jump detector.
  - Source: [Trigger a WO from a Meter](https://help.getmaintainx.com/trigger-a-work-order-from-a-meter)
- **The web app no longer lets you create new meter triggers.** New triggers are only possible on mobile; the web app shows existing trigger history and recommends **Workflow Automations** instead. In other words, PM by usage has moved to Maintenance Plans and alerts to Automations. — [Trigger a WO from a Meter](https://help.getmaintainx.com/trigger-a-work-order-from-a-meter)
- Recording a reading: web "+ Record Reading" → "New Meter Value" → Submit; mobile More > Meters. The meter shows Last Reading, a Reading History ("See All Readings") and a graph over a time frame. — [Record a Meter Reading](https://help.getmaintainx.com/record-a-meter-reading)
- Meter statuses: **Pending** (no reading yet), **Stable** (last reading within an acceptable range of the trigger, no WO created), **Triggered** (the last reading created a WO). — [Record a Meter Reading](https://help.getmaintainx.com/record-a-meter-reading)
- **AI anomaly detection** applies to manual meter readings and numeric procedure fields.
  - When a value looks off, the app shows a message comparing the entered value with the expected value.
  - The user can confirm it as an anomaly; it is then logged in the meter's reading history.
  - The feature is enabled in Work Order settings > Procedures, on the web.
  - For procedure fields, it needs at least 3 prior WOs containing that field.
  - Older blog posts say it is Enterprise-only; current tiers are unverified.
  - Sources: [Anomaly detection](https://help.getmaintainx.com/anomaly-detection); [AI basics](https://help.getmaintainx.com/ai-basics); [Record a Meter Reading](https://help.getmaintainx.com/record-a-meter-reading)
- **Samsara integration**:
  - Engine hours and odometer sync into MaintainX Meters **daily**; DVIRs, fault codes and GPS/geofence events sync in real time.
  - WOs can be created from DVIRs, geofence entry/exit, fault codes, mileage thresholds and engine hours.
  - Requires Enterprise.
  - Source: [MaintainX–Samsara](https://www.getmaintainx.com/integrations/samsara); [Samsara marketplace](https://www.samsara.com/resources/marketplace/maintainx)
- The Motive integration syncs mileage and engine hours into meters. FuelCloud updates meters with hours or miles from fuel transactions. — [Motive integration](https://webflow.getmaintainx.com/integrations/motive); [FuelCloud integration](https://webflow.getmaintainx.com/integrations/fuelcloud)
- MachineMetrics can trigger WOs from real-time machine conditions (Enterprise). — [MachineMetrics](https://www.getmaintainx.com/integrations/machine-metrics)

### Inferences
- SICOM's GPS-fed hour meter (Radicom/Navixy, rFMS, every 5 min) already beats MaintainX's daily telematics sync.
- Worth copying:
  - (a) A **delta-between-readings trigger**, which flags a jump or a rollback directly (SICOM fixes horometer errors by hand, MIG641).
  - (b) Statuses **Pending/Stable/Triggered** shown per meter.
  - (c) An "expected vs entered" check on manual readings, which can be a simple statistical rule rather than AI (expected = last + avg daily usage × days elapsed).
  - (d) A "**fuel transaction updates the meter**" path, like FuelCloud. SICOM already captures horometer/km on fuel loads (Romeral/ENEX), so it could feed the meter.
- MaintainX's split is a useful design pattern: plans for PM, meter triggers and automations for condition alerts.

### Gaps
- No documented rule for a reading lower than the previous one (rollback, meter replacement, or an offset when a hour-meter or ECU is changed). This is not covered in the meter articles reviewed.
- No documented way to edit or delete individual readings.
- No native MaintainX Geotab integration was found.

## 3. Parts/inventory: BOM, reservation/consumption, min/max, multi-location, cycle counts, POs, vendors

### Takeaway
MaintainX has a detailed **part status pipeline**: Assigned → Reserved → Kitted → Staged → Issued. There is an **Available = In Stock − Committed** calculation, an **auto-reserve window** that commits parts X days before the WO start date, and min/max per location that drives PO quantities. POs have approval rules by total cost and partial receipts that update stock. Costing is **moving average** only (no FIFO documented). Reviewers call inventory and POs the weaker area.

### Cited Findings
- **Parts ↔ assets**: parts are linked to assets as items needed for that asset's maintenance. Adding an asset to a WO lets you pick its linked parts, which then count as reserved quantities. — [About Parts](https://help.getmaintainx.com/about-parts)
- Quantities on a part:
  - **In Stock** turns red below the minimum and can go negative.
  - **Available** = In Stock − Committed (per location).
  - **Ordered Quantity** = Ordered − Fulfilled across approved and pending POs, floored at 0. Clicking it opens the PO.
  - **Minimum in Stock** is the red threshold. **Critical** parts email an escalation team when below the minimum.
  - **Maximum in Stock** is the target used to calculate PO quantities; if unset, the minimum is used.
  - Source: [About Parts](https://help.getmaintainx.com/about-parts)
- Part statuses on a WO:
  - **Assigned**: identified and added, not committed.
  - **Reserved**: committed, removed from Available.
  - **Kitted**: picked and grouped.
  - **Staged**: placed in a pickup area.
  - **Issued**: the technician has received the parts.
  - Source: [Part Statuses and Availability](https://help.getmaintainx.com/part-statuses-and-part-availability)
- **In Stock decreases only on Issue**, either by setting Issued or by closing the WO, which issues the remaining parts automatically. Reserved, Kitted and Staged lower Available but not In Stock. Moving from Assigned to Reserved runs an **overcommitment check**. Removing a part from a WO returns it to Available. — [Part Statuses and Availability](https://help.getmaintainx.com/part-statuses-and-part-availability)
- WO-level availability labels: Available / Partial / Unavailable, recalculated live. A warning icon flags competing commitments across WOs. — [Part Statuses and Availability](https://help.getmaintainx.com/part-statuses-and-part-availability)
- Who changes statuses:
  - Assigned is set automatically.
  - Reserved is set by a parts clerk or planner, **or automatically via the auto-reserve window**.
  - Kitted and Staged are set by the clerk or planner.
  - Issued is set by a technician or clerk, or automatically when the WO is done.
  - Source: [Part Statuses and Availability](https://help.getmaintainx.com/part-statuses-and-part-availability)
- Inventory settings:
  - **Auto Reserve Window**: parts are marked Reserved X days before the WO start date (example: 15 days). The **Assigned Quantity Window** works the same way for Assigned.
  - **Needs Restock Trigger**: compare the minimum against physical In Stock (default) or against Available.
  - **"Calculate Unit Cost Following a Moving Average"** across PO restocks.
  - **Allow Unit Cost Overrides** per WO, without changing the global cost.
  - Prevent Negative Ordered Quantity, for over-received POs.
  - Default fields can be made required, including on API and imports: unit cost, min/max, **Average Lead Time**, barcode, part type, teams, assets, vendors.
  - Source: [Parts Inventory Settings](https://help.getmaintainx.com/parts-inventory-settings)
- **Multi-location parts** (Enterprise): one part with several locations, each with its own quantity and its own minimum. **Part sharing between organizations** of the same company is also Enterprise. — [About Parts](https://help.getmaintainx.com/about-parts); [Order and Restock Parts](https://help.getmaintainx.com/order-and-restock-parts)
- Barcode or QR scan on mobile adds a part to a WO or finds it in the list. — [About Parts](https://help.getmaintainx.com/about-parts)
- **Cycle counts**:
  - Created and scheduled on the web only (Parts > Cycle Counts).
  - Each occurrence generates a special WO with a progress bar and a count field per part. Each count is attributed to the user who entered it.
  - Counting works on web and mobile but **not offline**.
  - A results report is generated on completion and can be exported.
  - Counts are usually batched by last recount date or criticality.
  - Variance and adjustment handling is not documented.
  - Source: [About Cycle Counts](https://help.getmaintainx.com/about-cycle-counts)
- **Purchase orders**:
  - Lifecycle: an Admin creates the PO, or a Full User requests it (web) and an Admin approves; approval; fulfillment (receipts record quantity received **and price paid**); an Admin marks it complete.
  - **Approval rules** route POs to users or teams, or auto-approve, **based on total cost thresholds**.
  - Taxes and additional costs (shipping) can be added.
  - Full Users cannot see costs.
  - An approved PO can be emailed to the vendor from the app.
  - Inventory parts pull in their unit cost and the vendor's **Ordering Part Number**. **One-off (non-stock) items** are received but not added to inventory.
  - Fulfilled quantities update stock automatically.
  - Available on Premium and Enterprise.
  - Source: [About Purchase Orders](https://help.getmaintainx.com/about-purchase-orders)
- "Start an order" from a low-stock part's page creates a PO automatically. Manual "+Restock" lets you adjust the quantity received. — [Order and Restock Parts](https://help.getmaintainx.com/order-and-restock-parts)
- Vendors: a part can have several vendors, each with its own ordering part number. When a PO specifies a vendor, that vendor's parts are prioritized when adding items. — [About Parts](https://help.getmaintainx.com/about-parts); [About Purchase Orders](https://help.getmaintainx.com/about-purchase-orders)
- Reviews:
  - Capterra reviewers report weak PO reporting.
  - One says WOs can't link to POs, and that PO and inventory development is slower than other modules.
  - Others say inventory is "lacking" or "a big gap".
  - TrustRadius praises how smooth the inventory workflow is.
  - Infraspeak says inventory and POs are Premium-tier. Premium is $75 per user per month per Software Advice vs $65 annual per Infraspeak; these conflict and may be monthly vs annual billing.
  - Sources: [Capterra reviews](https://www.capterra.com/p/179296/MaintainX/reviews/); [Infraspeak review Oct 2026](https://infraspeak.com/en/compare/maintainx-review); [Software Advice](https://www.softwareadvice.com/cmms/maintainx-profile/)

### Inferences
- Highest-value ideas for SICOM's bodega:
  - (1) Separate **Committed** from **In Stock**, with **Available** shown on the WO. Today a vale probably moves stock directly.
  - (2) An **auto-reserve window**: since PM WOs are pre-generated up to a horizon, the parts-per-service kit could be auto-reserved N days ahead. The WO then shows Available/Partial/Unavailable, and Coquimbo knows what to buy before the truck arrives.
  - (3) **Restock against Available instead of physical stock**.
  - (4) Max-in-stock driving the suggested PO quantity, plus Average Lead Time per part.
  - (5) Critical-part escalation email.
  - (6) Cycle counts as scheduled WOs.
- Where SICOM is already ahead: FIFO costing (MaintainX documents moving average only), and Softland integration with the real ERP. MaintainX POs are internal and reviewers say WO↔PO linkage is weak. SICOM links vales to WOs, which MaintainX does by issuing parts on the WO.

### Gaps
- Return-to-stock flow for parts already Issued is not documented.
- Cycle count variance approval or adjustment rules are not documented.
- No formal parts kit object was found beyond asset-linked parts and the Kitted status.
- PO numbering, partial-receipt status names, and a native WO↔PO link are not documented (one reviewer says the link is absent).

## 4. Asset cost tracking / TCO

### Takeaway
Costs roll up from WO labor (time tracking) and parts (unit cost, moving average or override) into reports filterable by asset. No dedicated in-product TCO screen was found documented. MaintainX's TCO content is educational.

### Cited Findings
- MaintainX describes a "Time and Cost Tracking" report that breaks WO cost (parts, labor) down by team, user, asset and location (blog). — [6 CMMS reports](https://www.getmaintainx.com/blog/6-cmms-reports-to-help-you-run-leaner-maintenance)
- The reporting page claims reports on labor utilization, overtime and total maintenance costs (marketing). — [Reporting](https://www.getmaintainx.com/use-cases/reporting)
- TCO formula as published by MaintainX: Initial Asset Cost + Operation + Maintenance + Downtime + Production Cost − Remaining Value. This is educational content, not a product feature. — [What is cost management for maintenance](https://www.getmaintainx.com/learning-center/what-is-cost-management-for-maintenance)
- Parts cost on a WO comes from the part's unit cost (moving average across PO restocks), with optional per-WO override. — [Parts Inventory Settings](https://help.getmaintainx.com/parts-inventory-settings)
- Reporting limitations are a recurring complaint in reviews. — [Infraspeak review](https://infraspeak.com/en/compare/maintainx-review); [Software Advice](https://www.softwareadvice.com/cmms/maintainx-profile/)

### Inferences
- SICOM's cost panel (Softland OC + bodega FIFO + monthly cost report) is probably richer than MaintainX's asset cost view. MaintainX's formula is a useful checklist of TCO components: downtime cost and remaining value are the ones SICOM could add to the asset sheet.

### Gaps
- No help-center article was found describing an asset-level cost tab or TCO screen, or its exact fields. I did not verify inside the product.
- Whether PO costs not issued to a WO, such as one-off items, roll up to an asset is not documented.
