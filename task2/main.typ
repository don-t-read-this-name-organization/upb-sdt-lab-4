// ============================================================
//  Setup
// ============================================================
#set document(
  title: "Shared Playlists and Synchronized Listening",
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

// ============================================================
//  Title page
// ============================================================
#align(center + horizon)[
  #text(20pt, weight: "bold")[Shared Playlists and Synchronized Listening]
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
  [FR1], [Users can create shared playlists and edit them together with other
          collaborators.],
  [FR2], [Users can start a listening session in which every participant hears
          the same song at the same position.],
  [FR3], [Users can invite friends to a playlist or to a listening session.],
  [FR4], [Participants of a session can chat while they listen.],
  [FR5], [Users can search the catalogue by song title, artist or album.],
  [FR6], [Users can send, accept and decline friend requests.],
  [FR7], [A user can join a session that is already playing and start
          listening from the current position.],
)

== User stories

#table(
  columns: (auto, 1fr, auto),
  table.header([ID], [User story], [Sequence diagram]),
  [US1], [As a listener, I want to invite my friends to join my playlist so we
          can listen to songs together.], [@seq-invite],
  [US2], [As a user, I want to add songs to a shared playlist so that everyone
          can contribute to the selection.], [@seq-add],
  [US3], [As a participant in a synced session, I want to chat with friends
          while we listen to music.], [@seq-chat],
  [US4], [As a user, I want to skip, pause, or play songs, and have all users
          in the synced session stay in sync.], [@seq-sync],
  [US5], [As a friend arriving late, I want to join a session that is already
          playing and hear what the others are hearing.], [@seq-join],
)

== Non-functional requirements

#table(
  columns: (auto, 1fr),
  table.header([Area], [Requirement]),
  [Synchronization], [Participants hear the same position. A drift below
    40 ms is inaudible and left alone, a drift between 40 and 300 ms is
    corrected by slightly changing the playback rate, and a larger drift is
    corrected with a seek.],
  [Responsiveness], [A play, pause or skip by the host takes effect for
    everyone about 250 ms after the button is pressed (800 ms for a skip,
    which may need a new track to load).],
  [Availability], [Playback keeps working when a supporting service such as
    chat or notifications is down.],
  [Security and privacy], [All traffic is encrypted, authorization is checked
    by the service that owns the data, and personal data is handled according
    to the GDPR.],
  [Scalability], [The system handles the load estimated in
    @scalability, and every component can grow by adding instances.],
)

// ============================================================
= Architecture
// ============================================================

== Overview

The system is split by business capability. Each service owns its data and
its database, and no service reads another service's database. The browser
talks to two entry points: the API Gateway for ordinary requests and the
Realtime Gateway for everything live. Audio never passes through the backend;
the browser downloads it from the CDN with a short-lived signed link.

#diagram("diagrams/architecture.svg",
  [Component view of the system]) <fig-arch>

== Services

#table(
  columns: (auto, 1fr, auto),
  table.header([Service], [Responsibility], [Data store]),
  [API Gateway], [Single entry point for REST requests. Validates JWTs,
    applies rate limits and routes requests to services.], [none],
  [Realtime Gateway], [Holds the WebSocket connections of all online users and
    pushes events to them.], [Redis],
  [Identity], [Registration, login (OIDC), access and refresh tokens.],
    [PostgreSQL],
  [User & Social], [Profiles, friendships and invitations to playlists and
    sessions.], [PostgreSQL],
  [Playlist], [Shared playlists, collaborators and their roles, adding,
    removing and reordering songs.], [PostgreSQL],
  [Catalog], [Song, album and artist metadata, and search.],
    [PostgreSQL, OpenSearch],
  [Media], [Issues signed links to the HLS audio files.],
    [Object storage, CDN],
  [Listening Session], [Owns the playback state of every session and orders
    the host's commands.], [Redis],
  [Chat], [Stores and distributes chat messages of a session.], [Cassandra],
  [Notification], [Sends push and e-mail notifications in reaction to
    events.], [none],
)

Invitations live in the User & Social service because they depend on
friendships: only friends can be invited, and the friendship check is local
to that service.

== Communication

The services use four styles of communication, each for a different job.

1. *REST over HTTPS*, through the API Gateway, covers request and response work
such as creating a playlist, searching or accepting an invitation.

