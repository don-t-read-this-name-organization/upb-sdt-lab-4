#import "seq.typ": *

#set document(title: "IT Support Ticketing System", author: "Daria Gladkykh")
#set page(paper: "a4", margin: (x: 2.2cm, y: 2.4cm), numbering: "1", number-align: center)
#set text(size: 11pt, lang: "en")
#set par(justify: true)
#set heading(numbering: "1.1")
#show heading.where(level: 1): it => { pagebreak(weak: true); it; v(0.4em) }
#show raw.where(block: false): set text(size: 0.92em)
#set table(stroke: 0.5pt, inset: 5pt)
#show table.cell.where(y: 0): set text(weight: "bold")
#show figure: set block(breakable: false)

#let fig(path, caption, width: 100%) = figure(image(path, width: width), caption: caption)

#page(numbering: none)[
  #v(1fr)
  #align(center)[
    #text(size: 24pt, weight: "bold")[IT Support Ticketing System]
    #v(0.6em)
    #text(size: 16pt)[Architecture]
    #v(2.5em)
    #text(size: 12pt)[Architecture Katas, Lab 4]
    #v(0.3em)
    #text(size: 12pt)[Daria Gladkykh]
  ]
  #v(1.2fr)
]

#outline(indent: auto, depth: 3)

= Requirements

== Functional requirements
#table(
  columns: (auto, 1fr),
  [ID], [Requirement],
  [FR1], [Employees submit IT support tickets with a title, a description, a category, a priority and optional attachments such as screenshots.],
  [FR2], [Every new ticket is routed automatically to a support team and, when possible, to an available agent of that team.],
  [FR3], [IT staff view the open tickets of their team, sorted by urgency, and change their status, assignee and priority.],
  [FR4], [The status of every ticket is tracked through a defined life cycle (open, in progress, on hold, resolved, closed) and every change is recorded.],
  [FR5], [Employees see the status, the history and the public comments of their own tickets, and are notified when the status changes.],
  [FR6], [Employees and agents exchange comments on a ticket. Agents can also write internal comments that the employee does not see.],
  [FR7], [Every ticket has service level targets for the first response and the resolution. Agents and team leads are warned before a target is missed.],
  [FR8], [Managers view reports on ticket metrics such as response times, resolution times, resolution rates and SLA compliance, and export them.],
  [FR9], [Employees can also open a ticket by e-mail to the helpdesk address, for example when they cannot reach the web application.],
)

== User stories
#table(
  columns: (auto, 1fr, auto),
  [ID], [User story], [Sequence diagram],
  [US1], [As an employee, I want to submit a ticket with my issue details so that IT can resolve my problem.], [@fig-us1],
  [US2], [As IT staff, I want to view open tickets and update their status as I work on them.], [@fig-us2],
  [US3], [As an employee, I want to see the status of my ticket so I know when it's resolved.], [@fig-us3],
  [US4], [As a manager, I want to view reports on ticket metrics so I can monitor IT support performance.], [@fig-us4],
  [US5], [As a team lead, I want to be warned before a ticket misses its SLA so that I can react in time.], [@fig-us5],
)

== Non-functional requirements
#table(
  columns: (auto, 1fr),
  [Area], [Requirement],
  [Availability], [Submitting and viewing tickets is available 99.9% of working hours. A ticket can still be submitted by e-mail when the web application is unreachable.],
  [Consistency], [Two agents working on the same ticket never overwrite each other's change without noticing. No status change is lost.],
  [Responsiveness], [Lists and ticket pages load in under 1 s (95th percentile). A status change is visible to the employee within 5 s.],
  [Accuracy of metrics], [Reports are computed from the full history of status changes and count only working hours, so that a ticket opened on Friday evening is not penalised for the weekend.],
  [Security and privacy], [Login through the company's single sign-on. Authorization is checked by the service that owns the data. All traffic and stored data are encrypted, attachments are scanned for malware, and personal data is handled according to the GDPR.],
  [Auditability], [Every change of status, assignee and priority is stored with its author and time and cannot be edited.],
  [Scalability], [The system handles the load estimated in @sec-load, including a burst of tickets during a company-wide outage, and every component can grow by adding instances.],
)

= Architecture

== Overview
The system is split by business capability into a small number of services. Each service owns its data and its database, and no service reads another service's database. The browser talks to two entry points: the API Gateway for ordinary requests and the Realtime Gateway, which pushes updates to open pages. Login is delegated to the company's identity provider, so the system never sees a password. Attachments never pass through the services; the browser uploads and downloads them directly from object storage with short-lived signed links.

The load of an internal ticketing system is moderate (see @sec-scalability), so the split is not driven by raw traffic. It is driven by three different workloads: the transactional work on tickets, the time-driven work of SLA clocks, and the analytical queries of reports. Separating them keeps a heavy report from slowing down agents, and lets the SLA logic change without touching the ticket model.

@fig-components shows the services, their data stores and how they communicate.

#page(flipped: true)[
  #fig("diagrams/components.pdf", [Component view of the system]) <fig-components>
]

