# Interactive simulation and local metadata

The authenticated `/lab` page is a server-rendered, Fake-only demonstration.
Use the local setup in README, prepare PostgreSQL and open `/lab` on loopback.
The two-column desktop layout stacks on mobile; the history table scrolls within
its container. All labels, native controls, focus outlines, result headings and
validation messages work without JavaScript. No SPA, browser driver dependency,
new frontend framework or automatic network-enabled demo is required.

[Desktop capture](images/dashboard-desktop.png) · [Mobile capture](images/dashboard-mobile.png)

These captures show synthetic localhost execution results. Latency is an observed
sample, not an SLA or real AI benchmark. Screenshots were taken from a static copy
of the rendered response with CSRF tokens removed; functional checks used the
actual Rails application, server-generated tokens and cookies.

## Run a scenario

1. Authenticate with your privately configured local Basic Auth credentials.
2. Enter an invented support ticket (10–3,000 Unicode characters).
   Unicode length is enforced by the server; the form avoids UTF-16-based native
   maxlength so supplementary characters do not receive an artificial lower cap.
3. Choose one of the eight described scenarios and submit **Run scenario**.
4. Read the classification or controlled error, HTTP-equivalent outcome, actual
   attempt count, measured monotonic elapsed time and short request reference.

All eight scenarios are documented in [Failure scenarios](FAILURE_SCENARIOS.md).
Success/failure results are rendered directly on POST, without persisting input
in a redirect, flash, session, cookie or URL. Ticket text can remain in the current
form for editing, but a later GET uses the default synthetic example. The page
sets Cache-Control no-store. Successful summaries are escaped text. These are
keyword fixtures, not real AI quality evaluations. Retry explanations describe
the configured simulation and observed invocation count, not invented traces.

## Why browser execution is always Fake

`LabController` constructs TicketClassifier with an application-owned fake
configuration and an explicit Providers::Fake instance. It never changes ENV or
Rails global configuration. Real-provider flags, credentials and model selection
cannot enable Anthropic from `/lab/run`. Browser fields cannot select a provider,
model, key, endpoint or retry budget. GET requests never classify anything.

The JSON API retains its separately guarded optional Anthropic path. No real
Anthropic call was made for this milestone; SDK requests remain mocked in tests.

Authentication runs before browser CSRF verification. POST requires a real Rails
authenticity token tied to the browser session; Basic Auth does not exempt it.
Missing/invalid tokens return 422. The browser action reads at most 65,537 bytes
and rejects a form over 64 KiB (allowing percent-encoded 3,000-character Unicode input) or unsupported media type. All form parameters are
filtered before controller instrumentation, including unknown fields. Action-local
exception handling avoids Rails 8.1 rescue_from logging sensitive messages.
Do not put secrets or ticket data in query strings or enable proxy body capture.

## Shared execution and metadata lifecycle

The API and browser both use ClassificationWorkflow around TicketClassifier.
Input, scenario and provider configuration are validated before the classifier
calls its metadata-only pre-execution block. Only then does RunRecorder insert
one started row. Invalid/malformed requests, failed authentication, CSRF failures
and disabled-provider/configuration rejections are excluded from recording and
terminal events. An invalid request can still receive an application UUID, but
it is not an accepted run. No authenticated SDK client is constructed for a
disabled configuration or failed initial recording.

The API returns the same server-generated request UUID stored in the row/event.
The browser generates a new UUID and displays only its first eight characters.
Clients cannot set a trusted UUID. The shared workflow executes the classifier
once; Runner still owns all provider retries. Controlled failures preserve Runner
attempt count and latency. Unexpected exceptions use internal_error and null
attempt count/latency because those values are unknown.

RunRecorder uses short database operations before and after execution, with no
transaction held over a provider request or retry sleep. It validates explicit
terminal metadata, then conditionally updates only a row still marked started.
Only the winning transition publishes an event. Competing/duplicate completions
cannot overwrite a terminal result or publish a second event.

## Schema and value bounds