2. *WebSocket* connections, through the Realtime Gateway, carry everything that
has to arrive immediately: playback commands, playback state, chat messages
and playlist changes.

3. *Kafka* carries durable domain events such as `InvitationCreated`,
`PlaylistTrackAdded` or `ChatMessageSent`. A service publishes an event
without knowing who consumes it. The Notification service, for example,
sends a push message when an invitation is created, and the Social service
does not know it exists.

4. *Redis* publish/subscribe is used on the synchronization path, where a few
milliseconds matter more than durability. A lost state message is harmless
because the next one replaces it, and a client that reconnects receives the
full state anyway.

== Technology choices

#table(
  columns: (auto, 1fr),
  table.header([Technology], [Why it is used here]),
  [Kafka], [A durable event log. Services stay decoupled, events of one
    playlist stay in order, and new consumers can replay the history.],
  [Redis], [In-memory store with publish/subscribe. Session state is read and
    written constantly and needs millisecond latency.],
  [Cassandra], [Distributed database built for heavy write loads. Chat is
    almost only writes and reads of the latest messages of one session.],
  [OpenSearch], [Full-text search with typo tolerance for the catalogue.],
  [Object storage and CDN], [Cheap storage for audio files, delivered from
    servers close to each listener.],
  [HLS], [Audio split into short segments, so playback starts fast, seeking
    is cheap and the bitrate adapts to the network.],
  [OIDC and JWT], [Standard login, and signed tokens every service can verify
    on its own.],
)

== Synchronization at a glance

The Listening Session service is the single source of truth for playback. It
stores the state of each session as:

```json
{
  trackId,
  positionMs,
  startedAt,
  isPlaying,
  version
}
```

and never updates the position while a song plays. The current position is
computed from the moment playback started:
`positionAt(t) = positionMs + (t - startedAt)` while playing.

When the host presses a button, the service checks that the command comes
from the host and is based on the latest `version`, increments the version,
and broadcasts the new state with an execution time about _250 ms_ in the
future. Each client knows the offset between its own clock and the server's,
so all of them apply the change at the same moment. @behaviour explains
the mechanism in detail.

// ============================================================
= Domain model
// ============================================================

== Modelling rules

Each service owns its classes. A class never holds an object that belongs to
another service; it holds only that object's identifier. A `PlaylistEntry`
stores a `trackId`, for example, and the Track itself stays in the Catalog
service. In the diagrams, solid lines are associations inside one service.
Dashed arrows marked `«ref by ID»` are references across services. Classes
that belong to another service appear in grey with the stereotype
`«external»` and without their members.

This rule keeps services independent. A service can change its internal
model, or its database, without breaking the others, as long as identifiers
and APIs stay the same.

#diagram("diagrams/class-overview.svg",
  [Overview of the domain classes, grouped by service]) <fig-class-overview>

== Identity service

#diagram("diagrams/class-identity.svg",
  [Classes of the Identity service], width: 70%) <fig-class-identity>

A `UserAccount` holds the e-mail address and a password hash, never the
password itself. Refresh tokens are stored as hashes as well, so a leaked
database does not give an attacker usable tokens.

== User & Social service

#diagram("diagrams/class-social.svg",
  [Classes of the User & Social service]) <fig-class-social>

One `Invitation` class covers both kinds of invitation. The fields
`targetType` and `targetId` say whether it points to a playlist or a session,
so invitations to playlists and sessions share one table, one API and one
expiry rule.

== Playlist service

#diagram("diagrams/class-playlist.svg",
  [Classes of the Playlist service]) <fig-class-playlist>

The order of songs is stored in `PlaylistEntry.position`, a string used for
fractional indexing. To move a song between the entries at positions `"a"`
and `"b"`, the service gives it a position such as `"an"` that sorts between
them, and no other row is renumbered. Two collaborators can add or move songs
at the same moment without overwriting each other's work.

`Playlist.version` increases with every change. Clients use it to notice a
missed update: when a change arrives with a version that skips a number, the
client reloads the playlist.

The methods `nextEntryAfter` and `previousEntryBefore` support the live link
between a session and its playlist. The session remembers only the position
of the current entry and asks for the next one when the song ends or the host
skips. A song a friend adds during the session is therefore played when the
session reaches it. Even if someone removes the song that is currently
playing, the next entry is still found by its position.

== Catalog service

#diagram("diagrams/class-catalog.svg",
  [Classes of the Catalog service], width: 70%) <fig-class-catalog>