== Services
#table(
  columns: (auto, 1fr, auto),
  [Service], [Responsibility], [Data store],
  [API Gateway], [Single entry point for REST requests. Validates JWTs, applies rate limits and routes requests to services.], [none],
  [Realtime Gateway], [Holds the Server-Sent Events connections of open pages and pushes ticket updates to them.], [Redis],
  [Directory], [Copy of employees, departments and roles, kept in sync with the company identity provider through SCIM.], [PostgreSQL],
  [Ticket], [Tickets, comments, attachments and the history of status changes. Enforces the life cycle of a ticket.], [PostgreSQL, object storage],
  [Routing & SLA], [Support teams and their members, routing rules, SLA policies and the SLA clock of every ticket.], [PostgreSQL],
  [Reporting], [Read model built from ticket events. Computes and serves metrics for managers.], [PostgreSQL (separate)],
  [Notification], [Sends e-mail and Teams messages in reaction to events, according to each employee's preferences.], [PostgreSQL],
  [Email Ingestion], [Reads the helpdesk mailbox and turns e-mails into tickets or into comments on existing tickets.], [none],
)

The SLA logic lives outside the Ticket service because it is driven by time and not by requests. A clock has to fire when a deadline approaches even if nobody touches the ticket, and the rules (business hours, holidays, pauses) change more often than the ticket model.

== Communication
The services use three styles of communication.

+ *REST over HTTPS*, through the API Gateway, covers request and response work such as submitting a ticket, listing tickets, changing a status or loading a report. The Routing & SLA service also calls the Ticket service over REST to assign a ticket.
+ *Server-Sent Events*, through the Realtime Gateway, push changes to open pages: a new ticket in an agent's queue, a status change on an employee's ticket, a new comment. The updates only go from the server to the browser, so SSE is enough and simpler than WebSockets. It runs over ordinary HTTP and reconnects automatically.
+ *Kafka* carries durable domain events such as `TicketCreated`, `TicketStatusChanged` or `SlaBreached`. A service publishes an event without knowing who consumes it. The Ticket service does not know that the Reporting and Notification services exist.

Events are published with the *transactional outbox* pattern. The Ticket service writes the change and the event into the same database transaction, and a relay copies new outbox rows to Kafka. An event is therefore never lost after a commit and never published for a change that was rolled back. Kafka topics are keyed by `ticketId`, so all events of one ticket are consumed in order.

== Technology choices
#table(
  columns: (auto, 1fr),
  [Technology], [Why it is used here],
  [PostgreSQL], [Tickets are relational data with strict rules (life cycle, optimistic locking, audit history). Transactions make the outbox pattern possible, and full-text search over titles and descriptions is built in.],
  [Kafka], [A durable event log. Events of one ticket stay in order, and a new consumer, such as the Reporting service, can rebuild its read model by replaying the history.],
  [Redis], [Registry of open SSE connections and publish/subscribe between Realtime Gateway nodes.],
  [Object storage], [Cheap and durable storage for attachments, accessed with signed links.],
  [OIDC, SCIM and JWT], [The company already manages its employees in Microsoft Entra ID. OIDC gives single sign-on with the company's MFA, SCIM keeps the directory in sync, and signed tokens can be verified by every service on its own.],
  [Server-Sent Events], [One-way push over plain HTTP, with automatic reconnection built into browsers.],
)