Migration `20261020090000_create_llm_runs` creates a PostgreSQL bigint id plus:
request_id (unique 36-character UUID), provider (16), model_name (100), optional
scenario (40), status (16), nullable integer attempt_count/latency_ms/input_tokens/
output_tokens, optional error_code (40), bounded provider_request_id (104),
completed_at and standard timestamps. There are no content or generic JSON columns.

A composite `(provider, created_at)` index supports the recent-history query.
PostgreSQL constrains provider/status enums and nonnegative nullable numbers.
Model validations enforce UUIDs, model/scenario/error allowlists, identifier shape,
status/completion consistency, integer values and terminal immutability.
The required model_name column collides with an ActiveModel instance helper;
LlmRun permits that one attribute locally, preserving its class-level Rails
model_name and all other dangerous-attribute protections.

Fake rows use fake-v1, null token usage and no provider request ID. Real API rows
use an allowlisted model, final-success SDK usage (not total billing) and an
optional safe opaque request ID. No ticket, prompt, completion, summary, API key,
Authorization header, SDK exception or raw external metadata is stored.

History is authenticated, Fake-only, newest first and limited to ten rows with
one indexed query and no N+1 associations. It shows scenario/status/attempts/
latency/error/timestamps in UTC, never full UUIDs or real-provider rows. There is
no history API, arbitrary record lookup, bulk export or public hosting feature.

## Native structured-event contract

The inspected Rails 8.1.4 EventReporter implements
`Rails.event.notify(name, payload)` and calls subscribers as **emit(event)**
(positionally). RunEventSubscriber is registered once at boot with an event-name
filter, so development reloads do not duplicate registration. Temporary test
subscribers are unsubscribed in ensure blocks.

One terminal event is attempted after a successful database terminal transition:

```ruby
Rails.event.notify("llm.classification.finished", {
  request_id: application_uuid,
  provider: "fake",          # or guarded API anthropic
  outcome: "succeeded",      # or failed
  attempt_count: 1,           # nil if unknown after an unexpected exception
  latency_ms: 12,             # nil if unknown
  error_code: nil             # or controlled failure code
})
```

The payload is assembled from exactly those six metadata fields. The minimal
subscriber writes only this allowlist and the event name as local JSON log data;
it does not serialize Rails context/tags, model objects or exceptions. Provider
request IDs and input/output token details are not event fields. SDK tracing
remains disabled. No exporter or external monitoring system is added.

## Recording failures and crash limits

If initial recording fails, execution fails closed with a safe HTTP 500 and zero
provider calls. If terminal recording fails after classification, its result is
preserved; there is no second provider call. The row may remain started, and no
terminal event is published for a transition that was not stored. If event
publication fails, the completed row remains intact; diagnostics contain only
the error class and opaque UUID, and no provider retry is attempted.

Synchronous execution has no outbox or crash recovery. A process crash can leave
a started row or omit an event after database completion. Terminal delivery is
best effort, not a transactional exactly-once event guarantee. A failed subscriber
cannot repeat classification; additional subscriber integrations must preserve
privacy and avoid attaching content to Rails reporter context. An unavailable
history query shows an empty unavailable state rather than triggering execution.

## Manual retention and remaining work

Metadata stays only in the dedicated local PostgreSQL database and safe local
logs. Recommend manually removing rows older than **30 days**. There is no cron,
scheduled cleanup, worker or new cleanup task. First inspect a count in a trusted
local Rails console using `LlmRun.where("created_at < ?", 30.days.ago).count`.
If the owner elects to delete that metadata, use the same scoped relation's
`delete_all` in that project database only. Do not delete volumes or unrelated
records. No content deletion is needed because content was never recorded.

Rotate local logs under your existing local policy. Keep the database and logs
private. These controls are a compact demonstration, not public-service traffic
management, production monitoring, audit-grade storage or a billing ledger.
Milestone 6 remains the final documentation/sample audit/release review; it is
not implemented as part of this dashboard change. No deployment is authorized.
