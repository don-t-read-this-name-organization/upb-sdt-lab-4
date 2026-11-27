#set document(
  title: "Online Food Delivery Service",
  author: "Roi Bachynskyi",
)
#set page(paper: "a4", margin: 2.5cm, numbering: "1")
#set text(font: "New Computer Modern", size: 11pt, lang: "en")
#set par(justify: true, leading: 0.65em)
#set heading(numbering: "1.1")
#show heading.where(level: 1): it => { pagebreak(weak: true); it; v(0.4em) }
#show link: it => underline(text(fill: rgb("#1a4f8b"), it))
#show raw.where(block: false): set text(size: 0.95em)
#show figure.caption: set text(size: 9.5pt)
#set table(inset: 6pt, stroke: 0.5pt + luma(160))
#show table.cell.where(y: 0): set text(weight: "bold")

#let diagram(path, caption, width: 100%) = figure(
  image(path, width: width),
  caption: caption,
)

#align(center + horizon)[
  #text(20pt, weight: "bold")[Online Food Delivery Service]
  #v(6pt)
  #text(13pt)[Architecture]
  #v(24pt)
]
#pagebreak()
#outline(indent: auto)

// ============================================================
= Requirements
// ============================================================

== Functional requirements

#table(
  columns: (auto, 1fr),
  table.header([ID], [Requirement]),
  [FR1], [Customers can browse restaurants and menus, place orders and pay
          for them.],
  [FR2], [Customers can follow the status of their order and the position
          of the courier in real time.],
  [FR3], [Restaurants can accept or reject orders and update their
          status.],
  [FR4], [The system assigns a courier to each order based on proximity
          and availability.],
  [FR5], [The system stays secure and responsive under high-concurrency
          traffic at peak times.],
  [FR6], [Customers can cancel an order until the restaurant accepts it.],
  [FR7], [Administrators can approve or suspend restaurants and couriers
          and issue refunds.],
)

FR1 to FR5 come from the assignment. FR6 and FR7 follow from decisions made
during the design: someone has to decide which restaurants and couriers may
use the platform, and customers need a way out of an order the restaurant
has not started on.

== User stories

#table(
  columns: (auto, 1fr, auto),
  table.header([ID], [User story], [Sequence diagram]),
  [US1], [As a customer, I want to see nearby restaurants and their menus
          so I can choose where to order from.], [@seq-browse],
  [US2], [As a customer, I want to place an order and see the expected
          delivery time so I know when my food will arrive.],
          [@seq-place-order],
  [US3], [As a restaurant owner, I want to receive and update order
          statuses so I can keep customers informed.],
          [@seq-restaurant-status],
  [US4], [As a delivery agent, I want to see my assigned orders and
          navigate efficiently to deliver food on time.], [@seq-dispatch],
  [US5], [As a customer, I want to pay securely for my order.],
          [@seq-payment],
)

Two more flows are described because the user stories depend on them: live
tracking of the courier (@seq-tracking) and the compensation that runs when
a restaurant rejects an order (@seq-reject).

== Non-functional requirements

#table(
  columns: (auto, 1fr),
  table.header([Area], [Requirement]),
  [Peak load], [About 30 new orders per second at lunch and dinner, and
    about 300 per second during a flash promotion (@scalability).],
  [Real time], [Status changes reach the customer within a few seconds. The
    courier's position on the map is at most about 5 seconds old.],
  [Response times], [A restaurant has 3 minutes to accept an order and a
    courier has 30 seconds to accept an offer.],
  [Payment security], [Card data never reaches the platform's servers, and
    no customer is ever charged twice for the same order.],
  [Availability], [Orders that are already placed keep progressing when a
    supporting service, such as notifications or the maps provider, is
    down.],
  [Privacy], [Personal data is handled according to the GDPR and stored in
    the EU. A courier's location is collected only while they are online.],
)

// ============================================================
= Architecture
// ============================================================

== Overview

The system is split by business capability, and each service owns its data
and its database. Four kinds of clients use it: the customer web app, the
restaurant dashboard, the courier app and the administration console. They
reach the backend through the API Gateway for ordinary requests and through
the Realtime Gateway for live updates. Payments and maps are handled by
external providers.

#diagram("diagrams/architecture.svg",
  [Component view of the system]) <fig-arch>

== Clients

#table(
  columns: (auto, auto, 1fr),
  table.header([Client], [Used by], [Main features]),
  [Customer web app], [customers], [browsing, ordering, payment, live
    tracking on a map],
  [Restaurant dashboard], [restaurant owners and staff], [incoming orders,
    status updates, menu management],
  [Courier app], [couriers], [going online and offline, delivery
    offers, navigation, sending the GPS position],
  [Administration console], [platform administrators], [approving
    restaurants and couriers, refunds],
)

