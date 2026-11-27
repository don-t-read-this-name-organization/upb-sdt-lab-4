#set document(
  title: "Digital Portfolio Website",
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
  #text(20pt, weight: "bold")[Digital Portfolio Website]
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
  [FR1], [Creators can upload images and videos, group them into albums and
          change their order.],
  [FR2], [Creators choose a template and customise it within the limits of
          that template: colours, fonts, grid style and social links.],
  [FR3], [Portfolios can be shared on social media with a correct preview
          card, and creators can see views and shares.],
  [FR4], [Media is delivered in modern formats, sized for each screen, and
          cached close to the visitor.],
  [FR5], [Original files are stored securely and scalably. Only validated
          copies are ever published.],
  [FR6], [Creators can unpublish a portfolio. It stops being visible to
          visitors and can be published again later.],
  [FR7], [Creators can delete their media and their account. Originals,
          published pages and cached copies are removed, and personal data
          is erased.],
)


== User stories

#table(
  columns: (auto, 1fr, auto),
  table.header([ID], [User story], [Sequence diagram]),
  [US1], [As a photographer, I want to upload my photos in different albums
          so that I can display them by project or theme.], [@seq-upload],
  [US2], [As an artist, I want to customise the appearance of my portfolio so
          that it reflects my personal style.],
          [@seq-customize, @seq-publish],
  [US3], [As a user, I want to see analytics for my portfolio, such as views
          and shares, so I can track its popularity.],
          [@seq-visit, @seq-analytics],
  [US4], [As a visitor, I want to share a portfolio on social media so others
          can see it.], [@seq-share],
)


== Non-functional requirements

#table(
  columns: (auto, 1fr),
  table.header([Area], [Requirement]),
  [Page load], [The first HTML of a portfolio arrives from the CDN in under
    200 ms for most visitors. Largest visible content is rendered in about
    2.5 seconds on a typical mobile connection.],
  [Upload], [Images up to 50 MB and videos up to 2 GB. Files go directly to
    storage, and large videos can be resumed after a dropped connection.],
  [Freshness], [A published change is visible to visitors within about one
    minute. Analytics on the dashboard are at most a few minutes old.],
  [Availability], [The public site, which is served from the CDN, targets
    99.95%. The editor and the API target 99.9%.],
  [Privacy], [Personal data is handled according to the GDPR and stored in
    the EU. No IP address is stored with analytics, and GPS data is removed
    from every published photo.],
  [Durability], [Originals are never deleted by accident: the object storage
    keeps several copies across zones, and the databases have point-in-time
    recovery.],
)

// ============================================================
= Architecture
// ============================================================

== Overview

The system is split by business capability, and each service owns its data.
Creators edit their portfolios through the web editor and upload files
straight to storage. Visitors never talk to the application services: they
load pages and media from the CDN, which is fed by static files that the
platform renders when a portfolio is published. The only requests that reach
the application from visitors are the small analytics beacons.

#diagram("diagrams/architecture.svg",
  [Component view of the system]) <fig-arch>

== Clients

#table(
  columns: (auto, auto, 1fr),
  table.header([Client], [Used by], [Main features]),
  [Editor (web app)], [creators], [uploading, albums, templates, publishing,
    statistics],
  [Public portfolio site], [visitors], [browsing albums, viewing media,
    sharing; a small loader script sends the analytics beacons],
  [Social platform crawlers], [social networks], [reading the Open Graph
    tags to build a preview card],
)

== Services