The catalogue is mostly read. PostgreSQL is the source of truth and
OpenSearch holds a copy of the same data, indexed for full-text search.

== Media service

#diagram("diagrams/class-media.svg",
  [Classes of the Media service], width: 70%) <fig-class-media>

An `AudioAsset` describes the HLS files of one track. A `StreamGrant` is a
signed link to those files that expires after a few minutes. The CDN checks
the signature, so a copied link quickly stops working.

== Listening Session service

#diagram("diagrams/class-session.svg",
  [Classes of the Listening Session service]) <fig-class-session>

`ListeningSession.apply(cmd)` handles every playback command. It first calls
`requireHost`, which rejects any command whose `issuedBy` differs from
`hostId`. It then compares `cmd.expectedVersion` with the current
`PlaybackState.version` and rejects commands based on an outdated state.

`PlaybackState` does not change while a song plays. It stores the position at
the moment playback started and the time `startedAt`, and
`positionAt(now)` computes the current position from them. The state changes
only when a command arrives, which keeps writes to Redis rare.

`invitedUserIds` lists the users who accepted an invitation; only they can
join. A session ends when the host leaves it explicitly or stays disconnected
for more than 60 seconds. The grace period keeps a short network drop on the
host's side from ending the session for everyone.

== Chat service

#diagram("diagrams/class-chat.svg",
  [Classes of the Chat service], width: 70%) <fig-class-chat>

Messages are identified by a `TimeUUID`, which contains a timestamp and
therefore sorts by time. `SYSTEM` messages announce events in the session,
such as a friend joining or the host skipping a song.

In Cassandra, the table of messages is partitioned by
`(session_id, bucket)`, where the bucket is a time window such as one day. A
long or busy session thus spreads over several partitions instead of growing
one very large partition, which was one of the problems Discord ran into. A
second table, `messages_by_sender`, lists the messages of each user, because
Cassandra can only look rows up by their partition key and deleting an
account requires finding all of that user's messages.

// ============================================================
= Behaviour <behaviour>
// ============================================================

== Theoretical foundation

The synchronization design applies a few classic results from distributed
systems.

#table(
  columns: (1fr, 1fr),
  table.header([Mechanism in this system], [Concept]),
  [The Listening Session service orders all commands of a session and stamps
   each with a `version`.],
  [A single sequencer imposing a total order. The version number is a logical
   clock in the sense of Lamport's "Time, Clocks, and the Ordering of Events
   in a Distributed System": events are numbered, and every replica
   agrees on their order without relying on physical clocks.],
  [Every client applies the same commands in the same order and reaches the
   same playback state.],
  [State machine replication. Each client is
   a deterministic replica of the `PlaybackState` machine.],
  [A command with an outdated `expectedVersion` is rejected.],
  [Optimistic concurrency control.],
  [Clients estimate the offset of their clock with a ping exchange and keep
   the sample with the lowest round trip.],
  [Cristian's algorithm, a simple relative of NTP.],
  [A command takes effect at `executeAt`, about 250 ms in the future.],
  [Synchronized physical clocks used to agree on when an event takes
   effect.],
)

The two kinds of time do different jobs. The logical clock, `version`,
decides the order of events and guarantees that all clients end in the same
state. Physical time, `executeAt` corrected by the clock offset, only makes
them reach that state at the same moment. If clock synchronization is a few
milliseconds off, people hear a change a few milliseconds apart, but nobody
ever ends up in a different state. This is Lamport's separation of ordering
from real time, applied to music playback.

== Clock synchronization

When a client joins a session, it sends several pings over the WebSocket.
For each one it records the local send time `t0`, the server time from the
reply and the local receive time `t1`:

$
  "rtt" = t_1 - t_0
  "offset" = "serverTime" - (t_0 + t_1) / 2
$


The estimate assumes the request and the reply take the same time, so its
error is at most half the round trip. The client keeps the offset from the
sample with the lowest round trip, because that sample has the smallest
possible error. It converts every `executeAt` from server time to local time
with `localTime = executeAt - offset`.

== Changes of the playback position

The position can change for three reasons, and each is handled differently.