== ServicesThe platform stays
out of almost all of PCI DSS

#table(
  columns: (auto, 1fr, auto),
  table.header([Service], [Responsibility], [Data store]),
  [API Gateway], [Entry point for REST requests. Validates JWTs, applies
    rate limits and admission control, routes requests.], [Redis (rate
    limits)],
  [Realtime Gateway], [WebSocket connections to all clients: order status,
    courier position, new orders, delivery offers.], [Redis],
  [Identity], [Login and roles: customer, restaurant staff, courier,
    administrator.], [PostgreSQL],
  [Customer], [Customer profiles and delivery addresses.], [PostgreSQL],
  [Restaurant & Menu], [Restaurants, opening hours, staff, menus, prices,
    availability, approval.], [PostgreSQL, Redis cache],
  [Discovery], [Search for restaurants near an address.], [OpenSearch],
  [Order], [Carts, the order lifecycle and the saga that coordinates
    it.], [PostgreSQL, Redis (carts)],
  [Payment], [Authorization, capture, void and refund through the payment
    provider.], [PostgreSQL (isolated)],
  [Courier], [Courier profiles, vehicles and approval.], [PostgreSQL],
  [Dispatch], [Choosing a courier for each order and sending offers.],
    [Redis GEO, PostgreSQL],
  [Courier Location], [Receiving GPS updates and streaming them to the
    customer.], [Redis GEO, PostgreSQL],
  [ETA], [Estimating the delivery time.], [Redis cache],
  [Notification], [Push messages, SMS and e-mail.], [none],
)

There is no separate administration service. Administrative actions are
operations on the data they change, such as approving a restaurant in the
Restaurant & Menu service or refunding a payment in the Payment service,
and they require the administrator role.

The Courier service and the Dispatch service both deal with couriers, but
with data that changes at very different speeds. A courier's profile
changes a few times a year, while availability and position change every
few seconds. Keeping them apart lets Dispatch hold only fast-changing data
in Redis.

== Communication

REST over HTTPS, through the API Gateway, is used for browsing, the cart,
placing orders, payments and menu management.

WebSocket connections, through the Realtime Gateway, carry live data: status
changes and the courier's position for the customer, new orders for the
restaurant, and delivery offers for the courier. The courier app also sends
its GPS position over the same connection.

Kafka carries domain events such as `OrderPlaced`, `OrderAccepted`,
`CourierAssigned` and `OrderDelivered`. Order events use the order
identifier as their key, so all events of one order are consumed in the
order they were produced.

== The order lifecycle

An order goes through several services and involves three people: the
customer, the restaurant staff and the courier. The Order service
coordinates the whole process as a saga:

+ The customer places the order and the payment provider authorizes the
  amount. The money is reserved but not taken.
+ The restaurant accepts the order within 3 minutes and starts cooking. If
  it rejects the order or does not answer, the authorization is voided.
+ Shortly before the food is ready, Dispatch looks for a courier.
+ The courier picks the food up and delivers it.
+ After delivery, the payment is captured.

The saga is orchestrated: the Order service sends a command for each step
and waits for the event that reports its outcome. The alternative,
choreography, lets each service react to the previous service's event with
no central coordinator. Orchestration was chosen because the whole flow is
visible in one place, which makes it easier to follow, test and change.
@behaviour describes the saga in detail.

Orders are offered to one courier at a time. Sending an offer to several
couriers at once would assign orders faster, but it makes couriers race each
other for every order, and the one with the fastest phone tends to win.

== Technology choices

#table(
  columns: (auto, 1fr),
  table.header([Technology], [Why it is used here]),
  [PostgreSQL], [Orders, payments and restaurant data need transactions and
    strong consistency. Each service has its own database.],
  [Redis], [Carts, caches, rate limits, and the positions and availability
    of couriers. Its GEO commands find the couriers near a point quickly.],
  [OpenSearch], [Full-text and geographic search over restaurants, with
    filters such as "open now".],
  [Kafka], [Durable domain events, kept in order per order, which new
    consumers can replay.],
  [CDN], [Static application files, restaurant images and versioned menus,
    served close to the user.],
  [Payment provider], [Card entry, 3-D Secure and the movement of money.],
  [Maps provider], [Geocoding addresses, travel times and routes.],
)

// ============================================================
= Domain model
// ============================================================

== Modelling rules

Each service owns its classes. A class never holds an object from another
service, only its identifier: an `Order` stores a `restaurantId` and the
Restaurant itself stays in the Restaurant & Menu service. In the diagrams,
solid lines are associations within one service and dashed arrows marked
`«ref by ID»` are references across services. Classes of other services are
grey, marked `«external»` and shown without members.

