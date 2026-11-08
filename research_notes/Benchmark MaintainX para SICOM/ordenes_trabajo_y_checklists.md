# MaintainX: work order lifecycle, procedures/checklists, findings to corrective action, and how work orders are closed

Research date: 2026-11-08. Sources are mostly the MaintainX help center (help.getmaintainx.com, current), the MaintainX blog (May 2026 release notes) and the MaintainX community forum. The community and blog posts carry no clear date unless noted. Plan tiers matter: many features are limited to Premium or Enterprise.

## 1. Work order statuses, priorities, categories, assignment, recurring work orders, templates, time and cost

### Takeaway
MaintainX keeps the lifecycle deliberately small: four working statuses (Open, In Progress, On Hold, Done) plus Canceled and Skipped. Most of the control comes from configuration instead. Admins choose which fields are required, which status changes need a comment, and what must be logged before Done (parts, time, cost, summary). Templates can lock fields as read-only, hidden or required.

### Cited Findings
- **Statuses.** There are four statuses: Open, On Hold, In Progress and Done. New work orders start as Open. The status changes to In Progress automatically when someone starts work or updates a procedure step. On Hold pauses the work, and "Mark as Done" closes it. — [MaintainX Help: Complete a Work Order](https://help.getmaintainx.com/complete-a-work-order)
- **Reporting buckets.** The work-orders-by-status report counts Open, On Hold and In Progress together as "Not Completed". It shows Skipped and Canceled separately from Done. — [MaintainX Help: Work Orders by Status report](https://help.getmaintainx.com/work-orders-by-status-report)
- **API status values.** A third-party mirror of the API lists OPEN, IN_PROGRESS, ON_HOLD, DONE, CANCELED and SKIPPED. Another mirror omits SKIPPED for updates. Neither is the official reference. — [withone.ai MaintainX API mirror](https://www.withone.ai/knowledge/maintain-x/conn_mod_def%3A%3AGKHiBgHdgvw%3A%3AREq2hKDKR3yD6geBYgpwgA)
- **Comments required for "negative" status changes.** Admins can require a comment when a work order goes On Hold, is Skipped or is Canceled. Each rule is set to None, Optional or Mandatory. — [MaintainX Help: Work Order Settings](https://help.getmaintainx.com/work-order-settings)
- **Work order form fields:**
  - Title ("What needs to be done?") is the only mandatory field by default, up to 255 characters. Description holds up to 4,096 characters.
  - Asset: the field disappears once sub-work orders are added.
  - Location: one per work order, set automatically from the asset's location.
  - Priority.
  - Categories: one or more, either built-in (Safety, Standard Operating Procedure) or custom.
  - Assignees: one or more users and/or teams.
  - Due Date (defaults to 12:00 PM) and Start Date (defaults to 12:00 AM).
  - Recurrence: weekly, monthly or "Does not recur".
  - Estimated Time.
  - Work Type: Preventive, Reactive or Other.
  - Procedure: cannot be added to a parent work order directly.
  - Vendors.
  - Parts: "Amount Used" is required for each part; unit cost override and source location are optional.
  - Files.
  — [MaintainX Help: Work Order Form Fields](https://help.getmaintainx.com/work-order-form-fields)
- **Configurable required fields.** Under Settings > Features > Work Orders > Set Preferences, each of these default fields can be Optional or Required: Asset, Users, Attachment, Description, Due Date, Location, Parts, Priority, Procedure, Recurrence, Categories, Teams, Vendors. Custom fields can also be required on create and update (Enterprise). — [Work Order Settings](https://help.getmaintainx.com/work-order-settings)
- **Custom fields.** Custom fields have the same options as default fields (Required, Read Only, Hidden). — [Search summary of the MaintainX custom fields article](https://intercom.help/maintainx/en/articles/5693033-adding-custom-fields-in-work-orders)
- **Assign by mention.** With "Assign Users and Teams on Mention" turned on, @mentioning a user or team in a comment adds them as an assignee. — [Work Order Settings](https://help.getmaintainx.com/work-order-settings)
- **Overdue escalation teams (Enterprise).** Selected teams are notified when work orders become overdue. — [Work Order Settings](https://help.getmaintainx.com/work-order-settings)
- **Configurable work order IDs.** "Next Work Order ID" sets a new starting number across the organization. The change can't be undone. — [Work Order Settings](https://help.getmaintainx.com/work-order-settings)
- **Work order templates** (Premium/Enterprise, created by admins on the web):
  - Each section's fields can be pre-filled, Hidden, Required or Read-only.
  - Procedure and Assignees can be required, hidden or read-only.
  - Priority can only be read-only.
  - Locations, Assets, Parts, Categories and Vendors can be required, hidden or read-only.
  - A read-only field with several preselected assets or locations becomes a dropdown limited to those choices.
  - "Relevant Teams" pins a template to the top of the list for specific teams.
  - Recurrence is only available when Template Type = Preventive. Due Date Settings take a number plus a unit (minutes, hours, days or weeks) and a start date so the work order appears before it is due.
  — [MaintainX Help: Create a Work Order Template](https://help.getmaintainx.com/create-a-work-order-template)
- **Meter-based recurrence moved to Workflow Automations.** The old work order "triggers" are no longer available; meter-based creation now runs through Workflow Automations. Thresholds can be "Increases by / Decreases by (from last trigger)", and the automation shows a "Next trigger at" value (the example is a truck at 15,000 miles). — [MaintainX Help: Trigger a Work Order](https://help.getmaintainx.com/trigger-a-work-order); [MaintainX Help: About Automations](https://help.getmaintainx.com/about-automations)
- **Automations:**
  - Actions: create a work order, change asset status (for example to Offline), or send an email.
  - Optional conditions, such as a time window.
  - Action History shows runs that succeeded, failed or were skipped, with links to the resulting work orders.
  - Plans: Premium gets meter-triggered work order creation; Enterprise gets custom automations with all conditions and actions.
  - Automations are configured on the web only.
  — [About Automations](https://help.getmaintainx.com/about-automations)
- **Automations in the May 2026 release.** Automations can create a work *request* instead of a work order, so the work goes through triage first (Enterprise). New conditions fire only on specific weekdays or when the asset is in a particular status (Enterprise). Multi-asset automations apply one rule to several assets (Premium+). — [What's New at MaintainX, May 2026](https://www.getmaintainx.com/blog/whats-new-at-maintainx-may-2026)
- **Next due date from last completion.** A community feature request asks for the next due date to be calculated from the last completion date. This suggests the feature was missing when the post was written. I found no confirmation that it exists now. — [MaintainX Community: feature request 275](https://community.getmaintainx.com/product-q-a-6/feature-request-275)
- **Time and cost logging** (Enterprise for the full module):
  - Time and cost can be added while the work order is Open, On Hold or In Progress.
  - Time is entered by hand or with the mobile timer. Labor cost uses the user's default hourly rate, which can be overridden; a rate of 0 means no labor cost.
  - Other costs take a description, a cost category and receipt attachments.
  - Parts are added with a location and quantity, and their unit costs are shown.
  — [Complete a Work Order](https://help.getmaintainx.com/complete-a-work-order)
- **Time and cost types.** Time types (default Inspection, Work, Other) and cost types (default Labor, Travel, Other) can be customized on Premium/Enterprise. — [Work Order Settings](https://help.getmaintainx.com/work-order-settings)
- **Smart Time Estimates (Enterprise).** AI estimates the time a work order will take, based on past work orders with the same procedure. — [Work Order Settings](https://help.getmaintainx.com/work-order-settings); [About Procedures](https://help.getmaintainx.com/about-procedures)
- **Sub-work orders (Premium+).** They can be created for several assets, a single asset or no asset, with bulk editing (May 2026). — [May 2026 release](https://www.getmaintainx.com/blog/whats-new-at-maintainx-may-2026)

### Inferences
- The pattern worth copying for SICOM is a small, fixed set of statuses with strictness set by admin rules: mandatory comment on hold, cancel or skip; required parts, time or summary per work type. Adding more states is not needed.
- "Next trigger at" is a simple way to show meter-based preventive maintenance. Each truck shows its next service horometer or km reading, like the escalera MB 300h logic.
- Routing automations to a *request* (triage) instead of straight to a work order matches SICOM's NC → OS flow. Findings wait in a queue until a planner groups and schedules them.

### Gaps
- The priority values are not listed on the official pages I read. My unverified recollection is None/Low/Medium/High; check this.
- I found no official confirmation that recurrence can be anchored to the completion date.

## 2. Procedures and checklists: field types, conditional logic, failed item → corrective work order, library

### Takeaway
The Pass / Flag / Fail field ("Inspection Check") is the core of MaintainX checklists. An org-wide setting decides whether a Fail or a Flag creates a corrective work order with a prompt, without a prompt, or not at all (only a comment alert). Only the failed items carry over to the new work order. Scoring and AI anomaly detection on numeric fields are further ways to trigger corrective actions.

### Cited Findings
- **Field types:**
  - Checkbox, Text, Number, Amount (currency), Multiple Choice, Checklist.
  - Inspection Check (Pass / Flag / Fail).
  - Yes / No / N/A.
  - Picture/File.
  - Signature Block.
  - Date, with an optional time.
  - Meter Reading: tied to a specific meter, so the reading updates that meter.
  - Location Check-In: the technician must verify their physical location before later steps.
  — [MaintainX Help: Procedure Fields](https://help.getmaintainx.com/procedure-fields)
- **API field type enum.** NUMBER, AMOUNT, TEXT, HEADING, FILE, SIGNATURE, MULTIPLE_CHOICE, INSPECTION_CHECK, YES_NO_NA, CHECKBOX, CHECKLIST, METER, DATE, CYCLE_COUNT. This comes from a third-party mirror. — [withone.ai mirror](https://www.withone.ai/knowledge/maintain-x/conn_mod_def%3A%3AGKHh_GIcJIs%3A%3AQod_CIXKTWeIHBcNPuhGzA/md)
- **Per-field options:**
  - Add Condition: conditional visibility; not available on Text.
  - Add Link.
  - Assign Users: assign a user or team to the field, or mark it "assignable later" when the work order is created. Assigned fields must be completed before the work order can be completed.
  - Reference pictures or files attached to the field.
  - Required toggle: the procedure cannot be completed while a required field is empty.
  - Description.
  - Limits: 350 fields per procedure and 512-character field names.
  — [Procedure Fields](https://help.getmaintainx.com/procedure-fields)
- **Corrective action setting.** Under Work Order Settings, "Failures" can be set to *Automatic with Prompt*, *Automatic without Prompt* or *None*. With None, an alert appears in the work order's comments mentioning the inspection failure. "Flags (including anomalies)" has the same three options (Premium/Enterprise). — [Work Order Settings](https://help.getmaintainx.com/work-order-settings)
- **Which field types trigger it.** Corrective work orders come from Pass/Flag/Fail fields, not Yes/No/N/A; a community member confirmed Yes/No/N/A lacks this. The original poster switched to Inspection Check fields with both Flag and Fail generating corrective actions. The follow-up work order can be edited after it is created. — [MaintainX Community: Prompting a follow-up work order](https://community.getmaintainx.com/getting-started-2/prompting-a-follow-up-work-order-489)
- **What the corrective work order contains.** The technician is prompted to confirm, and a corrective work order is created with a modified title (example: "Corrective action on Daily compressor inspection"). "Only the failed tasks or elements from the preventive maintenance work order carries over to the corrective task." The manager can then edit the assignee, priority, description and parts. The technician is notified when the work order is scheduled and assigned. — [MaintainX: Quality control apps](https://www.getmaintainx.com/quality-control-apps/)
- **Conditional logic.** A field can be shown only when another field has a specific value (example: a multiple-choice option). The pages I read do not list the operators or any numeric range comparisons. — [MaintainX Help: About Procedures](https://help.getmaintainx.com/about-procedures)
- **Procedure scoring:**
  - Points can be assigned only to Checkbox, Multiple Choice, Checklist and Inspection Check fields, with a score for each option.
  - The goal score is None, 25%, 50%, 75% or a custom percentage.
  - A score below the goal triggers a corrective action prompt (example: 35% against a 50% goal).
  — [MaintainX Help: Procedure Scoring](https://help.getmaintainx.com/procedure-scoring)
- **Anomaly detection:**
  - Works on Number, Amount and Meter Reading fields once the procedure has been used in at least 3 past work orders.
  - Confirming an anomaly records a flag on the work order, which can feed the Flag corrective-action rule.
  - Also applies to one-off meter readings.
  — [MaintainX Help: Anomaly Detection](https://help.getmaintainx.com/anomaly-detection); [Work Order Settings](https://help.getmaintainx.com/work-order-settings)
- **Library structure:**
  - Procedure Library with drafts that only the creator can see; drafts cannot be attached to work orders.
  - Public Procedure Hub of templates, searchable by industry, type or keyword.
  - Nested procedures: one procedure embedded in another. Editing it in the library updates every parent; "Merge into parent" turns it into a local section instead.
  - History, plus Version History showing what was added, edited or removed.
  - Per-procedure "Work Order History" with created and completed counts.
  - Global procedures shared across sub-organizations, with a version comparison tool.
  — [About Procedures](https://help.getmaintainx.com/about-procedures)
- **AI help (May 2026, Enterprise with Assist).** An AI Procedure Generator builds a procedure from a prompt or a file. AI Procedure Recommendations suggest a library procedure when a work order is created, based on its title, description and asset. — [May 2026 release](https://www.getmaintainx.com/blog/whats-new-at-maintainx-may-2026)
- **Template for findings outside the checklist.** A Hub template, "Corrective Action Required", covers corrective actions on preventive work orders that the Pass/Flag/Fail field does not cover. — [Procedure Hub: Corrective action required](https://getmaintainx.com/procedures/d/8AMtuQnAWoM/corrective-action-required)

### Inferences
- The three-state Pass / Flag / Fail field is the main idea to copy. "Flag" (observation or early wear: watch it, plan it) is separate from "Fail" (out of service or corrective now), and each can have its own policy. In SICOM terms, Fail could open an NC with high priority and block certificates, while Flag could open an NC as an observation for the next OS.
- The org-wide switch (automatic with prompt / without prompt / alert only) is cheap to build and avoids hard-coding behavior.
- Carrying *only the failed items* into the corrective work order is the same as SICOM grouping NCs by vehicle. The difference is that MaintainX creates one corrective work order per inspection, while SICOM groups across inspections.
- "Assigned fields must be done before the work order closes" maps to multi-role checklists, for example a mechanic step plus a supervisor sign-off step inside the same V03.

### Gaps
- I found no official step-by-step page on linking corrective and original work orders. The "Corrective Actions through Procedure Inspection Checks" help page that procedure-fields links to was not retrievable by search.
- I could not confirm numeric thresholds inside procedure fields (min/max that auto-flag). Only AI anomaly detection is documented.
- I could not confirm whether a photo can be required when an item is marked Fail.

## 3. Inspections → findings → corrective work orders: traceability and parent/child work orders

### Takeaway
Traceability works in three ways:
- Corrective work orders spawned from failed or flagged checks.
- Parent and sub-work orders with rolled-up progress.
- Reports that filter by Fail or Flag and group failed checks by asset.

RCA reports now link in both directions with the work orders that triggered them (2026). The documentation does not describe an explicit "spawned from work order #X" link for corrective work orders.

### Cited Findings
- **Parent and sub-work orders:**
  - The parent shows a progress bar of its sub-work orders' statuses.
  - Completing the parent requires completing its sub-work orders. Marking the parent Done early automatically marks every sub-work order Done.
  - Reopening a sub-work order reopens the parent.
  — [Complete a Work Order](https://help.getmaintainx.com/complete-a-work-order)
- **No procedure on the parent.** A parent work order cannot carry a procedure directly, and the Asset field disappears once sub-work orders exist. — [Work Order Form Fields](https://help.getmaintainx.com/work-order-form-fields)
- **Fail/Flag filter and report.** "Filter by Fail or Flag" adds a Procedure Flags filter to work order views. — [Work Order Settings](https://help.getmaintainx.com/work-order-settings) A "Completed with Inspection Check" report exists and can be grouped by asset to show failed or flagged checks. — [MaintainX Help: Completed with Inspection Check report](https://help.getmaintainx.com/completed-with-inspection-check-report) (seen in a search summary only, not fetched)
- **RCA linking (Enterprise, May 2026).** Root Cause Analysis reports link to their triggering work orders in both directions, automatically when the RCA is started from the work order. Labor and wrench time from the linked work order fill the RCA's repair time. — [May 2026 release](https://www.getmaintainx.com/blog/whats-new-at-maintainx-may-2026)
- **Requests to work orders.** Approving a work request sets it to Approved and creates a work order. The requester then sees the new work order's ID and status in the request. — [MaintainX Help: Approve or Decline Work Requests](https://help.getmaintainx.com/approve-or-decline-work-requests)

### Inferences
- SICOM already does better on grouping (NC by vehicle → OS). What is worth copying:
  - The progress bar on the parent (OS) showing its children (NC or OT).
  - "Reopen a child → reopen the parent."
  - An explicit rule for what happens to open children when the parent closes. MaintainX auto-closes them; for SICOM it is safer to block closing or force a decision per NC.
- Two-way RCA linking with time carried over is a good model for recurring failures on the same truck.

### Gaps
- I found no documentation of a field or chip on the corrective work order pointing back to the source inspection work order.

## 4. Closing a work order: required fields, sign-off, completion requirements, review

### Takeaway
MaintainX closes with "Mark as Done" and gates it with configurable completion rules:
- Required procedure fields and assigned fields.
- At least one part.
- Time entered.
- Cost entered.
- Mandatory AI or voice summary per work type.

I found no native supervisor review or verification status after Done. Sign-off is done with a Signature field inside the procedure.

### Cited Findings
- **Completion rules:** "Part Required" (at least one part), "Time Tracking Required" and "Cost Tracking Required" toggles. "Work Order Summary" (Enterprise) can be None, Optional or Mandatory for each work type (Preventive, Reactive, Other). — [Work Order Settings](https://help.getmaintainx.com/work-order-settings)
- **Summary prompt.** On Enterprise, users are prompted to record or type a summary when closing; this is part of CoPilot/Assist. A community answer says comments cannot be required at Done. — [MaintainX Community: require comments to close work orders](https://community.getmaintainx.com/product-q-a-6/require-comments-to-close-work-orders-464)
- **Procedure-level gates.** Required fields block completion of the procedure, and assigned fields block completion of the work order. Location Check-In must be done, or skipped if allowed, before later steps. — [Procedure Fields](https://help.getmaintainx.com/procedure-fields); [Complete a Work Order](https://help.getmaintainx.com/complete-a-work-order)
- **Permits (Beta).** Marking a work order Done sets its permit to "Work Done". A user with permission closes the permit separately, which acts as a second sign-off. — [Complete a Work Order](https://help.getmaintainx.com/complete-a-work-order)
- **Signature.** Sign-off appears as a Signature Block field in user-built procedures such as "A Team Work Order Sign Off". It is not a platform rule. — [Procedure Fields](https://help.getmaintainx.com/procedure-fields); [Procedure Hub: A team work order sign off](https://www.getmaintainx.com/procedures/d/KyP1nM9teks/a-team-work-order-sign-off)

### Inferences
- The idea to copy is completion rules that vary by work type: a preventive OT could require a horometer reading plus parts, and a corrective OT a summary plus photo. SICOM's quality audit or "cruzado" gate already goes beyond MaintainX, which has no native review step after Done. This is a point where SICOM is ahead.
- A required AI or voice summary at close (dictated on mobile) is a low-friction way to get readable closing notes from mechanics.

### Gaps
- I found no MaintainX "Pending review / Verified" status or approval workflow for completed work orders. It may exist in Enterprise without public documentation.

## 5. Asset hierarchy, downtime (status up/down) and the effect of work orders

### Takeaway
An asset is Online or Offline. Offline is tagged Planned or Unplanned, with custom reasons and a note. Status can be changed from the asset, from a work order or request, or by an automation. Closing a work order on an offline asset prompts the user to bring it back online. That prompt is what produces downtime history and the asset health metrics.

### Cited Findings
- **Changing status (Premium/Enterprise).** Asset status can be changed inside a work order or on the asset itself. Offline is marked planned or unplanned with an optional note, and custom status reasons apply to all assets. — [Search summary of MaintainX help article "Tracking asset downtime"](https://intercom.help/maintainx/en/articles/6884731-tracking-asset-downtime) (the direct fetch returned 404; details come from the search snippet)
- **Prompt at completion.** Technicians can change asset status while creating a work order. When work on an offline asset is completed, they are prompted to set it back to online. Equipment can be marked offline from work requests and corrective actions, and with one click when a corrective action is required after an inspection. — [What's New at MaintainX, Nov 2023 / Jan 2024](https://www.getmaintainx.com/blog/whats-new-at-maintainx-november-2023) (older, 2023-24; based on the search summary)
- **Reporting.** Asset Health Insights filters by online, offline planned or offline unplanned. Downtime export is CSV, one asset at a time. — [Search summary of the same 2023-24 sources](https://www.getmaintainx.com/blog/whats-new-at-maintainx-january-2024) (older)
- **Automations.** Automations can set an asset Offline, and since May 2026 they can use asset status as a condition. — [About Automations](https://help.getmaintainx.com/about-automations); [May 2026 release](https://www.getmaintainx.com/blog/whats-new-at-maintainx-may-2026)

### Inferences
- The "back online?" prompt at work order close is worth copying. SICOM already has a planner-driven status and a Change Status modal with gates (migs 239-242, 307). The MaintainX pattern would add: closing the last OT or OS on a truck in "M" asks to move it to Operative, and the downtime interval is recorded with a planned or unplanned reason.

### Gaps
- I did not research asset hierarchy (parent and child assets) in this pass. The downtime help article returned 404, and some details come from 2023-2024 posts.

## 6. UX patterns users praise or criticize

### Takeaway
Reviewers consistently rate ease of use and the mobile app highly. G2 score is about 4.8/5. Asset QR codes are among the most praised features. Complaints are mobile bugs, gaps between mobile and desktop, notification overload, and awkward QR printing.

### Cited Findings
- **G2 ratings and themes.** G2 rates MaintainX about 4.8/5 (roughly 900+ reviews). Its summary praises ease of use and intuitive design, and notes limits in mobile functionality and reporting on lower tiers. — [G2 MaintainX reviews](https://www.g2.com/products/maintainx/reviews)
- **QR codes.** Reviewers describe asset QR codes as "fantastic", speeding up search and cutting data entry. Criticisms: no way to scan a QR and auto-create a work order in one step, and trouble printing only a few codes. — [G2 reviews pages](https://g2.com/products/maintainx/reviews?page=2); [Capterra reviews](https://www.capterra.com/p/179296/GetMaintainx/reviews/?page=5)
- **Mobile complaints.** Bugs in the mobile app that teams rely on to open and close work orders, mobile and desktop "do not interface well", and too many notifications. — [G2](https://g2.com/products/maintainx/reviews?page=4); [Capterra](https://www.capterra.com/p/179296/GetMaintainx/reviews/?page=5)
- **Offline mode.** Offline mode and meters date back to July 2020. — [MaintainX Release Notes July 2020](https://www.getmaintainx.com/release-notes-july2020) (older)

### Inferences
- For SICOM: scanning the QR on a truck should go straight to "new OT/NC for this vehicle" with the asset and location pre-filled. That is the step reviewers say MaintainX lacks.

### Gaps
- The review excerpts come from search summaries, mostly 2023-2025, and were not individually verified.