== Ticket life cycle
The Ticket service accepts only the transitions shown in @fig-states. Any other change of status is rejected. The life cycle also controls the SLA clocks: the first transition to `IN_PROGRESS` records the first response, `ON_HOLD` pauses the resolution clock while IT waits for the employee, and `RESOLVED` stops it.

#fig("diagrams/ticket-states.pdf", [States of a ticket], width: 100%) <fig-states>

A resolved ticket is not closed at once. The employee can confirm the solution or reopen the ticket within 7 days; after that it closes automatically. The number of reopenings is kept, because a high reopen rate shows tickets that were closed too early.

= Domain model

== Modelling rules
Each service owns its classes. A class never holds an object that belongs to another service; it holds only that object's identifier. A `Ticket` stores a `teamId`, for example, and the `SupportTeam` itself stays in the Routing & SLA service. In the diagrams, solid lines are associations inside one service. Dashed arrows marked «ref by ID» are references across services. Classes that belong to another service appear in grey with the stereotype «external» and without their members.

#fig("diagrams/class-overview.pdf", [Overview of the domain classes, grouped by service], width: 92%) <fig-overview>

== Directory service
#fig("diagrams/class-directory.pdf", [Classes of the Directory service], width: 62%)

`Employee.externalId` is the identifier of the user in the company identity provider. Roles are not managed in the ticketing system: they are derived from groups in the identity provider (for example the group _IT-Support-Network_ gives the role `AGENT`), so access is granted and removed in one place. When an employee leaves the company, SCIM deactivates the account and the Directory service publishes `EmployeeDeactivated`.

== Ticket service
#fig("diagrams/class-ticket.pdf", [Classes of the Ticket service], width: 88%) <fig-class-ticket>

`Ticket` is the aggregate root. Comments, status changes and attachments are only created through its methods, so the rules of the life cycle cannot be bypassed. `changeStatus` checks three things: that the transition is allowed by `canTransition`, that the user may make it, and that `expectedVersion` equals the current `version`. Every successful change increments `version` and appends a `StatusChange`, which is never updated or deleted and forms the audit trail.

`number` is a readable identifier such as `IT-2026-004512`, used in e-mails and phone calls. `resolutionDueAt` is a copy of the deadline owned by the Routing & SLA service; it is stored here only to sort the agents' queue without a call to another service.

An `Attachment` is created in the state `PENDING`. A malware scanner checks every uploaded file and sets `scanStatus`; agents can download a file only when it is `CLEAN`.

== Routing & SLA service
#fig("diagrams/class-routing.pdf", [Classes of the Routing & SLA service]) <fig-class-routing>

Routing rules are evaluated in the order given by `RoutingRule.order`; the first rule that matches the category and priority of a ticket decides the team. Inside the team the ticket goes to the available member with the fewest open tickets, unless everyone has reached `maxOpenTickets`, in which case the ticket stays in the team queue.

`SlaPolicy` gives the targets for each priority:

#table(
  columns: (auto, auto, auto, auto),
  [Priority], [First response], [Resolution], [Clock],
  [CRITICAL], [15 min], [4 h], [24/7],
  [HIGH], [1 h], [8 working hours], [working hours],
  [MEDIUM], [4 working hours], [3 working days], [working hours],
  [LOW], [1 working day], [5 working days], [working hours],
)

`SlaClock` stores deadlines and not a running counter, so nothing needs to be updated every second. A pause adds the paused time to `pausedTotal` and moves the deadlines by the same amount when the clock resumes. `BusinessCalendar.add` skips nights, weekends and public holidays.

== Reporting service
#fig("diagrams/class-reporting.pdf", [Classes of the Reporting service], width: 80%) <fig-class-reporting>

The Reporting service keeps a read model optimised for queries, separate from the operational data (CQRS). `TicketFact` is one row per ticket, updated by every event about that ticket. `DailyTeamMetric` holds pre-computed values per team and day, so a report over a year reads a few thousand rows instead of every ticket. `ProcessedEvent` makes the consumer idempotent: an event delivered twice by Kafka is recognised by its `eventId` and ignored.