Small values such as `GeoPoint` and `Money` are value objects. Every service
that needs them has its own copy of the type, so no service depends on a
shared library.

#diagram("diagrams/class-overview.svg",
  [Overview of the domain classes, grouped by service]) <fig-class-overview>

== Identity service

#diagram("diagrams/class-identity.svg",
  [Classes of the Identity service], width: 65%) <fig-class-identity>

Every account has exactly one role. Restaurant staff also get the identifier
of their restaurant in the access token, so other services can check that a
staff member works for the restaurant of an order without asking another
service.

== Customer service

#diagram("diagrams/class-customer.svg",
  [Classes of the Customer service], width: 70%) <fig-class-customer>

An address is geocoded with the maps provider when the customer saves it.
Its coordinates are used to find restaurants that deliver there and to
estimate travel times.

== Restaurant & Menu service

#diagram("diagrams/class-restaurant.svg",
  [Classes of the Restaurant & Menu service]) <fig-class-restaurant>

A new restaurant starts in `PENDING_APPROVAL` and becomes visible to
customers only after an administrator approves it.

Prices are stored as `Money` in minor units, as a whole number of bani,
because floating-point numbers cannot represent amounts such as 0.10
exactly.

`maxActiveOrders` describes the kitchen's capacity. When a restaurant
reaches it, `hasCapacity` returns false and the restaurant appears as busy.
This protects the kitchen and the accuracy of delivery estimates during
peaks.

The menu has a version that increases with every change. The version is
part of the menu's URL, so the CDN can cache a menu for a long time and a
change simply produces a new address.

== Discovery service

#diagram("diagrams/class-discovery.svg",
  [Classes of the Discovery service], width: 75%) <fig-class-discovery>

`RestaurantDocument` is a read model: a copy of restaurant data shaped for
searching and rebuilt from the events of the Restaurant & Menu service. A
restaurant is found only if the customer's address lies within its delivery
radius.

== Order service

#diagram("diagrams/class-order.svg",
  [Classes of the Order service]) <fig-class-order>

The cart lives in Redis, since it changes often and does not matter once the
order is placed or abandoned.

When an order is placed, the name and price of each item are copied into
`OrderItem`, and the delivery address into `AddressSnapshot`. A later change
to the menu or to the customer's address does not alter an order that has
already been placed or its receipt.

`Order` holds the state the customer sees. `OrderSaga` holds the
orchestrator's internal state: the current step and the deadline for that
step. Both are stored in the same database, so the saga survives a restart
of the service.

The saga advances when it receives a domain event. A domain event records a
business fact that has already happened, such as `PaymentAuthorized` or
`OrderAccepted`, and never changes after it is published. A command such as
`AuthorizePayment` is a request that can still fail. The saga stores the
identifiers of the events it has processed, so a duplicate delivered by
Kafka has no effect.

#diagram("diagrams/order-states.svg",
  [States of an order], width: 85%) <fig-order-states>

`Order.canTransition` allows exactly the transitions in @fig-order-states.
A request that does not match one of them, such as marking an order ready
before it was accepted, is rejected.

== Payment service

#diagram("diagrams/class-payment.svg",
  [Classes of the Payment service]) <fig-class-payment>

Every payment carries an idempotency key. If a request to the payment
provider is retried after a network error, the provider recognizes the key
and does not charge the customer a second time.

`LedgerEntry` is append-only. Movements of money are never updated or
deleted; a correction is a new entry. The full history of every payment can
therefore always be audited. A refund can be requested only by an
administrator.

== Courier service

#diagram("diagrams/class-courier.svg",
  [Classes of the Courier service], width: 60%) <fig-class-courier>

Like a restaurant, a courier starts in `PENDING_APPROVAL` and receives
offers only after approval.

== Dispatch service

#diagram("diagrams/class-dispatch.svg",
  [Classes of the Dispatch service]) <fig-class-dispatch>

A `DeliveryJob` is the search for a courier for one order. It sends one
`Offer` at a time and remembers which couriers declined, so nobody is
offered the same order twice.

`reserveForOffer` switches a courier from `AVAILABLE` to `OFFERED` in a
single atomic Redis operation. Two jobs looking for a courier at the same
moment can never both offer to the same person.

== Courier Location and ETA services

#diagram("diagrams/class-location-eta.svg",
  [Classes of the Courier Location and ETA services]) <fig-class-location>

`CourierPosition` holds only the latest known position of each courier.
`TrackingLink` decides when a customer may see that position, which is only
between pickup and delivery. `DeliveryTrace` stores the route of each
delivery for 30 days to settle disputes and is then deleted.