#table(
  columns: (auto, 1fr, auto),
  table.header([Service], [Responsibility], [Data store]),
  [API Gateway], [Entry point for REST requests. Checks JWTs, applies rate
    limits and routes requests to services.], [Redis (rate limits)],
  [Identity], [Accounts, login, refresh tokens and optional two-factor
    authentication.], [PostgreSQL],
  [Portfolio], [Creator profiles, portfolios, albums, the template catalogue,
    theme settings, and publishing. Publishing creates a site snapshot.],
    [PostgreSQL],
  [Media], [Upload tickets, quotas and the status of every file. It never
    touches the file bytes.], [PostgreSQL],
  [Media Worker], [Checks the file type, scans for malware, strips metadata
    and creates the derivatives: AVIF, WebP, JPEG and HLS. Also writes the status of each file.], [PostgreSQL, object storage],
  [Site Publisher], [Renders a portfolio as static HTML and writes it to the
    public bucket, then invalidates the CDN.], [Object storage],
  [Analytics Collector], [Receives beacons, validates them, hashes the visitor
    and publishes the events to Kafka. Stores nothing itself.], [none],
  [Analytics Aggregator], [Reads the event stream and writes it into
    ClickHouse, where materialised views keep the rollups.], [ClickHouse],
  [Analytics Reporting], [Answers the dashboard: checks ownership, then reads
    the rollups.], [ClickHouse, Redis (cache)],
  [CDN], [Serves pages, media and social preview images close to the visitor.
    It has a web application firewall and bot filtering.], [none],
)

The Portfolio service does not own media files and the Analytics services do
not own portfolios. Each of them keeps only the identifiers and the small
copies of data it needs, as described in the domain model.

== Communication

REST over HTTPS, through the API Gateway, is used for everything a creator
does in the editor: upload tickets, albums, themes and publishing.

Files are sent directly from the browser to the private originals bucket
with a presigned URL. The URL is created by the Media service and expires
after 15 minutes, so the bytes never pass through the application servers.

Kafka carries the domain events, such as `MediaUploaded`, `MediaReady`,
`PortfolioPublished` and the analytics events. The Portfolio service publishes
its events through a transactional outbox, so an event exists exactly when the
change it describes was committed.

Internal endpoints, such as the one the Site Publisher uses to read a
portfolio, are not reachable through the gateway. They are protected by the
network policies of the cluster and by service credentials.

== Storage layout

Storage is split into two buckets with different access rules:

- the *originals bucket* is private. Creators upload to it with presigned
  URLs, and only the Media Worker reads it;
- the *public bucket* holds the derivatives and the static site files. It is
  served through the CDN and contains no original file.

Derivative keys contain the media identifier and the variant, for example
`/media/{mediaId}/medium-1200.avif`. Each derivative is written once and
never changed, so the CDN can cache it for a year. Pages change more often,
so they get a short cache time and are invalidated when a portfolio is
published.

== Technology choices

#table(
  columns: (auto, 1fr),
  table.header([Technology], [Why it is used here]),
  [PostgreSQL], [Accounts, portfolios and media metadata need transactions and
    consistent updates, such as the version check on theme changes.],
  [Object storage], [Practically unlimited capacity for originals and
    derivatives, with direct uploads from the browser and durable copies
    across zones.],
  [CDN], [Serves almost all of the traffic: pages, images, videos and preview
    images, close to the visitor. A web application firewall sits in front of
    it.],
  [Kafka], [Durable events between the services. Events are kept, so a new
    consumer, such as a new analytics view, can replay them.],
  [ClickHouse], [Stores millions of analytics events per day and answers
    aggregate questions, such as views per day for one portfolio, in
    milliseconds.],
  [Redis], [Rate limits, the cache of dashboard reports and the daily keys for
    visitor hashes.],
  [FFmpeg and libvips], [Image resizing and video transcoding inside the
    workers.],
  [Static rendering], [Published portfolios are plain HTML files. They load
    fast, cost almost nothing to serve and cannot run code from the creator.],
)

// ============================================================
= Domain model
// ============================================================

== Modelling rules

Each service owns its classes. A class never holds an object from another
service, only its identifier: an `AlbumItem` stores a `mediaId`, and the media
file itself stays in the Media service. In the diagrams, solid lines are
associations within one service and dashed arrows marked `«ref by ID»` are
references across services. Classes of other services are grey, marked
`«external»` and shown without members.

Small values such as `ThemeSettings` and `SocialLink` are value objects. Each
service that needs an enumeration, such as `MediaStatus`, keeps its own copy,
so no service depends on a shared library.

#diagram("diagrams/class-overview.svg",
  [Overview of the domain classes, grouped by service]) <fig-class-overview>