=== Definitions of the metrics
Let $c_i$ be the creation time of ticket $i$, $f_i$ the time of its first response, $r_i$ the time it was last resolved and $p_i$ the total time it spent on hold. All durations are measured in working time.

$ "first response time"_i = f_i - c_i $
$ "resolution time"_i = r_i - c_i - p_i $
$ "resolution rate" = "tickets resolved in the period" / "tickets created in the period" $
$ "SLA compliance" = "tickets resolved before their deadline" / "tickets with a resolution deadline in the period" $
$ "reopen rate" = "tickets reopened at least once" / "tickets resolved in the period" $

Response and resolution times are reported as the median and the 90th percentile and not as the mean, because a few tickets that wait weeks for a spare part would otherwise dominate the average.

== Notification service
#fig("diagrams/class-notification.pdf", [Classes of the Notification service], width: 75%)

`DeliveryLog` records every message sent. Before sending, the service checks the log for the same `eventId` and recipient, so a redelivered event does not send a second e-mail. Failed deliveries are retried with an increasing delay.

= Behaviour

== Concurrency on a ticket
Several agents can open the same ticket at once, for example a team lead and the assignee. The Ticket service uses optimistic concurrency control. Every request that changes a ticket carries the `version` the user saw, and the update is executed as

```sql
UPDATE tickets SET status = $1, version = version + 1
WHERE id = $2 AND version = $3
```

If another change happened in the meantime, no row is updated and the user gets `409 Conflict` with the current ticket, so they decide again with the latest information. No lock is held while a person thinks, and no change is silently overwritten.

The same version number lets clients detect missed updates. A page that receives an update with a version that skips a number reloads the ticket instead of applying the update.

== Sequence diagrams

=== Submitting a ticket
#figure(
  seq(
    ("Employee", "Web Client", "API\nGateway", "Ticket\nService", "Ticket DB", "Object\nStorage", "Kafka", "Routing\n& SLA", "Notification"),
    (
      msg(0, 1, "fills in the form, attaches a screenshot"),
      msg(1, 2, "POST /attachments\n{fileName, size, type}"),
      msg(2, 3, "validate JWT, forward"),
      self(3, "check type and size <= 20 MB"),
      msg(3, 4, "INSERT attachment (PENDING)"),
      ret(3, 1, "201 {attachmentId, uploadUrl (5 min)}"),
      msg(1, 5, "PUT file (signed URL)"),
      ret(5, 1, "200"),
      msg(1, 2, "POST /tickets {title, description,\ncategory, priority, attachmentIds}"),
      msg(2, 3, "forward, requesterId = token.sub"),
      self(3, "validate, assign number"),
      msg(3, 4, "BEGIN; INSERT ticket (OPEN, v1);\nlink attachments; INSERT outbox\nTicketCreated; COMMIT"),
      ret(3, 1, "201 {id, number IT-2026-004512, OPEN}"),
      ret(1, 0, "shows ticket number"),
      msg(4, 6, "outbox relay: TicketCreated"),
      group("par", "consumers", a: 6, b: 8),
      msg(6, 7, "TicketCreated"),
      self(7, "match rule, pick least\nloaded agent, start SLA clock"),
      msg(7, 3, "PUT /tickets/{id}/assignment\n{teamId, assigneeId, dueAt}"),
      msg(3, 4, "UPDATE ticket; outbox TicketAssigned"),
      ret(3, 7, "200"),
      otherwise("notification"),
      msg(6, 8, "TicketCreated, TicketAssigned"),
      self(8, "confirmation e-mail to the\nemployee, Teams message to agent"),
      end(),
    ),
  ),
  caption: [Submitting a ticket (US1)],
) <fig-us1>

The employee gets the ticket number as soon as the ticket is stored; routing and notifications happen afterwards, through events. If the Routing & SLA service is down for a moment, tickets are still accepted and are routed when it comes back, because `TicketCreated` stays in Kafka.

The assignment call carries the event identifier as an idempotency key, so a retried call does not assign the ticket twice. The attachment is uploaded before the ticket is created, so the large file never passes through the gateway and the ticket request stays small.