`EtaEstimate` splits the estimate into its parts: remaining preparation
time, the courier's travel time to the restaurant, travel time to the
customer and a safety buffer.

// ============================================================
= Behaviour <behaviour>
// ============================================================

== Theoretical foundation

=== Sagas

An order touches the Order, Payment and Dispatch services, the payment
provider, a restaurant and a courier, and it takes about 40 minutes. A
single database transaction cannot span all of that: the services have
separate databases, and no lock can be held for 40 minutes while a kitchen
cooks.

A long transaction is split into a sequence of local transactions
`T1, T2, ..., Tn`, each committed on its own. Every step has a compensating
transaction `Ci` that semantically undoes it. The saga either completes all
steps, or it stops at some step `Tj` and runs the compensations
`Cj, ..., C1` in reverse order.

A compensation is not a rollback. The authorization of a payment cannot be
erased; it can only be followed by a void, which releases the money and
leaves both operations in the ledger. The customer sees the result as if
nothing had happened, while the history shows what really did.

#table(
  columns: (auto, 1fr, 1fr, 1fr),
  table.header([Step], [Command or action], [Event that moves on],
    [Failure and compensation]),
  [`AUTHORIZING_PAYMENT`], [`AuthorizePayment`], [`PaymentAuthorized`],
    [`PaymentFailed`: the order is cancelled],
  [`AWAITING_RESTAURANT`], [notify the restaurant], [`OrderAccepted`],
    [`OrderRejected` or no answer in 3 minutes: the authorization is voided],
  [`PREPARING`], [none], [`OrderReady`], [none],
  [`DISPATCHING`], [`RequestCourier`], [`CourierAssigned`],
    [`DispatchFailed`: an administrator is alerted and the customer is
     informed],
  [`DELIVERING`], [none], [`OrderPickedUp`, then `OrderDelivered`], [none],
  [`CAPTURING_PAYMENT`], [`CapturePayment`], [`PaymentCaptured`],
    [retried until it succeeds],
)

A saga gives up one property of a classic transaction: isolation. Other
parts of the system can see an order halfway through, for example after the
payment was authorized and before the restaurant answered. The design
handles this with the order status, which tells everyone exactly which
stage the order is in, and with the version number on each order, which
rejects a change based on an outdated state. A customer who cancels at the
same moment the restaurant accepts gets a conflict instead of a corrupted
order.

Waiting for a person needs a deadline. The saga stores `deadlineAt` for
the current step, and `onTimeout` treats a missed deadline like an event:
a restaurant that does not answer in 3 minutes is handled the same way as
one that rejects.

=== Idempotency and the transactional outbox

Kafka delivers every event at least once. After a network error or a
restart, a consumer may receive the same event again. Every handler is
therefore idempotent, which means processing an event twice has the same
effect as processing it once. The saga stores the identifiers of the events
it has processed. The Payment service relies on idempotency keys, which the
payment provider honours too. Delivery at least once combined with
idempotent handlers gives an effect that happens exactly once.

A service often has to change its database and publish an event about the
change. If it does the two separately, a crash between them either loses
the event or publishes an event for a change that was never committed. With
the transactional outbox, the service writes the event into an outbox table
in the same transaction as the change. A relay reads the table and
publishes the events to Kafka. An event exists exactly when the change it
describes exists.

=== Geohashing

Finding restaurants near a customer and couriers near a restaurant are both
proximity queries. A geohash turns a latitude and longitude into a short
string by repeatedly halving the map and interleaving the bits of both
coordinates. Points that are close to each other usually share a long
common prefix, so a proximity search becomes a search for keys with the
same prefix in a sorted index.

Redis stores the positions of couriers this way. `GEOADD` turns a position
into a 52-bit geohash used as the score in a sorted set, and `GEOSEARCH`
finds all members within a radius. Two places can sit right next to each
other on opposite sides of a cell boundary and share almost no prefix.
`GEOSEARCH` therefore also checks the neighbouring cells, and the result
is filtered by exact distance.

The Discovery service uses the same idea for caching. Every customer in the
same cell of roughly one square kilometre gets the same list of
restaurants, so one cached result serves everyone in that area.

=== Ordering GPS updates

GPS updates travel over a mobile network and can arrive out of order. The
Courier Location service keeps an update only if its `recordedAt` is newer
than the stored one. Comparing timestamps is safe here because they all
come from the clock of the same phone. Timestamps from different devices
could not be compared this way, since their clocks are not synchronized.

== Sequence diagrams

=== Browsing nearby restaurants

#diagram("diagrams/seq-browse.svg",
  [Browsing nearby restaurants and menus (US1)]) <seq-browse>