== Identity service

#diagram("diagrams/class-identity.svg",
  [Classes of the Identity service], width: 75%) <fig-class-identity>

There are two roles. Creators own portfolios. Administrators can take down
content that breaks the rules and can see the platform's operational
statistics, but they cannot see the private analytics of a creator. Every
account can enable two-factor authentication, and it is required for
administrators.

== Portfolio service

#diagram("diagrams/class-portfolio.svg",
  [Classes of the Portfolio service]) <fig-class-portfolio>

A portfolio starts as `DRAFT`. Changes made in the editor are saved in the
draft, and the visitors keep seeing the last published snapshot until the
creator publishes again. `SiteSnapshot` keeps every published version, so a
bad publication can be rolled back.

`ThemeSettings` does not contain HTML, CSS or JavaScript. It contains only
values from the lists that the chosen `Template` allows: an accent colour
written as a hex code, a font from a fixed list, a grid style and the social
links. This is what makes customisation safe for visitors, since no creator
can add code to a page.

`AlbumItem` keeps a copy of the media status, so the editor can show that an
item is still being processed without asking the Media service on every page
load. The copy is updated by the `MediaReady` and `MediaRejected` events.

== Media service

#diagram("diagrams/class-media.svg",
  [Classes of the Media service]) <fig-class-media>

`MediaAsset` describes one uploaded file and its state. `UploadTicket` is the
short-lived permission to upload that file, and it fixes the size and the
content type. `Derivative` is a copy created by the worker: a resized image or
a video rendition. The original is never served to visitors.

#diagram("diagrams/media-states.svg",
  [States of a media file], width: 80%) <fig-media-states>

`MediaAsset` moves through the states in @fig-media-states. A file that is
rejected or fails stays in the editor until the creator removes it, so the
creator can see what went wrong and try again with a different file.

== Analytics services

#diagram("diagrams/class-analytics.svg",
  [Classes of the Analytics services]) <fig-class-analytics>

Every beacon becomes an `AnalyticsEvent`. Events are immutable, and a
correction is a new event. The event does not contain the IP address or the
visitor's identity. Instead, `visitorHash` is a keyed hash of the IP address
and the user agent. The key changes every day and is deleted after 24 hours,
so the same visitor cannot be followed across days.

`DailyRollup` is a read model. It is built from the events by ClickHouse and
is what the dashboard reads. `PortfolioOwnerIndex` is a local copy of who owns
which portfolio, updated from the `PortfolioPublished` and portfolio creation
events. It lets Analytics Reporting check ownership without calling the
Portfolio service on every request.

// ============================================================
= Behaviour <behaviour>
// ============================================================

== Theoretical foundation

=== Direct uploads with presigned URLs

A classic upload streams every byte through the application servers, which
then write it to storage. That makes the servers the bottleneck for large
videos and ties up their memory and connections. With a presigned URL the
server only signs a permission: the signature fixes the object key, the
maximum size, the content type and the expiry time. The browser then sends
the bytes to storage directly, and the server checks the result afterwards by
comparing the size and the SHA-256 checksum with what was promised.

The server must never trust the client's claim about the file. The type is
decided from the file's first bytes, not from its extension, and the worker
decodes every image into pixels and encodes it again. Decoding and re-encoding
removes any hidden content that could be used to attack a browser or a later
processing step.

=== Transactional outbox and idempotent consumers

Kafka delivers every event at least once. A worker may therefore receive the
same `MediaUploaded` event twice after a restart. Each handler is idempotent:
it stores the identifier of the event it has processed, and a duplicate is
ignored. The Portfolio service writes its events into an outbox table in the
same transaction as the change, so a crash never publishes an event for a
change that was not saved.

=== Counting unique visitors without cookies

Counting unique visitors exactly needs a set of every visitor, which becomes
large for popular portfolios. A HyperLogLog sketch estimates the number of
distinct values in a few kilobytes with an error of about 1%. Combined with
the daily visitor hash, it gives a good count of visitors per day without
storing a cookie or an identifier that survives the day.