The host can seek on purpose, for example from 1:20 to 1:35. The client
sends a single `SEEK` command when the host releases the slider, instead of
one for every movement. The server sets `positionMs` to the new value and
`startedAt` to the execution time, increments the version and broadcasts the
new state. A client that receives the message late does not jump to 1:35; it
jumps to `positionAt(now)`, the position the others have already reached. A
client that has not buffered the new position first loads the HLS segment,
then starts from `positionAt(readyTime)`, so a slow connection catches up
with the group instead of holding it back.

A listener's player can also drift on its own because of buffering, CPU load
or slightly different clock speeds. Every few seconds each client compares
its position with `positionAt(now)`:

#table(
  columns: (auto, 1fr),
  table.header([Drift], [Correction]),
  [under 40 ms], [none, it is not audible],
  [40 to 300 ms], [the playback rate changes slightly, for example to 1.03
    or 0.97, until the drift is gone; browsers keep the pitch unchanged],
  [over 300 ms], [the player seeks to the correct position],
)

The thresholds are design parameters and can be tuned.

A listener who is not the host cannot seek at all. The slider is read-only
in the interface, and if a client sends a `SEEK` command anyway,
`requireHost` rejects it on the server.

== Sequence diagrams

=== Inviting a friend to a playlist

#diagram("diagrams/seq-invite.svg",
  [Inviting a friend to a playlist (US1)]) <seq-invite>

The Social service checks two things before it creates an invitation: the two
users must be friends, and the Playlist service must confirm that the inviter
is an owner or editor. The invitation and its `InvitationCreated` event are
written in the same database transaction, a pattern called the transactional
outbox. A relay then publishes the event to Kafka. No event is lost if the
service crashes after the commit, and no event is published for a change
that was rolled back.

The event reaches the invitee in two ways at once. The Notification service
sends a push message or e-mail, and the Realtime Gateway shows the invitation
directly if the invitee is online. When the invitee accepts, the Social
service adds them to the playlist as an editor and the inviter gets a
notification.

Session invitations follow the same flow with two differences: only the host
may invite, and accepting calls `Session.allow` so the user can join.

=== Adding a song to a shared playlist

#diagram("diagrams/seq-add-song.svg",
  [Adding a song to a shared playlist (US2)]) <seq-add>

The user first searches the catalogue, which OpenSearch answers with fuzzy
matching. The Playlist service then checks that the user is an owner or
editor and that the track exists, computes a position between the
neighbouring entries, and stores the entry together with the incremented
version and an outbox event.

The event goes to Kafka with the playlist identifier as its key. All events
of one playlist land in the same partition and are consumed in order. The
Realtime Gateway forwards the change to the other collaborators, who insert
the entry at its position. If a session is playing this playlist, the new
song plays when the session reaches it.

=== Chatting during a session

#diagram("diagrams/seq-chat.svg",
  [Chatting during a synced session (US3)]) <seq-chat>

When the chat opens, the client loads the latest 50 messages over REST.
Messages are sent over the WebSocket. The Chat service checks that the sender
is a participant, using the participant set the Session service keeps in
Redis, and applies a rate limit. It stores the message in Cassandra and
publishes it on the session's Redis channel. Every Realtime Gateway node that
holds a connection of this session receives it and forwards it to its local
sockets.

The sender gets an acknowledgement carrying its own `clientMsgId` and marks
the message as sent. It also receives the broadcast copy and drops it as a
duplicate by the same identifier. An event is published to Kafka as well, for
consumers that do not need to be fast.

=== Play, pause and skip

#diagram("diagrams/seq-playback-sync.svg",
  [Keeping play, pause and skip in sync (US4)]) <seq-sync>

The host's command goes over the WebSocket to the Listening Session service,
which loads the state from Redis and performs the two checks described in
the domain model. For a pause, it computes the position at the execution
time, stops playback in the new state and increments the version. The
state is written with an atomic compare-and-set that succeeds only if the
version has not changed in the meantime, so two instances of the service can
never both apply a command to the same version.

A skip asks the Playlist service for the entry after the current position.
The lead time is longer, 800 ms, because clients may need to load the new
track; most of them have already prefetched it. A client that receives the
state after the execution time starts at `positionAt(now)` and is in sync
immediately.

=== Joining a session in progress

#diagram("diagrams/seq-join-session.svg",
  [Joining a session that is already playing (US5)]) <seq-join>

The friend opens a WebSocket with their token and asks to join. The Session
service checks that the session is still active and that the user is in
`invitedUserIds`, adds them to the participants and returns the current
state together with the server time. The other participants see a "joined"
message.