When a customer enters a new address, the Customer service geocodes it with
the maps provider. The Discovery service first looks in Redis for a cached
result for the customer's geohash cell and filters. On a miss it queries
OpenSearch for open restaurants whose delivery radius includes the address,
sorted by distance and rating, and caches the result for 60 seconds.

Menus are cached by restaurant and version. The response carries the
version as an ETag, so the browser can ask whether its copy is still
current instead of downloading the menu again.

=== Placing an order

#diagram("diagrams/seq-place-order.svg",
  [Placing an order and seeing the expected delivery time (US2)])
  <seq-place-order>

The Order service loads the cart and asks the Restaurant & Menu service for
a quote: the current prices, whether every item is available, whether the
restaurant is open and whether it delivers to the address. If anything
fails, the customer sees the reason and keeps the cart.

The ETA service adds the preparation time, the travel time from the maps
provider and a buffer. The order is stored as `PLACED` with copies of the
prices, together with the saga in its first step. The Payment service
creates the payment with the provider and returns a client secret, which
the browser uses to complete the payment (@seq-payment).

When `PaymentAuthorized` arrives, the saga moves the order to
`PAYMENT_AUTHORIZED`, sets a 3-minute deadline for the restaurant and
publishes `OrderPlaced`. The restaurant dashboard plays an alert and the
customer sees the order waiting for the restaurant, with the expected
delivery time.

The request carries an idempotency key, so a double click or a retry after
a network drop returns the same order instead of creating a second one.

=== Accepting and updating an order

#diagram("diagrams/seq-restaurant-status.svg",
  [The restaurant accepts and updates an order (US3)])
  <seq-restaurant-status>

The staff member accepts the order and enters a preparation time. The Order
service checks that the order belongs to the staff member's restaurant,
using the restaurant identifier in the token, and that the order has not
changed in the meantime. A conflict appears, for example, when the customer
cancelled a moment earlier.

The ETA is recalculated with the real preparation time. The saga computes
when to start looking for a courier: the moment the food will be ready
minus the courier's expected travel time, so the courier arrives as the
food comes out of the kitchen. The customer is informed over the WebSocket
and by a push notification.

Later updates, "being prepared" and "ready for pickup", follow the same
path. Each is checked against the allowed transitions of
@fig-order-states.

=== Assigning a courier and delivering

#diagram("diagrams/seq-dispatch.svg",
  [Assigning a courier, pickup and delivery (US4)]) <seq-dispatch>

When the time to dispatch arrives, the saga publishes `RequestCourier`.
Dispatch creates a delivery job, asks Redis for available couriers within
3 km of the restaurant and asks the maps provider for each candidate's
travel time. Candidates are ranked by travel time and then by how long they
have been waiting for work.

Dispatch reserves the best candidate with the atomic switch to `OFFERED`
and sends the offer, which expires after 30 seconds. If the courier
accepts, the job is assigned and `CourierAssigned` goes to the saga. If the
courier declines or the time runs out, they are excluded from this job,
become available for other jobs, and the next candidate gets the offer.
When no candidates remain, the search radius grows from 3 to 5 and then to
8 km. After the last attempt, Dispatch reports `DispatchFailed` and an
administrator is alerted.

The courier app opens the route in the courier's maps app, first to the
restaurant and then to the customer. Confirming pickup activates live
tracking for the customer. Confirming delivery moves the order to
`DELIVERED`, the saga goes on to capture the payment, and the courier is
available again.

=== Paying securely

#diagram("diagrams/seq-payment.svg",
  [Paying securely (US5)]) <seq-payment>

The Payment service creates the payment with manual capture, which means
the money is only reserved for now. The customer enters the card details in
fields served by the payment provider inside the page, so the card number
goes straight from the browser to the provider. The bank asks the customer
to confirm the payment with 3-D Secure, usually in the banking app.

The browser learns the result immediately, but the platform trusts only the
provider's webhook. The Payment service verifies the webhook's signature,
ignores it if it was already processed, checks the amount and the order,
writes an `AUTHORIZATION` entry to the ledger and publishes
`PaymentAuthorized`. A declined card or a failed confirmation leads to
`PaymentFailed`, and the saga cancels the order.

After delivery, the saga asks the Payment service to capture the money. The
capture also carries an idempotency key and adds a `CAPTURE` entry to the
ledger.

=== Live tracking

#diagram("diagrams/seq-tracking.svg",
  [Live tracking of the courier]) <seq-tracking>

While online, the courier app sends its position every 5 seconds. The
Courier Location service drops inaccurate or outdated positions, stores the
latest one in Redis GEO and, for an available courier, also in the set that
Dispatch searches. If the courier is carrying an order, the position is
published on that order's channel and the marker moves on the customer's
map.