== Sequence diagrams

=== Uploading media into an album

#diagram("diagrams/seq-upload.svg",
  [Uploading a photo or video into an album (US1)]) <seq-upload>

The upload is split into two steps. First the editor asks the Media service
for a ticket and sends the file to storage. Then it confirms the upload.
Confirming changes the state to `PROCESSING` and publishes `MediaUploaded`.
The creator can already add the file to an album, which shows it as being
processed; the Portfolio service changes the item to `READY` when the worker
reports success.

The Media Worker does the expensive work asynchronously. It reads the original
from the private bucket, checks the file's real type, scans it for malware,
removes the GPS coordinates from the EXIF data, and writes the derivatives.
Photos are stored at three sizes in AVIF and WebP, and once more as a JPEG
for social previews. A video gets a poster image and two HLS renditions, so
the player can switch quality with the connection speed.

If the worker fails for a temporary reason, the message is retried with
increasing delays. After five failed attempts the file is marked `FAILED`.

=== Organising the portfolio and customising its appearance

#diagram("diagrams/seq-customize.svg",
  [Choosing a template and customising its appearance (US2)]) <seq-customize>

The editor first asks for the templates. Every template lists the options it
supports, and the editor shows only those. When the creator saves, the
Portfolio service validates every field against the template and against
fixed lists: an invalid colour, a link to an unknown site or an unexpected
field is rejected with a message for each field.

Saving uses the version number of the portfolio. If another editor tab
changed the theme in the meantime, the update affects zero rows and the
creator is asked to reload. This avoids silently overwriting a change.

The preview is rendered by the same kind of renderer that publishes the site,
but in draft mode. It is never cached and is marked `noindex`, so search
engines do not index unpublished work, and it is shown in a sandboxed frame.

=== Publishing a portfolio

#diagram("diagrams/seq-publish.svg",
  [Publishing a portfolio as static pages (US2, FR4)]) <seq-publish>

Publishing does not change any page directly. The Portfolio service records a
new snapshot and an event in one transaction. The Site Publisher then renders
the pages and writes them to the public bucket. The HTML of the home page is
written last, so the previous version stays live until the new one is
complete. If anything fails, the snapshot is marked `FAILED` and the visitors
keep seeing the previous version.

Pages are static and contain no creator code. Images are included with
`srcset`, so each device downloads a suitable size, and every page carries
the Open Graph tags that social platforms need.

=== Visiting a portfolio and recording the view

#diagram("diagrams/seq-visit.svg",
  [A visitor opens a portfolio, and the view is recorded (US3, FR4)]) <seq-visit>

Pages and media come from the CDN, and in most cases the application servers
do not see the request at all. The loader script sends the analytics events
as one small batch with `sendBeacon`, so the browser can send them even while
the visitor is leaving the page. The Collector accepts the batch with
`202 Accepted` at once, which keeps the visitor's experience fast even when
the analytics pipeline is slow. The aggregation happens later, from the
stream.

=== Sharing a portfolio on social media

#diagram("diagrams/seq-share.svg",
  [Sharing a portfolio, and the preview the platform builds (US4)]) <seq-share>

The share button opens the platform's own share page, with the canonical
address of the portfolio and no tracking parameters in it. The visitor's
choice is recorded as a `ShareEvent`. The platform's crawler then reads the
page, and the Open Graph tags tell it which title and image to use in the
preview card. The image is the `OG_1200` derivative, which is already sized
for the cards of the big platforms, so the platform does not have to resize
a full-size original.

=== Viewing the statistics

#diagram("diagrams/seq-analytics.svg",
  [Viewing the statistics of a portfolio (US3)]) <seq-analytics>

The dashboard reads the rollups, not the raw events, so it stays fast even
after years of traffic. The ownership check uses the local `PortfolioOwnerIndex`,
and a report that was requested recently is served from Redis. The reports are
cached for 5 minutes, which is much shorter than the freshness requirement.

=== Deleting an account

#diagram("diagrams/seq-delete-account.svg",
  [Deleting an account with its portfolios and media (FR7)]) <seq-delete-account>