=== Working on tickets
#figure(
  seq(
    ("IT Agent", "Web Client", "API\nGateway", "Ticket\nService", "Ticket DB", "Kafka", "Routing\n& SLA", "Realtime\nGateway", "Notification"),
    (
      msg(0, 1, "opens team queue"),
      msg(1, 2, "GET /tickets?status=OPEN,IN_PROGRESS\n&team=mine&sort=resolutionDueAt"),
      msg(2, 3, "forward"),
      self(3, "role AGENT, member of team"),
      msg(3, 4, "SELECT ... ORDER BY due LIMIT 50"),
      ret(3, 1, "200 [tickets, SLA due times]"),
      msg(0, 1, "opens IT-2026-004512, Start work"),
      msg(1, 2, "PATCH /tickets/{id}/status\n{to: IN_PROGRESS, expectedVersion: 2}"),
      msg(2, 3, "forward"),
      self(3, "canTransition(OPEN to IN_PROGRESS)"),
      group("alt", "version is still 2", a: 1, b: 4),
      msg(3, 4, "BEGIN; UPDATE ... WHERE version = 2;\nINSERT status_change; set firstRespondedAt;\nINSERT outbox TicketStatusChanged; COMMIT"),
      ret(3, 1, "200 {status IN_PROGRESS, version 3}"),
      otherwise("someone else changed the ticket"),
      ret(3, 1, "409 Conflict {current ticket}"),
      ret(1, 0, "shows the other change"),
      end(),
      msg(4, 5, "outbox relay: TicketStatusChanged"),
      group("par", "consumers", a: 5, b: 8),
      msg(5, 6, "TicketStatusChanged"),
      self(6, "recordFirstResponse"),
      msg(5, 7, "TicketStatusChanged"),
      self(7, "push to requester's pages"),
      msg(5, 8, "TicketStatusChanged"),
      self(8, "e-mail to employee"),
      end(),
    ),
  ),
  caption: [An agent views the queue and changes the status of a ticket (US2)],
) <fig-us2>

The queue is sorted by the resolution deadline, so the most urgent ticket is on top. Resolving the ticket later follows the same flow with `to: RESOLVED` and a mandatory resolution note, and the Routing & SLA service stops the resolution clock.

=== Following the status of a ticket
#figure(
  seq(
    ("Employee", "Web Client", "API\nGateway", "Ticket\nService", "Ticket DB", "Kafka", "Realtime\nGateway", "Redis"),
    (
      msg(0, 1, "opens My tickets"),
      msg(1, 2, "GET /me/tickets"),
      msg(2, 3, "forward"),
      msg(3, 4, "SELECT ... WHERE requester_id = token.sub"),
      ret(3, 1, "200 [tickets]"),
      msg(1, 2, "GET /tickets/{id}"),
      msg(2, 3, "forward"),
      self(3, "canView: requester or agent;\nhide INTERNAL comments"),
      ret(3, 1, "200 {ticket, history, public comments, v3}"),
      msg(1, 6, "GET /events (SSE, access token)"),
      msg(6, 7, "register connection for user"),
      divider("later: the agent resolves the ticket"),
      msg(5, 6, "TicketStatusChanged {ticketId, requesterId, RESOLVED, v4}"),
      msg(6, 7, "find connections of requesterId"),
      msg(6, 1, "event: ticket-updated {RESOLVED, v4}"),
      group("alt", "version = local + 1", a: 1, b: 3),
      self(1, "apply update"),
      otherwise("an update was missed"),
      msg(1, 3, "GET /tickets/{id} (via gateway)"),
      end(),
      ret(1, 0, "shows Resolved and the resolution note"),
      group("alt", "problem solved", a: 0, b: 3),
      msg(1, 3, "PATCH status {to: CLOSED} (via gateway)"),
      otherwise("problem is back"),
      msg(1, 3, "PATCH status {to: IN_PROGRESS, reason}"),
      self(3, "reopenCount + 1"),
      end(),
    ),
  ),
  caption: [An employee follows the status of a ticket (US3)],
) <fig-us3>