The ETA service recalculates the estimate every 60 seconds, or sooner when
the courier leaves the expected route, instead of on every position update.
This keeps the number of paid calls to the maps provider under control.

=== Rejection and compensation

#diagram("diagrams/seq-reject.svg",
  [The restaurant rejects or does not answer]) <seq-reject>

The saga enters `COMPENSATING` when the restaurant rejects the order or the
3-minute deadline passes. It asks the Payment service to void the
authorization, which releases the reserved money and adds a `VOID` entry to
the ledger. The order becomes `REJECTED` and the customer learns, in the app
and by notification, that the order was not accepted and that they were not
charged.

If voiding fails, the saga stays in `COMPENSATING` and retries with
increasing delays. A compensation must eventually succeed, because leaving
the customer's money reserved for an order that will never arrive is not an
acceptable end state.

// ============================================================
= Security and privacy <security>
// ============================================================

== Authentication

Customers, restaurant staff, couriers and administrators all log in through
the Identity service. Passwords are stored only as Argon2id hashes. After
login the client receives an access token, a JWT valid for 15 minutes, and
a refresh token valid for 30 days that is kept in an `HttpOnly` cookie.

The access token contains the user's role. For restaurant staff it also
contains the identifier of their restaurant, so the Order service can check
that an order belongs to the staff member's restaurant without calling
another service. WebSocket connections are opened with the same token.

Administrator and restaurant owner accounts must use two-factor
authentication. They can approve restaurants, issue refunds or see many
orders, which makes them the most valuable accounts to an attacker.

== Authorization

Each service checks its own rules, and the user's identity always comes
from the verified token. A customer cannot open the tracking page of
someone else's order by changing the order number in the URL, because the
Order service compares the order's customer with the user in the token.

#table(
  columns: (1fr, 1fr),
  table.header([Action], [Allowed for]),
  [Browse restaurants and menus], [anyone],
  [Place and pay for an order], [customers],
  [Cancel an order], [the order's customer, until the restaurant accepts],
  [See an order and its tracking], [the order's customer, its restaurant
    and the assigned courier],
  [Accept, reject or update an order], [staff of the order's restaurant],
  [Edit a menu], [the owner of that restaurant],
  [Accept an offer, confirm pickup and delivery], [the courier the order was
    offered or assigned to],
  [See the customer's address and phone number], [the assigned courier,
    until delivery],
  [Approve or suspend restaurants and couriers, refund], [administrators],
)

== Data in transit and at rest

All traffic uses TLS, as HTTPS for requests and WSS for WebSockets. The
services run in a private network and traffic between them is encrypted as
well. Databases and backups are encrypted on disk, and secrets are kept in
a secrets manager. The Payment service has its own database, which no other
service can reach.

== Payments

Card details go from the browser directly to the payment provider, through
card fields the provider serves inside the page. The platform never sees a
card number, which keeps it out of almost all of PCI DSS, the security
standard of the card industry. The bank confirms every payment with 3-D
Secure, as EU rules on strong customer authentication require. The provider
reports results through signed webhooks, and a webhook with an invalid
signature is rejected. Every call to the provider carries an idempotency
key, so a retried request never charges a customer twice. The money is
captured only after delivery.

== Common attacks

#table(
  columns: (auto, 1fr),
  table.header([Attack], [Protection]),
  [Accessing other people's orders], [Ownership is checked on every order
    request.],
  [Script injection through restaurant names, menu texts or delivery
    notes], [These texts are displayed as plain text, never as HTML.],
  [SQL injection], [Only parameterized queries are used.],
  [Bots, fake orders, flooding at peak times], [Rate limits per user and
    per IP address. An order exists only after its payment is
    authorized.],
  [A courier confirming a delivery they did not make], [Delivery can be
    confirmed only near the customer's address, and the route is kept for
    disputes.],
)

== GDPR

The platform processes personal data of three groups of people.

#table(
  columns: (auto, 1fr),
  table.header([User], [Personal data]),
  [Customer], [name, e-mail, phone number, delivery addresses, order
    history],
  [Courier], [name, phone number, vehicle, location while online],
  [Restaurant staff], [name, e-mail, the restaurant they work for],
)

Processing this data is necessary to deliver the orders, so the legal basis
is the contract with the user. Marketing messages require consent. Orders
and payments must be kept as long as accounting law requires, which is a
legal obligation that also limits what deleting an account can remove.
=== Location of couriers

A courier's location is the most sensitive data in the system, since it
shows where a person is during their working day. The design limits it in
several ways:

- The app collects the location only while the courier is online. Going
  offline stops tracking completely.
- A customer sees the courier's position only between pickup and delivery.
- The route of each delivery is kept for 30 days to settle disputes and is
  then deleted automatically, by dropping the database partitions that are
  older than 30 days.