Deletion starts with the Identity service, which closes the account at once:
it revokes every session and erases the email and password hash. The request
is confirmed with the password and, when it is enabled, a one-time code, so a
stolen session cannot delete an account on its own.

The rest of the work happens asynchronously. Each service removes its own data
when it receives `UserDeleted` or `PortfolioDeleted`, and it retries until it
succeeds. The Media service deletes the originals and derivatives, the Site
Publisher removes the pages, and the analytics keep only the aggregated counts.
The account row stays as a tombstone with its identifier until every service
has confirmed, so the process can be restarted safely.

Unpublishing (FR6) is a smaller version of the same flow: the Portfolio service
changes the status, the Site Publisher removes the pages and the CDN is
invalidated. The media and the snapshots are kept, so the portfolio can be
published again.

// ============================================================
= Security and privacy <security>
// ============================================================

== Authentication

Creators and administrators log in through the Identity service. Passwords
are stored only as Argon2id hashes. After login the client receives an access
token, a JWT valid for 15 minutes, and a refresh token valid for 30 days. The
refresh token is stored in an `HttpOnly`, `Secure` cookie with `SameSite`
set to `Strict`, and only its hash is stored on the server, so a database leak
does not reveal usable tokens.

The access token contains the account identifier and the role. Services trust
the claims only after checking the signature, and they never accept an
identifier from the request body as the identity of the caller.

== Authorization

#table(
  columns: (1fr, 1fr),
  table.header([Action], [Allowed for]),
  [See a published portfolio, its albums and media], [anyone],
  [Upload media, edit albums, change the theme, publish], [the owner of the
    portfolio],
  [Unpublish or delete a portfolio], [the owner, and administrators for
    content that breaks the rules],
  [See the statistics of a portfolio], [the owner only],
  [Read the originals of a file], [nobody, through the platform; only the
    worker reads them],
  [Call internal endpoints, such as the Site Publisher's], [services only],
  [Suspend an account], [administrators],
)

Ownership is checked in every service that changes or reads private data,
using the identifier from the token. Changing the portfolio identifier in a
URL does not give access to someone else's portfolio, because the owner check
compares the stored owner with the token on every request.

== Upload security

- The presigned URL fixes the key, the size, the content type and the
  checksum, and it expires after 15 minutes.
- The file type is decided from the magic bytes. Only JPEG, PNG, HEIC, WebP,
  MP4 and MOV are accepted.
- Every file is scanned for malware before any derivative is published. An
  infected file is rejected and deleted.
- Images are decoded and re-encoded, which removes the EXIF data, including
  GPS coordinates, and any payload hidden in the file.
- Originals are never served to visitors. Only the derivatives are public.
- Each creator has a storage quota, for example 5 GB on the free plan and
  100 GB on the paid one. The quota is checked when the ticket is issued.

== Templates and visitor safety

Creators cannot add HTML, CSS or JavaScript. All text in a portfolio, such as
titles, captions and the biography, is escaped when the page is rendered.
The published pages send a Content Security Policy that allows scripts only
from the platform's own domain. The editor's preview runs in a sandboxed frame
with no access to the editor.

Social links are accepted only when they use HTTPS and point to one of the
platforms in `SocialPlatform`. The platform never fetches a URL that a creator
supplies, so the publisher cannot be used to reach internal addresses.

== Data in transit and at rest

All traffic uses TLS 1.2 or newer. Services talk to each other inside the
private network, and the traffic between them is encrypted too. The object
storage, the databases and the backups are encrypted on disk. Secrets, such as
the signing keys and the database credentials, are kept in a secrets manager
and rotated regularly.

== Visitor analytics privacy

The analytics are designed to collect as little as possible:

- no cookies are set on the visitor's browser;
- the IP address is used only to build the daily hash and is discarded at once;
- the referrer is stored as a domain only, and the country as a code;
- the daily key that makes the hash unique to one day is deleted after 24 hours;
- the dashboard hides any number that is based on very few visitors.