The client then synchronizes its clock as described above, gets a stream
link from the Media service and downloads from the CDN the segment that
contains `positionAt(now)`. As soon as the audio is ready it seeks to the
position for that moment and starts playing. Finally it loads the chat
history.

// ============================================================
= Security and privacy
// ============================================================

== Authentication

Users log in with e-mail and password through the Identity service, which
follows the OIDC standard. Passwords are stored only as Argon2id hashes. The
algorithm is deliberately slow and memory-hungry, so guessing passwords from
a leaked database is expensive.

After login the client receives two tokens. The access token is a JWT valid
for 15 minutes. It is signed by the Identity service, so every other service
can verify it with Identity's public key without calling Identity. The
refresh token is valid for 30 days and is used only to get a new access
token. It lives in an `HttpOnly` cookie that JavaScript cannot read, and the
database stores only its hash.

The WebSocket connection is authenticated with the same access token when it
opens. When the token expires, the client sends a fresh one over the open
connection; otherwise the server closes it.

== Authorization

The API Gateway only establishes who the user is. Whether the user may do
something is decided by the service that owns the data, because only that
service knows the rules. The user's identity always comes from the verified
token and never from the request body or URL, so a user cannot act as
someone else by changing an identifier in a request.

#table(
  columns: (1fr, 1fr, auto),
  table.header([Action], [Allowed for], [Checked by]),
  [Edit a playlist], [the owner and editors], [Playlist],
  [Invite to a playlist], [the owner and editors, and only friends can be
    invited], [Social, Playlist],
  [Invite to a session], [the host, and only friends can be invited],
    [Social, Session],
  [Join a session], [invited users], [Session],
  [Play, pause, skip, seek], [the host only], [Session],
  [Send and read chat], [session participants], [Chat],
  [Get an audio stream], [any logged-in user], [Media],
)

== Data in transit and at rest

All traffic between browsers and the system uses TLS, as HTTPS for requests
and WSS for WebSockets. The services run in a private network, and traffic
between them is encrypted as well.

Databases, file storage and backups are encrypted on disk. Database
passwords, signing keys and other secrets are kept in a secrets manager and
never in source code or container images.

The audio bucket is private and only the CDN can read from it. A listener
receives a signed link that is valid for a few minutes, so a shared link
stops working shortly after it was issued.

== Common attacks

#table(
  columns: (auto, 1fr),
  table.header([Attack], [Protection]),
  [Script injection through chat (XSS)], [Messages are stored as plain text
    and displayed as text, never as HTML.],
  [SQL injection], [Only parameterized queries are used.],
  [Spam and flooding], [Rate limits on the gateway and on WebSocket
    messages, for example at most 5 chat messages per second.],
  [A listener trying to control playback], [The server checks that every
    command comes from the host. Hiding the buttons in the interface is only
    a convenience.],
)

== GDPR

The application processes personal data of users in the EU, so it falls
under the GDPR.

The system collects only what it needs to work: the e-mail address, the
display name, playlists, session participation and chat messages. It does
not ask for a location, phone number or date of birth. Processing this data
is necessary to provide the service, which is the legal basis of a contract.
Marketing e-mails are sent only with the user's consent, which can be
withdrawn at any time.

Users can exercise their rights from the application:

- Access and portability: the user downloads all of their data as a file.
- Rectification: the user edits their profile and e-mail address.
- Erasure: the user deletes their account, as shown in @seq-delete.

Data is not kept longer than needed:

#table(
  columns: (1fr, auto),
  table.header([Data], [Retention]),
  [Chat messages], [12 months],
  [State of an ended session], [24 hours],
  [Expired invitations], [30 days after expiry],
  [Logs (with a pseudonymous user identifier)], [90 days],
  [Account data], [until the account is deleted],
)

#diagram("diagrams/seq-delete-account.svg",
  [Deleting an account]) <seq-delete>

When a user deletes their account, the Identity service deactivates it, logs
the user out everywhere and publishes a `UserDeleted` event. Every service
that holds data about the user reacts to the event and deletes its own part.
The Social service removes the profile, friendships and invitations. The
Playlist service hands each owned playlist to an editor, or deletes it if
there is none, so friends do not lose a shared playlist. The Session service
ends sessions hosted by the user, and the Chat service finds the user's
messages through `messages_by_sender` and deletes them.

// ============================================================
= Scalability <scalability>
// ============================================================

== Load estimate