- An administrator can open a route only for a dispute, and every access is
  recorded in an audit log.

The same principle protects customers. A courier sees the customer's
address and phone number only after accepting the order and loses access
after delivery.

=== Rights and retention

Users can download all their data, correct their profile and delete their
account. If a data breach occurs, the supervisory authority must be notified within 72 hours.

#table(
  columns: (1fr, 1fr),
  table.header([Data], [Retention]),
  [Route of a delivery], [30 days],
  [Live position of a courier], [only the latest one, while online],
  [Carts], [7 days],
  [Orders and payments], [as long as accounting law requires; personal
    fields are anonymized when the account is deleted],
  [Logs, with a pseudonymous user identifier], [90 days],
)

=== Deleting an account

#diagram("diagrams/seq-delete-account.svg",
  [Deleting a customer account]) <seq-delete>

An account cannot be deleted while one of its orders is still on the way.
Otherwise the Identity service deactivates the account, logs the user out
on every device and publishes `UserDeleted`. The Customer service deletes
the profile and the addresses, and the Courier Location service deletes the
routes of deliveries to those addresses.

Orders and payments cannot simply be deleted, because accounting law
requires keeping them. The Order service anonymizes them instead: it
removes the name, the address text, the phone number and the delivery
notes, and keeps the amounts, the items and the dates. The Payment service
keeps its ledger and removes the link to the person.

// ============================================================
= Scalability <scalability>
// ============================================================

== Load estimate

#table(
  columns: (1fr, auto),
  table.header([Assumption], [Value]),
  [Orders per day], [500,000],
  [Active hours per day], [14, from 10:00 to 24:00],
  [Peak at lunch and dinner], [3 × the average],
  [Flash promotion], [10 × the normal peak, for about an hour],
  [Read requests per order (about 10 visits of 15 requests)], [150],
  [Lifetime of an order], [about 40 minutes, 25 of them with a courier],
  [Restaurants], [20,000],
  [Interval between GPS updates], [5 seconds],
)

#table(
  columns: (1fr, 1fr, auto, auto),
  table.header([Load], [Calculation], [Normal peak], [Promotion]),
  [New orders], [500,000 / (14 × 3,600) × 3], [≈ 30 / s], [≈ 300 / s],
  [Read requests], [30 × 150], [≈ 4,500 / s], [≈ 45,000 / s],
  [Orders in progress], [30 / s × 2,400 s], [≈ 72,000], [],
  [Couriers online], [30 / s × 1,500 s, plus idle couriers], [≈ 50,000],
    [],
  [GPS updates], [50,000 / 5 s], [≈ 10,000 / s], [],
  [WebSocket connections], [customers, couriers and restaurants],
    [≈ 140,000], [],
  [Kafka events], [30 orders × about 12 events], [≈ 360 / s],
    [≈ 3,600 / s],
  [Payment authorizations], [one per order], [≈ 30 / s], [≈ 300 / s],
  [Calls to the maps provider for ETA], [45,000 deliveries / 60 s],
    [≈ 750 / s], [],
)

Reads outnumber orders by about 150 to 1, which makes caching the most
effective tool. GPS updates are the largest stream of writes, but each is
small and only the latest position matters, so they belong in Redis rather
than in a database. Writes on the order path are modest at a normal peak
and grow tenfold during a promotion, which is where the system has to
protect itself.

Two limits come from outside: the payment provider caps the rate of API
calls, and the maps provider charges for every call. The tightest limit is
physical, though. Servers can be added in minutes, but a kitchen cannot cook
ten times more food because a promotion started.

== Partitioning by city

An order in Cluj never needs a courier in Iași, so the location-heavy parts
of the system are partitioned by city. Redis keeps separate keys per city,
such as `couriers:available:{cityId}` and `couriers:positions:{cityId}`,
and Dispatch and Courier Location process Kafka partitions grouped by city.
A spike in Bucharest does not slow down dispatch in Timișoara, and adding a
city means adding partitions without changing the architecture.

== Scaling the components