Raw events are kept for 90 days, and only the aggregated rollups are kept
longer. Whether the analytics need a consent banner under the GDPR and the
ePrivacy rules must be confirmed with the platform's legal advisers; the
design above is built so that the data cannot identify a visitor.

== GDPR and the rights of creators

Creators can download a copy of their data: the profile, the portfolios, the
album structure and the originals, as a ZIP file behind a signed link that
expires after 24 hours. They can correct their profile at any time.

When an account is deleted (FR7, @seq-delete-account), the Identity service
closes the login at once and publishes `UserDeleted`. The Portfolio service
unpublishes and removes the portfolios. The Media service deletes the originals
and the derivatives, and the CDN cache is invalidated. The aggregated statistics
contain no personal data, so they can remain, while the raw events of the
deleted portfolios are removed.

#table(
  columns: (1fr, 1fr),
  table.header([Data], [Retention]),
  [Original files and derivatives], [until the creator deletes them or the
    account is deleted],
  [Published pages], [until the portfolio is unpublished],
  [Raw analytics events], [90 days],
  [Aggregated statistics], [kept for the life of the portfolio, with no
    personal data],
  [Logs, with a pseudonymous user identifier], [30 days],
  [Daily visitor keys], [24 hours],
)

== Common attacks

#table(
  columns: (1fr, 2fr),
  table.header([Attack], [Protection]),
  [Script injection through titles, captions or the biography], [All text is
    escaped; the Content Security Policy blocks inline scripts.],
  [Uploading a disguised malicious file], [The type is decided from the bytes,
    the file is re-encoded and scanned before it is published.],
  [Scraping the original files], [Originals are private; the public site
    serves only the smaller derivatives.],
  [Inflated view counts from bots], [The CDN bot filter, rate limits per IP
    address, and unique counts per daily hash.],
  [Account takeover by guessing passwords], [Rate limits on login, Argon2id
    hashes, and optional two-factor authentication.],
  [Enumerating unlisted portfolios], [Identifiers are random, and unlisted
    portfolios are marked `noindex` and kept out of every listing.],
  [Cross-site request forgery], [`SameSite` cookies and a CSRF token on the
    refresh endpoint.],
  [Denial of service on the public site], [The CDN absorbs most of the traffic,
    and the web application firewall blocks abusive clients.],
)

// ============================================================
= Scalability <scalability>
// ============================================================

== Load estimate

#table(
  columns: (1fr, 1fr),
  table.header([Assumption], [Value]),
  [Registered creators], [1,000,000],
  [Creators active in a month], [150,000],
  [Uploads per active creator per month], [40],
  [Average original size], [8 MB for a photo, 150 MB for a video, with 85%
    photos and 15% videos],
  [Public page views per day], [20,000,000],
  [Images loaded per page view], [about 20, at about 120 KB each],
  [Beacons per page view], [about 3],
  [Peak factor], [5 times the average],
)

#table(
  columns: (1fr, 1fr, 1fr),
  table.header([Load], [Calculation], [Value]),
  [New uploads per day], [150,000 × 40 / 30], [≈ 200,000],
  [Ingress of originals per day], [200,000 × (0.85 × 8 MB + 0.15 × 150 MB)],
    [≈ 6 TB],
  [Storage growth per year, with derivatives], [6 TB × 365 × about 1.2],
    [≈ 2.6 PB],
  [Page views], [20,000,000 / 86,400 s], [≈ 230 / s, peak ≈ 1,150 / s],
  [Image egress per day], [20,000,000 × 2.4 MB], [≈ 48 TB, about 4.4 Gbit/s],
  [Requests reaching the origin], [10% of the peak page views, from cache
    misses], [≈ 115 / s],
  [Analytics events], [20,000,000 × 3 events], [≈ 700 / s, peak ≈ 3,500 / s],
  [Raw analytics volume per day], [60,000,000 × about 250 bytes], [≈ 15 GB],
  [Upload requests at the peak], [about 10 per second], [≈ 10 / s],
)