The employee is informed in three ways: the open page updates immediately through SSE, an e-mail is sent by the Notification service, and the list of tickets shows the current status whenever it is loaded. If the Realtime Gateway is down, the e-mail and the list still work.

=== Viewing reports
#figure(
  seq(
    ("Manager", "Web Client", "API\nGateway", "Reporting\nService", "Reporting DB", "Kafka"),
    (
      group("loop", "for every ticket event", a: 3, b: 5),
      msg(5, 3, "TicketCreated / StatusChanged / SlaBreached"),
      msg(3, 4, "BEGIN; INSERT processed_event (skip if exists);\nUPSERT ticket_fact; COMMIT"),
      end(),
      self(3, "every night: aggregate yesterday\ninto daily_team_metric"),
      divider("the manager opens the dashboard"),
      msg(0, 1, "opens IT performance, last quarter"),
      msg(1, 2, "GET /reports/summary?from&to&teams"),
      msg(2, 3, "forward"),
      self(3, "authorize: MANAGER sees own\ndepartment, ADMIN sees all"),
      msg(3, 4, "SELECT from daily_team_metric (past days)"),
      msg(3, 4, "SELECT from ticket_fact (today)"),
      self(3, "merge, compute rates and percentiles"),
      ret(3, 1, "200 {created, resolved, resolution rate,\nmedian first response, p90 resolution,\nSLA compliance, reopen rate, backlog by age}"),
      ret(1, 0, "charts and trend per team"),
      msg(0, 1, "Export"),
      msg(1, 3, "GET /reports/summary.csv (via gateway)"),
      ret(3, 1, "200 text/csv"),
    ),
  ),
  caption: [A manager views reports on ticket metrics (US4)],
) <fig-us4>

Reports never query the Ticket database, so a report over a whole year does not slow down agents. The cost is that today's numbers lag a few seconds behind the operational data, which is irrelevant for a performance report. If the definition of a metric changes, the read model is rebuilt by replaying the events from Kafka.

=== SLA warning and breach
#figure(
  seq(
    ("Routing & SLA\nscheduler", "Routing DB", "Kafka", "Ticket\nService", "Notification", "Agent /\nTeam lead"),
    (
      group("loop", "every minute", a: 0, b: 5),
      msg(0, 1, "SELECT clocks RUNNING with due < now + 20%\nFOR UPDATE SKIP LOCKED"),
      group("alt", "80% of the time used, not yet notified", a: 0, b: 5),
      msg(0, 1, "set atRiskNotified"),
      msg(0, 2, "SlaAtRisk {ticketId}"),
      msg(2, 4, "SlaAtRisk"),
      msg(4, 5, "Teams message to the assignee"),
      otherwise("deadline passed"),
      msg(0, 1, "state = BREACHED"),
      msg(0, 2, "SlaBreached {ticketId}"),
      msg(2, 3, "SlaBreached"),
      self(3, "mark ticket, raise priority one level"),
      msg(2, 4, "SlaBreached"),
      msg(4, 5, "e-mail and Teams to the team lead"),
      end(),
      end(),
    ),
  ),
  caption: [Warning before and escalation after a missed SLA (US5)],
) <fig-us5>

`FOR UPDATE SKIP LOCKED` lets several instances of the scheduler run at once without handling the same clock twice. The scheduler only reads the index of deadlines, so its cost does not depend on the total number of tickets.

= Security and privacy

== Authentication
Employees log in through the company identity provider with OpenID Connect, using the same account and multi-factor authentication as for every other company application. The ticketing system stores no passwords.

After login the browser receives an access token, a JWT valid for 15 minutes, signed by the identity provider. Every service verifies it with the provider's public key without calling it. The token carries the user's identifier and roles. A refresh token is kept in an `HttpOnly`, `Secure`, `SameSite=Strict` cookie that JavaScript cannot read. The SSE connection is authenticated with the access token when it opens and closed when the token expires.

Because accounts come from the identity provider, an employee who leaves the company loses access immediately everywhere, and IT staff who move to another team lose their old permissions without anyone having to remember them.