#table(
  columns: (auto, 1fr),
  table.header([Component], [Strategy]),
  [Stateless services], [The gateway and the Customer, Restaurant & Menu,
    Discovery, Order, Payment, ETA, Courier and Notification services run as
    several instances. Kubernetes adds instances based on CPU use and
    request rate.],
  [Restaurant lists and menus], [Three layers of caching. The CDN keeps
    menus for a long time because their version is part of the URL. Redis
    keeps search results per geohash cell for 60 seconds. The browser
    revalidates its copy with an ETag. Most read requests never reach a
    service.],
  [Discovery], [OpenSearch replicas serve the reads. The index can be
    rebuilt from events at any time.],
  [Order database], [One PostgreSQL primary handles the writes of a normal
    peak. Read replicas serve order history and dashboards. If the load
    keeps growing, the database can be sharded by city.],
  [Payment], [A separate database, and a rate limiter in front of the
    payment provider that matches the provider's limits.],
  [Realtime Gateway], [About 140,000 connections at 10,000 to 20,000 per
    node, so 8 to 14 stateless nodes.],
  [Courier Location], [About 10,000 updates per second into Redis GEO,
    sharded by city. Only positions of couriers carrying an order are
    forwarded to customers.],
  [Dispatch], [Partitioned by city; matching in one city is independent of
    every other city.],
  [Maps provider], [Travel times are cached by pair of grid cells and time
    of day. The ETA is recalculated every 60 seconds or when the courier
    leaves the route, not on every update.],
  [Kafka], [Order events are partitioned by order, and location events are
    grouped by city.],
)

#diagram("diagrams/deployment-scaling.svg",
  [Deployment and scaling of the system]) <fig-deployment>

== Flash promotions

A promotion is planned, so the system can prepare before it starts instead
of only reacting to the load.

#table(
  columns: (auto, 1fr),
  table.header([Measure], [How it works]),
  [Scheduled scaling], [Instance counts are raised 30 minutes before the
    start. Automatic scaling alone reacts too slowly to a jump that happens
    within minutes.],
  [Cache warm-up], [Menus and restaurant lists of the participating
    restaurants are loaded into the CDN and Redis in advance.],
  [Admission control], [The gateway admits at most a fixed number of
    checkouts per second in each city, using a token bucket in Redis.
    Customers above the limit wait in a virtual queue with an estimated
    waiting time. A short, honest wait is better than errors for
    everyone.],
  [Load shedding by priority], [Under pressure the gateway drops the least
    important traffic first. Operations on orders already placed, by
    restaurants and couriers, are protected first, then checkout and
    payment, then browsing. Recommendations, reviews and order history are
    dropped first.],
  [Kitchen capacity], [A restaurant that reaches `maxActiveOrders` appears
    as busy with a longer delivery time, or stops taking orders for a
    while.],
  [Limited coupons], [A coupon for the first 10,000 orders is a counter in
    Redis decreased with the atomic `DECR`. Thousands of simultaneous
    checkouts can never produce more than 10,000 discounts.],
  [Shortage of couriers], [Delivery estimates grow to match reality,
    Dispatch widens its search radius, and couriers get a notification in
    advance asking them to go online.],
)

#diagram("diagrams/seq-flash-checkout.svg",
  [Checkout during a flash promotion]) <seq-flash>

A customer who finds the city's checkout limit reached receives a response
with the time to wait. The app retries with the same idempotency key, so a
retry cannot create a duplicate order. The Order service then checks the
restaurant's capacity and reserves a coupon by decreasing the counter. If
the counter drops below zero, the coupon is given back and the customer is
asked to confirm the full price. If the payment later fails or the
restaurant rejects the order, the saga's compensation returns the coupon as
well.

== Resilience

#table(
  columns: (auto, auto, 1fr),
  table.header([Failure], [Effect], [Handling]),
  [Payment provider unavailable], [No new orders], [A circuit breaker
    returns a clear message instead of timeouts. Orders already placed
    continue.],
  [Maps provider unavailable], [No exact ETA or travel times], [The ETA
    falls back to the straight-line distance multiplied by a factor for the
    city, at an average speed. Couriers still navigate with their own maps
    app.],
  [Dispatch unavailable], [New orders wait for a courier], [Requests stay
    in Kafka and are processed when Dispatch is back. Restaurants keep
    cooking.],
  [A Realtime Gateway node fails], [Clients lose live updates], [Clients
    reconnect with exponential backoff and random jitter, and reload the
    order over REST.],
  [A courier's phone loses signal], [The marker stops moving], [The app
    buffers positions and sends them later; the server keeps only the
    newest.],
  [A Redis shard fails], [Dispatch pauses in one city for a few seconds],
    [A replica is promoted automatically and pending offers are sent
     again.],
  [A saga step fails], [The order stops progressing], [The saga state is in
    the database, and timeouts and retries move it forward or compensate
    it.],
)

== Monitoring

The business metrics are tracked per city: orders per minute, the time
restaurants take to accept, the time to assign a courier and the accuracy
of delivery estimates, comparing the predicted with the actual delivery
time. The technical metrics are the 99th percentile of checkout latency,
the success rate of payment authorizations, the number of requests
rejected by admission control, Kafka consumer lag, WebSocket connections
per node, cache hit ratios, and calls to the maps provider per minute,
which translate directly into cost.
