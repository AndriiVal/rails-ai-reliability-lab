# Application architecture

A conventional full Rails monolith runs on the Ubuntu host. PostgreSQL 17 runs
alone in project-scoped Docker Compose, bound to loopback port 5433. Development
and test databases have distinct names. LlmRun stores metadata only; classification never persists inputs or results.

GET /lab renders an interactive server-rendered dashboard with Tailwind and
existing local assets. POST /lab/run works without JavaScript and requires CSRF.
LabAuthentication is shared by LabController and the classification controller;
it rejects absent/blank configuration and securely compares both credentials.
GET /up remains the public Rails boot health check, without database diagnostics.

POST /api/v1/classifications uses ActionController::API, without browser sessions
or cookies. Browser ApplicationController retains its CSRF protection. The API
controller owns media type, bounded JSON parsing, root/key checks, UUID creation,
status mapping and safe serialization. It clears Rails' parsed-body parameter
cache before instrumentation so raw bodies never enter automatic parameter logs.
It reads only 16,385 bytes to enforce a 16,384-byte limit, independently of the
Content-Length header; it does not use Rails' automatic body parser or wrapping.

TicketClassifier normalizes and validates input, selects only the server-configured
Fake or guarded Anthropic provider, and delegates execution and strict output validation to
Reliability::Runner. The runner measures elapsed time with its injected
monotonic clock. Expected application errors use TicketClassifier::Error
with a controlled code and actual attempt count. ClassificationValidator::InvalidOutput
remains distinct at the provider-output boundary. Unexpected programming exceptions
propagate from the service; the API returns a controlled 500 and logs only an
error class and opaque request ID, never the exception message or raw input.

Providers::Fake is stateless. It performs deterministic keyword matching and
returns fixed synthetic JSON summaries in Providers::Response. ClassificationValidator strictly
checks exactly four fields, enums, summary length/type and the actual boolean,
then freezes the result and its values. Each call accepts ticket_text, scenario,
attempt (one-based) and an explicit positive timeout_seconds budget. Sequences
are selected by this per-execution attempt number; no request state is stored
in the Fake Provider, including when an instance is used concurrently.

Reliability::Runner alone owns retries. All counters, start times and deadlines
are local to one call. RetryPolicy holds validated constructor settings: 1–3 total
attempts, positive finite timeout limits and finite nonnegative backoff values.
Default limits are 3 calls, 8 seconds per attempt and 25 seconds overall. The
runner checks time before every call, caps its budget to remaining time, classifies
late returns and typed failures as transport timeouts, and checks output-validation
completion against the overall deadline.
Known provider failures carry safe status/kind/Retry-After metadata, not raw bodies.
Unknown Ruby exceptions propagate to the existing safe API 500 boundary.

RetryPolicy handles transient-only classification, header parsing and exponential
backoff with bounded jitter. A separate wall-clock callable interprets HTTP dates;
elapsed time and deadlines never use wall-clock time. The explicit production
Sleeper calls Kernel.sleep; unit/request tests inject a virtual clock and sleeper.
Early sleeper returns are rechecked so a valid header minimum is never shortened.
A non-advancing injected sleeper fails closed rather than creating a busy loop.
No thread interruption or Timeout.timeout is used. See FAILURE_SCENARIOS.md for
exact delay/date policies and cooperative execution limitations.

LlmConfiguration provides fake/disabled defaults and strict boolean parsing.
Unknown providers and incomplete Anthropic configuration fail closed before
client construction. No API key or outbound HTTP is required in default fake mode.

Providers::Response is a small immutable shared contract containing original JSON
body, model, optional final-response tokens and an optional internal provider ID.
Runner validates body with ClassificationValidator and returns the response
alongside validated result/count/latency. TicketClassifier exposes only allowed
metadata. SDK types remain inside Providers::Anthropic.

The opt-in Anthropic adapter owns fixed v1 system instructions, server-owned
schema/model, max_tokens 512, SDK timeout propagation and typed error translation.
SDK retries and telemetry are disabled. A per-invocation SDK middleware pins the
Messages URL, replaces outbound headers, blocks redirect sends and reads only
a safe opaque request ID. Strict independent JSON validation still rejects values
that the upstream grammar does not constrain (notably summary length).

The API catches action errors locally before Rails 8.1 rescue_from instrumentation,
which otherwise logs exception messages. Unexpected failures log class/UUID only.
The adapter introduces no new retry layer. Metadata recording and terminal Rails
events now belong to the shared application workflow, outside the SDK. See
[Anthropic setup](ANTHROPIC_SETUP.md) for released-SDK evidence and limitations.

ClassificationWorkflow is shared by UI/API. TicketClassifier validates input,
scenario and opt-in configuration, then yields explicit provider/model/scenario
metadata before execution. RunRecorder inserts started before any provider call;
a completed outcome or controlled failure updates the same row conditionally
from started. It never holds a transaction across retries or network calls.
Only the winning terminal update publishes the allowlisted Rails event. API UUID
creation remains at the HTTP boundary; the same UUID is passed to the workflow.

LabController injects fake configuration and Providers::Fake directly, independent
of global real settings. It filters all form parameters before controller logging,
uses a bounded form parser, authenticates before CSRF verification and renders
escaped result text directly after POST. History is one indexed query for the
latest ten fake rows. Current input is not placed in session/flash/cookies/URLs.

Initial recording failures fail closed before invocation; terminal write/event
failures never retry the provider. Crash gaps can leave started rows or missing
events. There is no outbox/recovery worker. The subscriber registers once at boot
and implements Rails 8.1.4 emit(event), logging only six payload fields plus name.
See [dashboard architecture and retention](DASHBOARD.md) for the exact schema,
metadata allowlists, database model-name compatibility and failure limits.
