# MaintainX: app móvil/offline, portal de solicitudes, mensajería y automatizaciones (benchmark para SICOM)

Research date: 2026-11-08. Main sources: MaintainX help center (help.getmaintainx.com), integration pages, community, and review aggregators. The help center pages were read as they stood in Nov 2026. The July 2025 changelog dates several features (request portals, threads).

## Mobile app and offline mode for technicians

### Takeaway
MaintainX offline mode is narrower than SICOM's. It is a **cache of work orders** limited by count, ordered by due date, and filtered to the user's own or their team's WOs. Technicians can update those cached WOs offline. No conflict resolution is documented, and reviewers report delays and one case of data loss. What stands out is how configurable and visible the cache is (limit, filter, last update, storage, clear), plus the QR/barcode scan button and the voice notes transcribed by AI.

### Cited Findings
- Offline mode is **mobile only**, on all plans (Basic through Enterprise), for Full Users and Administrators. **Requesters cannot use it.** — [Offline mode](https://help.getmaintainx.com/offline-mode)
- What is documented: technicians "update work orders while they're offline". Changes go to local copies and sync later. The page lists no other offline functions. — [Offline mode](https://help.getmaintainx.com/offline-mode)
- Activation: **automatic** when there is no connection, or manual via Account > Offline Settings > "Is Offline". You must be online beforehand to build or update the cache. — [Offline mode](https://help.getmaintainx.com/offline-mode)
- Configurable cache settings:
  - "Save work orders assigned to": only me, or me plus my teams. With "only me", WOs assigned only to a team are not saved.
  - "Update cache when": Manually, or "Connected to any network".
  - "Cache Limit": number of WOs. The app trims automatically if the limit is lowered. No default or maximum value is published.
  - "Cache last updated": tap to force an update.
  - "Available Storage".
  - "Clear local cache": only with offline mode off.
  - "Disable Caching": changes made offline are not saved.
  - Source: [Offline mode](https://help.getmaintainx.com/offline-mode)
- How the cache is built:
  - It rebuilds when the user opens the To-do or Calendar view, or updates it manually.
  - Eligible WOs go in **in due-date order (soonest first)** up to the limit.
  - The cache rebuilds periodically when eligible WOs change.
  - The cache **survives a reboot or a dead battery**.
  - Source: [Offline mode](https://help.getmaintainx.com/offline-mode)
- When it reconnects, the app **asks the user to turn off offline mode and sync**. Sync is automatic or manual depending on settings. — [Offline mode](https://help.getmaintainx.com/offline-mode); [Mobile app overview](https://help.getmaintainx.com/getting-started-new-users/mobile-app-overview)
- Multiple organizations: you cannot switch organizations offline. Before switching, offline changes are synced to the original organization. — [Offline mode](https://help.getmaintainx.com/offline-mode)
- **Workstation mode** turns a device into a shared multi-user terminal:
  - Logging in requires a connection. Offline mode can be turned on after login.
  - A user who logs out offline cannot log back in until the device reconnects.
  - Inactivity timers still apply offline.
  - Only one workstation at a time.
  - Sources: [Offline mode](https://help.getmaintainx.com/offline-mode); [July 2025 update](https://help.getmaintainx.com/help-center-updates/july-2025)
- Lowering the cache limit is the official fix for an app that lags or crashes. — [Troubleshooting lag](https://help.getmaintainx.com/troubleshooting-mobile-application-is-lagging) (cited via search snippet)
- **Scan Code** is a shortcut on the Overview screen that reads QR or barcodes with the camera. Scanning an asset's QR code adds it to a WO. The QR/barcode module is turned on in Advanced Features. — [Mobile app overview](https://help.getmaintainx.com/getting-started-new-users/mobile-app-overview)
- From the Requests screen, scanning an asset's QR code starts a request. MaintainX AI then fills in the asset's name, description, manufacturer and model. — [Set up a request portal / work requests](https://help.getmaintainx.com/set-up-a-request-portal) (cited via search snippet)
- **Voice memos** can be attached to WOs and transcribed to text by AI on request (a manual step). The article is more than two years old. — [AI-powered voice memos](https://intercom.help/maintainx/en/articles/8510395-ai-powered-voice-memos)
- The App Store listing mentions photos, voice notes and offline work. — [App Store](https://apps.apple.com/app/1437854484)
- Requests can be created by chatting with MaintainX AI, with a voice note, or with free text. The AI generates the request (title, description, location, priority). — [About work requests](https://help.getmaintainx.com/about-work-requests)
- Languages:
  - 16 languages as of the Feb 2024 announcement. — [Blog more languages](https://getmaintainx.com/blog/support-your-global-workforce-with-maintainx-now-in-more-languages)
  - Spanish is on the official list. Each language is labeled "MaintainX Reviewed" or "User Reviewed", and the page warns that AI translations may contain errors. — [Supported languages](https://help.getmaintainx.com/supported-languages)
  - Changing the language does not change date, currency or teammates' comments. — [Change display language](https://help.getmaintainx.com/change-the-display-language) (via snippet)
- A "Tap to Translate" button in chat is claimed only by a competitor's blog and was not verified against MaintainX documentation. — [Fabrico blog](https://www.fabrico.io/blog/best-cmms-software-mixed-language-workforces/)
- Reviews:
  - "Occasional delays syncing in low Wi-Fi areas". — [Software Advice](https://softwareadvice.com/cmms/maintainx-profile/reviews/)
  - "Offline functionality is limited compared to some alternatives". — [Digital Project Manager](https://thedigitalprojectmanager.com/tools/maintainx-review/)
  - One AWS Marketplace review reports data loss offline (a single case). — [AWS Marketplace reviews](https://aws.amazon.com/marketplace/reviews/reviews-list/prodview-7datgv4slskmk?page=5)
  - Ratings of around 4.8/5 on G2 and Capterra. — [Infraspeak](https://infraspeak.com/en/compare/maintainx-review)

### Inferences
- The idea worth copying is to make the offline cache **explicit and visible to the technician**. Before going to the mining site, the technician should see "how many OTs I have saved, last sync at HH:MM, space used". The cache should be filtered (mine / my crew) and ordered by due date. SICOM's PWA would gain from a "Preparar para faena" (prepare for site) screen with that information.
- Rebuilding the cache when the user opens the To-do or Calendar view is a cheap form of prefetch. It is equivalent to precaching the OTs the user is shown while online.
- SICOM looks ahead on conflicts: MaintainX documents none. If SICOM already handles offline queues with idempotency, it is above the benchmark here.
- The documented scope of MaintainX offline mode (updating WOs) is smaller than SICOM's offline forms (ENEX, Romeral, Franke). It is not a model for breadth, only for cache UX.
- Turning a QR scan into a pre-filled request (asset, model) and creating a report by voice are the most transferable ideas for operators with gloves or little time.

### Gaps
- No public numbers: default or maximum cache size, offline attachment size, or whether photos are queued.
- No documented behavior when two people edit the same WO offline (last-write-wins or merge).
- No official confirmation of whether procedures/checklists, signatures or parts can be completed offline. The help center only says "update work orders".
- Video capture in the mobile app is not documented. Video only appears as a portal attachment (.mp4).
- Claimed but unverified from primary sources: the 2026 voice/AI features roadmap, and Autodesk acquiring MaintainX for USD 3.6 billion in May 2026 ([Contrary Research](https://research.contrary.com/company/maintainx)).

## Request portal (requests from non-users)

### Takeaway
MaintainX separates **requests** from **WOs**. Requests come in through public portals (link or QR, no account needed) and through the "Requester" role in the app. An administrator, or the routed team's administrator, approves or declines each one, and only approved requests become WOs. Each portal can be **locked to a specific asset or location**, so a QR code stuck on the truck reports straight against that equipment. The requester gets optional emails at chosen events (created, approved, declined, completed).

### Cited Findings
- Portals are standalone web forms that **need no account**. Anyone with the URL or QR code can submit. Administrators can create "as many request portals as your organization needs". Portals are shared by copying the link or printing a QR code from "Share Portal". — [About work requests](https://help.getmaintainx.com/about-work-requests); [Create a request portal](https://help.getmaintainx.com/create-a-request-portal); [Share a request portal](https://help.getmaintainx.com/share-a-request-portal)
- Plan and role: portals are created on the **web only**, by **Administrators**, on **Premium and Enterprise** plans (not Basic or Essential). The path is Settings > Features > Request Portals > +New Request Portal. — [Create a request portal](https://help.getmaintainx.com/create-a-request-portal)
- Portal fields:
  - Portal Title (required).
  - Thumbnail and Welcome Text (optional).
  - Request Title (required for the requester).
  - Description.
  - WO custom fields, **Enterprise only**. Each can be marked "Include this field in Request Portal" and "Make this field required".
  - Support Contact, an email shown to the requester.
  - Source: [Create a request portal](https://help.getmaintainx.com/create-a-request-portal)
- **Location and asset prefill:**
  - "All" lets the requester pick from every location or asset. Warning: the portal is public, so those lists are visible to anyone with the link.
  - "Restricted" hides the field and automatically assigns the request to that location or asset.
  - If the location is restricted, the asset list shows only assets at that location.
  - Source: [Create a request portal](https://help.getmaintainx.com/create-a-request-portal)
- Custom links can be created per asset or location. — [Set up a request portal](https://help.getmaintainx.com/set-up-a-request-portal) (via snippet)
- Requester identification: with "Limit requester identification to email only" turned on, email is required. With it off, the requester can give email **or phone**. — [Create a request portal](https://help.getmaintainx.com/create-a-request-portal)
- Updates to the requester:
  - With "Let requesters choose to receive email updates" turned on, the requester sees "Receive Email Notifications" and must give an email.
  - The administrator chooses which events trigger emails: **Created, Approved, Declined, Completed**.
  - Source: [Create a request portal](https://help.getmaintainx.com/create-a-request-portal)
- Portal attachments: images (drag and drop) and files in .doc, .docx, .xlsx, .csv, .pdf, .gif, .jpg, .png and **.mp4**. .xls is not accepted. Files under 50 MB are recommended. — [Create a request portal](https://help.getmaintainx.com/create-a-request-portal)
- Portal requests land in the organization's central Requests inbox. Portal users see limited information. — [Set up a request portal](https://help.getmaintainx.com/set-up-a-request-portal) (via snippet)
- In-app channel: by default only **Requesters** submit requests. Administrators and Full Users create WOs directly. Requesters see the status of their own requests. — [About work requests](https://help.getmaintainx.com/about-work-requests)
- Approval:
  - Administrators approve or decline in the Requests module.
  - With **request routing** (Work Request Settings), the request goes to a team's queue and that team's administrators decide. The portal can let the requester choose the team.
  - **Approved requests become WOs**, which are then assigned.
  - Source: [About work requests](https://help.getmaintainx.com/about-work-requests); [Create a request portal](https://help.getmaintainx.com/create-a-request-portal)
- Requesters (users with an account) are notified when:
  - the request is approved or declined;
  - the resulting WO changes;
  - someone comments on that WO or mentions them.
  - Administrators are notified of requests waiting for approval.
  - Source: [About work requests](https://help.getmaintainx.com/about-work-requests)
- Request portals arrived as a new section in July 2025, along with the request routing update. — [July 2025 update](https://help.getmaintainx.com/help-center-updates/july-2025)
- Email and SMS as request channels are **not mentioned** in the official documentation. There are third-party Zapier bridges (Google Forms → request, Slack message → request). — [About work requests](https://help.getmaintainx.com/about-work-requests); [Zapier Google Forms](https://zapier.com/apps/google-forms/integrations/maintainx/368907/create-maintainx-work-requests-from-new-google-forms-entries); [Zapier Slack](https://zapier.com/apps/maintainx/integrations/slack/370537/add-maintainx-work-requests-from-new-slack-channel-messages)

### Inferences
- SICOM's client QR portal already covers viewing documents and reporting issues. What MaintainX adds:
  - **one portal per asset with the field locked**, so the client or driver does not choose the equipment and cannot see the rest of the fleet;
  - an **explicit request → approval → WO stage** with per-team routing;
  - **opt-in emails for the external requester** at four events;
  - required fields configurable per portal;
  - a phone number as an alternative identifier.
- The warning that a public portal exposes the lists of assets and locations is a useful lesson. In SICOM, the per-equipment QR should never list other equipment.
- The four-event model (Created, Approved, Declined, Completed) is a minimal, sensible policy for notifying clients without spamming them.

### Gaps
- No public page shows whether the external (portal) requester can view a status page or tracking link, rather than only receiving emails.
- No documented decline reason sent to the requester, and no SLA for approving requests.
- No info on anti-spam measures or captcha on public portals.

## Messaging and communication tied to records

### Takeaway
MaintainX has a full internal chat: direct, group and team chats, with each team chat created automatically. Separately, it has **comments on each WO and PO**. Its distinctive feature is the **two-way bridge between chat and record**: a WO can be created from any message, and assigning a WO to a team posts its link in that team's chat. Threads were in beta in July 2025.

### Cited Findings
- Types of conversation:
  - private (one to one);
  - **team chats**, created automatically when a team is created, with each new member added;
  - group chats (three or more people);
  - **comments on WOs and purchase orders**, which can be edited and, on some entities, reacted to.
  - Source: [About messaging](https://help.getmaintainx.com/about-messaging)
- Every user can send attachments and photos in messages. — [About messaging](https://help.getmaintainx.com/about-messaging)
- **A WO can be created from any message the user sent.** Requesters cannot do this. Assigning a WO to a team **posts the WO link automatically in the team chat**. — [About messaging](https://help.getmaintainx.com/about-messaging); [Send messages](https://help.getmaintainx.com/send-messages)
- Threads: a thread hangs off a specific message, has its own Threads tab and an "[X replies]" link, and a WO can also be created from a thread. Threads were "in Beta for all users" in July 2025. — [About messaging](https://help.getmaintainx.com/about-messaging); [July 2025 update](https://help.getmaintainx.com/help-center-updates/july-2025)
- **Permalinks** to any message work only for logged-in users in the same organization who have access to the conversation. — [About messaging](https://help.getmaintainx.com/about-messaging)
- @mentions send an immediate notification. — [Send messages](https://help.getmaintainx.com/send-messages) (via snippet)
- Message notification options: "Every new message", "Only direct messages and mentions", "Nothing", over in-app (web) or push (mobile). — [Notification settings](https://help.getmaintainx.com/notification-settings)
- Teams, Slack, Google Chat and Discord are connected only through third parties such as Zapier and Pipedream. For example, each new comment on a WO can be forwarded to a Teams channel. — [Zapier Teams](https://zapier.com/apps/maintainx/integrations/microsoft-teams/1572774/send-chat-messages-in-microsoft-teams-for-new-work-orders-in-maintainx)

### Inferences
- For SICOM, the high-value piece is not a general chat (WhatsApp already fills that role) but the **record link**: comments with @mentions on each OT/NC that trigger the bell, a "convert this note into an OT/NC" button (SICOM already has "Nota operador → NC", MIG252), and an automatic post to the crew or workshop when something is assigned.
- An internal chat competes with WhatsApp, and adoption is doubtful. Comments on records with mentions plus notifications are the useful 80%.

### Gaps
- Not documented: asset-level conversations, voice messages in chat, read receipts, native translation, and plan gating for messaging.

## Automations, notifications, escalation and SLA

### Takeaway
MaintainX's native "Workflow Automations" are **meter-centered**. Triggers are threshold conditions on meter readings (11 operators, plus persistence over several readings or a duration). Conditions cover asset status and day/hour windows. Actions are to create a WO, create a request, change asset status (with downtime type) or send an email. They include **anti-repeat throttling** ("Execute at most once every") and an execution history. Native escalation, SLA rules and notification digests were **not found**. Notifications are per-user settings across email, in-app and push, with an overdue alert on mobile.

### Cited Findings
- Structure: one or more triggers, an optional condition and one or more actions. **Premium** includes meter automations that create WOs. **Enterprise** includes custom automations with every condition and action. Not available on Basic or Essential. Automations are configured on the **web only**, by Full Users and Administrators. — [About automations](https://help.getmaintainx.com/about-automations)
- **Meter triggers:**
  - Is above / Is below / Is equal to / Is not equal to / Is above or equal / Is below or equal / Is between;
  - Increases by and Decreases by "(from last trigger)", which show a "Next trigger at" value;
  - Increases by and Decreases by "(from last reading)".
  - Source: [Create an automation](https://help.getmaintainx.com/create-an-automation); [About automations](https://help.getmaintainx.com/about-automations)
- **Persistence ("For")**: "One Reading", "Multiple readings" (for example, more than 5 of the last 10), or "A reading longer than" X minutes or hours. This filters out noisy readings. — [Create an automation](https://help.getmaintainx.com/create-an-automation)
- **Conditions**: "Asset Status" (Online or Offline) and "Between Certain Days and Hours". — [Create an automation](https://help.getmaintainx.com/create-an-automation)
- **Actions:**
  - "Create a Work Order": blank or from a template, with procedures attached; the asset is auto-assigned or set with the {Asset ID} and {Asset Name} variables; the WO can be assigned to a team.
  - "Create a Request": title, description, priority (None, Low, Medium, High), location, asset, asset status and files.
  - "Change Asset Status": status, **Downtime Type** and a note.
  - "Send a Notification": an email with recipients, subject and text, sent as one email to each recipient, optionally including the author.
  - Source: [Create an automation](https://help.getmaintainx.com/create-an-automation); [About automations](https://help.getmaintainx.com/about-automations)
- Limits:
  - up to **250 assets per trigger**;
  - several triggers per automation;
  - **"Execute at most once every"** a set interval, to avoid duplicate WOs.
  - No cap on the number of automations is published.
  - Source: [Create an automation](https://help.getmaintainx.com/create-an-automation)
- **Action History**: counts of runs that executed, failed or were skipped, each with a date and time, and links to the WO created and the asset status. — [About automations](https://help.getmaintainx.com/about-automations)
- Meters are "Manual" (the technician records the reading) or "Automated" (from an integration or sensor, set up with a MaintainX representative or through the REST API). Automated meters have **Threshold Settings**, added in July 2025. Meters from the **legacy IoT feature, including Samsara, cannot use workflow automations**. — [About automations](https://help.getmaintainx.com/about-automations); [July 2025 update](https://help.getmaintainx.com/help-center-updates/july-2025)
- Inspections and failed checklists:
  - Marketing pages say triggers can create WOs, send alerts or assign technicians "based on the information generated by technicians". — [Quality control apps](https://www.getmaintainx.com/quality-control-apps/); [Inspections](https://www.getmaintainx.com/inspections)
  - The community shows a **prompted** corrective WO (the technician is asked) when an item fails Yes/No, and users asking how to automate it. — [Community: follow-up WO](https://community.getmaintainx.com/getting-started-2/prompting-a-follow-up-work-order-489)
- **Notifications (per-user settings, web and mobile):**
  - Channels: email, in-app (web) and push (mobile). SMS is not mentioned.
  - WOs, grouped by WOs I created, WOs assigned to me and WOs assigned to my team: "All new comments" and "Only mentions in comments". Mobile only: **"Work order becomes overdue"**, "Status has changed" and "All assigned work orders".
  - Requests: assigned to my teams, unassigned, and **needing my approval** (push and email by default).
  - POs: those needing my approval (email).
  - Messages: three levels.
  - Reporting: a **weekly WO report by email on Mondays**, enabled through the representative.
  - Requesters can configure only Requests and Messages.
  - Source: [Notification settings](https://help.getmaintainx.com/notification-settings); [Notifications FAQ](https://help.getmaintainx.com/faq-notifications)
- Push and email are configured independently. Some actions do not generate notifications. — [Notifications FAQ](https://help.getmaintainx.com/faq-notifications); [Troubleshooting notifications](https://help.getmaintainx.com/troubleshooting-notifications)
- External automations (Zapier, Make, Zoho Flow) offer triggers such as WO created, WO status updated and asset created, and actions such as create WO, part or user. — [Zoho Flow](https://www.zohoflow.com/apps/maintainx/integrations/)

### Inferences
- Ideas to copy straight into SICOM, whose GPS and horómetro already exist:
  - (1) **Meter rules with persistence**, such as "more than N of the last M readings" or "for longer than X min", to avoid false alarms from GPS readings.
  - (2) **"From last trigger" vs "from last reading"**: "every +250 h since the last time it fired" is a usage-based PM without a calendar.
  - (3) **Throttling ("at most once every X")** plus a **history of run / failed / skipped**, both cheap to build in a rules table with logs.
  - (4) An action that changes asset status with a downtime type, which ties into SICOM's fleet status and reliability.
- The SLA, escalation and digest gaps in MaintainX are an opportunity for SICOM: a digest of the bell by email (daily) and escalation of overdue OT/NC to the supervisor are not in the benchmark.
- The overdue alert existing only on mobile, and the weekly report requiring a request to the vendor, suggest MaintainX's notifications are less polished than its marketing.

### Gaps
- No native escalation rules (overdue X h → notify supervisor), no SLA on response or approval time, and no daily digest were found in the help center.
- The automation triggers cover only meters. No status-change trigger or inspection-result trigger appears in the native workflow documentation. These may exist in Enterprise or in procedures, but no source confirms them.

## Fleet integrations (telematics, IoT, ERP)

### Takeaway
The flagship fleet integration is **Samsara**:
- DVIRs, fault codes and geofence events in real time create requests or WOs.
- Engine hours and odometer sync **daily** into meters (Enterprise).
- **Closing the WO closes the DVIR in Samsara.**

Motive follows the same pattern. No official **Geotab** integration was found. The integrations are built by MaintainX (staging and a consultant), not self-service.

### Cited Findings
- Samsara:
  - Created **in real time**: a WO or request when a DVIR is submitted, carrying all defects and **DVIR photos**; WOs or requests from fault codes, with asset and location context; WOs when entering or leaving a **geofence**.
  - Synced **daily**: engine hours and odometer, into meters for usage-based PMs (Enterprise).
  - When the WO is marked DONE, **the DVIR is closed in Samsara automatically**.
  - Requires a Samsara plan with API access and MaintainX Premium or Enterprise. Meter syncing needs Enterprise.
  - Setup: MaintainX builds it and validates it in staging, with an integration consultant who maps assets and locations through custom fields.
  - Source: [MaintainX–Samsara integration](https://webflow.getmaintainx.com/integrations/samsara); [Samsara Marketplace](https://www.samsara.com/resources/marketplace/maintainx)
- Motive: syncs mileage, engine hours and fault codes, and creates WOs from fault codes. Meters require Enterprise. — [MaintainX–Motive](https://webflow.getmaintainx.com/integrations/motive)
- Legacy IoT meters (Samsara included) do not work with the new workflow automations. New automated meters are created through the REST API. — [About automations](https://help.getmaintainx.com/about-automations)
- Machine and IoT: there is a MachineMetrics integration (page found but not read in detail). — [MachineMetrics](https://webflow.getmaintainx.com/integrations/machine-metrics)
- Geotab: no MaintainX source found. Only competitors claim Geotab support. — [OxMaint](https://oxmaint.com/industries/fleet-management/telematics-cmms-integration-for-fleets-guide)

### Inferences
- Copy the **pattern** of the Samsara integration:
  - a telematics event (fault code, geofence) becomes a request, not a direct WO, so a person filters it;
  - the driver's pre-use inspection with defects becomes a request with photos;
  - closing the WO "closes the loop" with the source system.
- SICOM already has Centinela GPS and horómetro sync from Navixy, Volvo and Renault rFMS. What is missing is the **closing of the loop** and the rule "inspection with defect → request with photos".

### Gaps
- ERP integrations (SAP, NetSuite, etc.) were not investigated in depth because of the call budget. Nothing about Softland.
- The Samsara sync is daily for meters. The latency of other providers is unknown.