The estimate starts from the following assumptions.

#table(
  columns: (1fr, auto),
  table.header([Assumption], [Value]),
  [Registered users], [1,000,000],
  [Daily active users], [100,000],
  [Concurrent sessions at peak], [10,000],
  [Average listeners per session (limit 50)], [5],
)

#table(
  columns: (1fr, 1fr, auto),
  table.header([Load], [Calculation], [Result]),
  [Concurrent WebSocket connections], [10,000 × 5], [≈ 50,000],
  [Playback commands], [10,000 sessions × 1 per minute], [≈ 170 / s],
  [State messages sent to clients], [170 × 5], [≈ 850 / s],
  [Chat messages written], [50,000 users × 1 per 30 s], [≈ 1,700 / s],
  [Chat messages delivered], [1,700 × 5], [≈ 8,500 / s],
  [Audio bandwidth], [50,000 × 160 kbps], [≈ 8 Gbps],
)

The business logic itself is light. The two real costs are audio bandwidth,
which the CDN absorbs, and a large number of long-lived WebSocket
connections, which the Realtime Gateway handles. The design concentrates on
those two.

== Scaling each component

#table(
  columns: (auto, 1fr),
  table.header([Component], [Strategy]),
  [API Gateway, Social, Playlist, Catalog, Media, Notification], [Stateless.
    More instances run behind the load balancer, and Kubernetes adds them
    automatically based on CPU use or request rate.],
  [Realtime Gateway], [Also stateless, since connections are registered in
    Redis and not in the node's memory. One node holds about 10,000 to
    20,000 connections, so 4 to 6 nodes cover the estimate. A client does
    not need to stay on the same node.],
  [Listening Session], [Several instances. The atomic compare-and-set in
    Redis acts as the sequencer, so every session has exactly one order of
    commands whichever instance handles them.],
  [Redis], [Redis Cluster, sharded by `{sessionId}` so all keys of one
    session live on the same shard. Sharded publish/subscribe (`SPUBLISH`,
    Redis 7 and later) sends a session's messages only within the shard that
    owns it.],
  [PostgreSQL], [Read replicas for reads and a Redis cache for popular
    playlists. A database that grows too large can be sharded by `userId` or
    `playlistId`, which is unlikely at this scale.],
  [Catalog], [Mostly reads, served by OpenSearch replicas and caching. Album
    covers go through the CDN.],
  [Media and CDN], [The CDN caches HLS segments close to listeners. Popular
    songs are almost always served from the cache, so object storage sees
    little traffic.],
  [Cassandra], [Capacity grows in proportion to the number of nodes. Data is
    replicated three times, and reads and writes use `LOCAL_QUORUM`. The
    partition key `(session_id, bucket)` keeps partitions small.],
  [Kafka], [Topics are partitioned by key, such as `playlistId` or `userId`.
    Consumers scale up to the number of partitions; 12 to 24 partitions per
    topic leave room to grow.],
)

#diagram("diagrams/deployment-scaling.svg",
  [Deployment and scaling of the system]) <fig-deployment>

== Resilience

#table(
  columns: (auto, auto, 1fr),
  table.header([Failure], [Effect], [Handling]),
  [A Realtime Gateway node crashes], [Its clients lose the connection],
    [Clients reconnect to another node with exponential backoff and random
     jitter, join the session again and receive the current state. The music
     keeps playing locally in the meantime.],
  [A Session service instance crashes], [None visible],
    [The state is in Redis, so another instance continues.],
  [A Redis primary fails], [A few seconds without commands],
    [A replica is promoted automatically. Clients keep playing from their
     last state, and the host's command is retried.],
  [The Chat service is down], [No chat],
    [Playback keeps working, because chat and synchronization do not depend
     on each other.],
  [The Playlist service is slow], [A skip is delayed],
    [A circuit breaker in the Session service, and the next entry is fetched
     before the current song ends.],
  [A Kafka consumer falls behind], [Notifications arrive late],
    [Events stay in Kafka, so nothing is lost and the consumer catches up.],
)

== Monitoring

The most important quality metric is synchronization drift. Clients report
the difference between their position and `positionAt(now)`, and the system
tracks its median and its 95th and 99th percentiles. The other metrics are
WebSocket connections per node and the reconnection rate, the time from the
host pressing a button to the broadcast, Kafka consumer lag, Cassandra
latency and the CDN cache hit ratio.