== Authorization
The API Gateway only establishes who the user is. Whether the user may do something is decided by the service that owns the data. The user's identity always comes from the verified token and never from the request body or URL, so a user cannot act as someone else by changing an identifier. Every lookup of a ticket by identifier also checks that the user may see it, which prevents reading other people's tickets by guessing numbers.

#table(
  columns: (1fr, 1fr, auto),
  [Action], [Allowed for], [Checked by],
  [Submit a ticket], [any employee], [Ticket],
  [View a ticket and its public comments], [the requester, agents of the assigned team, team leads, admins], [Ticket],
  [View internal comments], [agents, team leads, admins], [Ticket],
  [Change status, priority, assignee], [agents of the assigned team, team leads], [Ticket],
  [Confirm or reopen a resolved ticket], [the requester], [Ticket],
  [Download an attachment], [anyone who may view the ticket, and only if the file is clean], [Ticket],
  [Edit routing rules and SLA policies], [admins], [Routing & SLA],
  [View reports], [managers for their department, team leads for their team, admins for all], [Reporting],
)

== Data in transit and at rest
All traffic between browsers and the system uses TLS. The services run in a private network and talk to each other over mutual TLS. Databases, object storage, Kafka and backups are encrypted on disk. Secrets such as database passwords and API keys for the mail server live in a secrets manager and never in source code or container images.

The attachment bucket is private. Files are uploaded and downloaded only through signed links valid for 5 minutes, and they are served from a separate domain with `Content-Disposition: attachment`, so a malicious HTML or SVG file can never run in the context of the application.

The audit trail (`StatusChange`) is append-only: the database user of the Ticket service has no right to update or delete those rows.

== Common attacks
#table(
  columns: (1fr, 1.6fr),
  [Attack], [Protection],
  [Script injection through a description or comment (XSS)], [Text is stored as written and rendered as sanitized Markdown with an allow-list of tags. A strict Content Security Policy forbids inline scripts.],
  [SQL injection], [Only parameterized queries are used.],
  [Malicious attachments], [Allow-list of file types, a size limit of 20 MB, a malware scan before any download, and delivery from a separate domain.],
  [Reading someone else's ticket by changing its number (IDOR)], [The Ticket service checks `canView` for every ticket it returns, including in lists and searches.],
  [Phishing through the e-mail channel], [The Email Ingestion service accepts e-mails only from company domains with valid SPF and DKIM, and links in ticket e-mails always point to the application, never to attachments.],
  [Spam and flooding], [Rate limits on the gateway, for example at most 20 new tickets per user per hour.],
  [Passwords pasted into tickets], [The form warns when the text looks like a password, and agents can redact a comment. Redaction is recorded in the audit trail.],
)

== GDPR
Tickets contain personal data of employees (name, e-mail, department, and whatever they describe in the ticket), so the system falls under the GDPR. The legal basis is the legitimate interest of the employer in running IT support. All data is stored in an EU region.

The system collects only what support needs: identity and department come from the directory, and the form has no fields for private data. Reports for managers show teams and categories; figures per agent are visible only to the agent's own team lead.

Employees can view all their tickets at any time and download them as a file. When an employee leaves, their account is deactivated through SCIM; their closed tickets are kept for the retention period and then pseudonymized: the name and e-mail are replaced by an identifier, while the technical content and the metrics remain.

#table(
  columns: (1fr, auto),
  [Data], [Retention],
  [Tickets, comments and history], [3 years after closing, then pseudonymized],
  [Attachments], [1 year after the ticket is closed],
  [Reporting read model], [pseudonymized identifiers only, 5 years],
  [Notification delivery log], [90 days],
  [Application logs (pseudonymous user identifier)], [90 days],
)

= Scalability <sec-scalability>

== Load estimate <sec-load>
The estimate starts from a company with the following size.

#table(
  columns: (1fr, auto),
  [Assumption], [Value],
  [Employees], [20,000],
  [IT agents], [150],
  [Tickets per employee per month], [1],
  [Working days per month], [21],
  [Share of the daily load in the busiest hour], [15%],
)