Reads outnumber everything else by a wide margin: one upload is followed by
hundreds of image requests from visitors. This is why the design pushes
almost all reads to the CDN, where they are cheap, and keeps the application
for the work that has to be correct: uploads, publishing, the theme and the
statistics.

The most expensive stage is video transcoding. A clip of 150 MB takes several
CPU minutes to produce its renditions. Video workers therefore form a separate
pool that scales on the lag of its queue, so a burst of videos cannot slow
down the processing of photos.

== Caching and the CDN

Three kinds of cache work together. Derivatives are immutable, so visitors and
the CDN keep them for a year. Pages have a short cache time, one minute, and
are invalidated for one portfolio when it is published, so a change is visible
quickly without invalidating the whole site. Dashboard reports are cached in
Redis for 5 minutes.

Storage also scales in a simple way: the derivative keys are based on the
media identifier, so the storage can be spread over many partitions, and no
single prefix becomes hot.

== Kafka partitioning and viral portfolios

A portfolio shared by a well-known photographer can receive a million views
in an hour. If the analytics events were keyed by `portfolioId`, all of them
would land on one partition, and one consumer would become the bottleneck.
The events are therefore keyed by `eventId`, which spreads the load over all
partitions. Counting does not need the events of one portfolio to be processed
in order, because the rollups are sums and sketches. Ordering matters only for
the media state changes, and those events are keyed by `mediaId`.

== Scaling the components

#table(
  columns: (auto, 1fr),
  table.header([Component], [Strategy]),
  [Stateless services], [The gateway, Identity, Portfolio, Media, Collector and
    Reporting run as several instances. Kubernetes adds instances based on CPU
    use and request rate.],
  [Media Worker], [Scales on the lag of the `MediaUploaded` topic. Image and
    video workers are separate pools.],
  [Site Publisher], [Scales on the lag of the `PortfolioPublished` topic. Each
    portfolio is rendered independently.],
  [Analytics Collector], [The most-called service, at up to 30 instances. It
    keeps no state, so instances can be added in seconds.],
  [Analytics Aggregator], [Consumers in a group, one per partition. ClickHouse
    receives batches, not single events.],
  [PostgreSQL], [One primary per service with a read replica. Portfolios are
    small rows, so one primary handles the write load with room to spare.],
  [ClickHouse], [Sharded by portfolio and replicated. Rollups are pre-computed,
    so a dashboard query reads a few hundred rows.],
  [Object storage and CDN], [Practically unlimited capacity. The CDN absorbs
    the peaks, so the origin only sees cache misses.],
)

#diagram("diagrams/deployment-scaling.svg",
  [Deployment and scaling of the system]) <fig-deployment>

== Resilience

#table(
  columns: (27%, 27%, 1fr),
  table.header([Failure], [Effect], [Handling]),
  [CDN node fails], [Visitors reach another node], [Anycast routing sends the
    request to the nearest healthy node.],
  [Media Worker crashes mid-file], [One file is delayed], [The message is
    redelivered and the worker starts again. Derivatives are written with the
    same key, so a repeated write changes nothing.],
  [Site Publisher fails], [A change is not visible yet], [The previous version
    stays live. The event is retried, and the snapshot is marked `FAILED` if
    retries run out.],
  [Analytics Aggregator is down], [Dashboard data is delayed], [Kafka keeps the
    events, and the consumer catches up when it is back.],
  [ClickHouse is unavailable], [The dashboard shows a message], [Beacons still
    flow to Kafka. Reports use the last cached result.],
  [Object storage zone fails], [Writes move to the other zones], [Object
    storage replicates across zones, and the workers retry.],
  [Redis fails], [Rate limits and report cache are lost], [Limits fall back to
    the gateway's local counters, and reports are recomputed from ClickHouse.],
)

== Monitoring

The business metrics are tracked per day: uploads, portfolios published, the
share of visitors on mobile devices, and the number of views that the bot
filter removed. The technical metrics are the 75th percentile of time to first
byte on the CDN, the cache hit ratio, the processing time of a photo and a
video, the age of the oldest message in each Kafka consumer group, the
storage used per creator, and the number of rejected uploads by reason.