#table(
  columns: (1fr, 1fr, auto),
  [Load], [Calculation], [Result],
  [New tickets per working day], [20,000 / 21], [≈ 950],
  [New tickets in the busiest hour], [950 × 15%], [≈ 145 / h],
  [Burst during a company-wide outage], [2,000 tickets in 15 min], [≈ 2.2 / s],
  [Queue refreshes by agents], [150 agents × 1 per 30 s], [≈ 5 / s],
  [Status checks by employees], [20,000 × 5 per day, in 8 h], [≈ 3.5 / s],
  [Open SSE connections at peak], [25% of employees and all agents], [≈ 5,000],
  [Tickets per year], [950 × 250 days], [≈ 240,000],
  [Attachments per year], [30% of tickets × 1.5 MB], [≈ 110 GB],
)

The average load is small. The real challenges are elsewhere: the burst of tickets during an outage, when the system matters most and many people submit the same problem at once; report queries over years of data, which must not slow down agents; and growth if the system is later offered to several companies.

== Scaling each component
#table(
  columns: (1fr, 2fr),
  [Component], [Strategy],
  [API Gateway, Ticket, Routing & SLA, Reporting, Notification, Directory], [Stateless. More instances run behind the load balancer, and Kubernetes adds them automatically based on CPU use or request rate. Two instances is the minimum for availability.],
  [Realtime Gateway], [Stateless, since connections are registered in Redis. One node holds tens of thousands of SSE connections, so two nodes are enough for availability and capacity.],
  [PostgreSQL (tickets)], [One primary with two replicas in different availability zones. Lists and searches read from replicas; changes go to the primary. At 240,000 tickets a year one database is enough for many years. A multi-company version would partition the tables by `tenantId`.],
  [Reporting], [Separate database, so analytical queries never touch the ticket database. Pre-aggregated daily metrics keep queries over long periods fast. If data grows by orders of magnitude, the read model can move to a column store such as ClickHouse without changing any other service.],
  [Kafka], [Three brokers with replication factor 3. Topics are partitioned by `ticketId`; 6 to 12 partitions leave room for more consumer instances.],
  [Object storage], [Scales on its own. Old attachments move to a cheaper storage class.],
  [Outage burst], [The submit path is short (one insert and one outbox row). Routing and notifications are asynchronous, so a burst only makes queues in Kafka longer for a minute. Agents can link duplicate tickets to one major incident and resolve them together, and a banner on the form announces known outages so that fewer duplicates are created.],
)

#fig("diagrams/deployment.pdf", [Deployment and scaling of the system], width: 80%) <fig-deployment>

== Resilience
#table(
  columns: (1fr, 1fr, 1.3fr),
  [Failure], [Effect], [Handling],
  [The company network or the main web application is down], [Employees cannot reach the form], [The system runs in a cloud region outside the company data centre, and tickets can be submitted by e-mail to the helpdesk address.],
  [A Ticket service instance crashes], [None visible], [Other instances take over; the load balancer removes the failed one.],
  [The PostgreSQL primary fails], [About 30 s without changes], [Automatic failover to a replica in another zone. Reads continue from the replicas.],
  [Routing & SLA is down], [New tickets are not assigned for a while], [Tickets are stored anyway; `TicketCreated` waits in Kafka and is processed when the service returns. Deadlines are computed from the creation time, so SLA clocks are still correct.],
  [Notification or the mail server is down], [E-mails arrive late], [Events stay in Kafka and deliveries are retried. The application and SSE still show the current status.],
  [Realtime Gateway is down], [Pages do not update by themselves], [The browser reconnects with backoff and reloads the ticket; loading pages still works.],
  [A Kafka consumer falls behind], [Reports and notifications are late], [Nothing is lost; the consumer catches up. Lag is monitored.],
)

== Monitoring
The system tracks technical and business metrics side by side. Technical metrics are request latency and error rate per endpoint, outbox lag (the time from commit to publication in Kafka), Kafka consumer lag, the number of SSE connections and database replication lag. Business metrics are the number of tickets per hour compared to the usual value for that hour, which detects company-wide outages early, the number of tickets waiting without an assignee, and the number of SLA clocks at risk. An alert on unusually many new tickets of one category often shows an incident before anyone reports it as such.
