# Security and privacy

Local demonstration only; no production deployment is approved. Basic Auth needs
TLS for use beyond localhost. Do not enter client data. Personal provider keys
belong only in a private local environment for explicitly approved experiments.
The lab fails closed if either configured credential is missing or blank.
Rails secure comparison handles both credential checks; CSRF protection remains.
The public health check only reports Rails boot health, not database health.

Parameter filtering covers passwords, secrets, tokens, API keys, authorization
headers, prompts, ticket text, completions and summaries. Do not log raw headers,
request bodies or environment dumps. Parameter filtering does not sanitize
arbitrary manual log messages; keep sensitive data out of those messages.

.env, Rails master keys and credentials, compiled assets, logs, local bundles
and temporary files are ignored. .env.example contains local dummy values only.
Review shell assignments before explicitly sourcing a trusted .env file.
Do not commit keys, source employer code or use corporate services.

Configuration defaults to fake/disabled and never needs an API key. The official
Anthropic SDK is optional at runtime and requires all opt-in guards before client
construction. WebMock prevents unmocked HTTP in tests; no live request has been
made. See [Anthropic setup](ANTHROPIC_SETUP.md) for exact guards and manual policy.

Compose exposes PostgreSQL only on 127.0.0.1:5433 with project-owned persistent
storage. Do not remove volumes, change Docker socket permissions or connect to
unrelated databases. CI has read-only repository permissions, dummy credentials,
no provider keys and no deployment step. A passing scanner is only one review aid.

The classification API accepts a JSON object with only ticket_text and optional
scenario. Unknown fields, invalid UTF-8, invalid ticket lengths, malformed JSON
and oversized bodies fail before provider invocation. No arbitrary provider,
model, URL or key may be supplied. The body limit is 16,384 bytes, including JSON
syntax and escapes. Provider selection comes from trusted application configuration.

The stateless API does not use browser sessions/cookies. It inherits from
ActionController::API; browser CSRF callbacks remain on ApplicationController.
Basic Auth alone does not make this safe to expose publicly; use localhost only.
No permissive CORS policy is enabled. Credentials are never placed in URLs.

The endpoint suppresses automatic Rails body-parameter parsing before logging
and uses a bounded parser, preventing unknown-field and malformed-body leaks.
Do not enable request-body capture in proxies, middleware or external tooling.
Generic error JSON never echoes rejected input or exception messages. Unexpected
bugs log only an error class and a fresh request UUID for investigation. Query
strings are not classification inputs; do not place ticket text or secrets there.

All fake outputs pass strict application-owned schema checks. Invalid output is
non-retryable and maps to 502. Only metadata is written/emitted; no instruction
execution occurs. Browser input/results are escaped by default. Only enabled real
mode makes SDK calls; Fake never uses the SDK. The
runner alone performs bounded retry delays; the Fake Provider never sleeps.

The broad action-level StandardError handler deliberately prevents unexpected
exception messages and backtraces from reaching responses or ordinary error logs.
It logs the exception class and opaque request UUID only; internal-error attempt
counts are null because the number of invocations may be unknown. Expected
TicketClassifier::Error failures retain their specific controlled status mapping.
This limits diagnosis: the log cannot identify the failing source line, recover
the exception cause or reproduce an incident, and handled errors may not reach
normal unhandled-exception reporters. Reproduce bugs locally with synthetic data;
do not enable raw-body logging to compensate. Only allowlisted local terminal metadata events are included; no external
error-reporting system is installed. This remains a local demonstration, not production monitoring.

Retries apply only to typed transient provider failures. Timely upstream 401/403,
invalid provider output, bad input and unknown Ruby exceptions do not retry.
Error messages are controlled strings; neither raw Retry-After values nor
provider error objects are logged. Fixed fake summaries never echo input; real
summaries may reflect the synthetic ticket and are returned only to the caller.
At most three provider calls and cooperative deadline checks limit server work,
but a synchronous process cannot forcibly stop arbitrary blocking code precisely
on time. SDK transport timeout propagation is verified through mocks, not live
network latency. Do not mistake these tests for production readiness.

A typed provider failure arriving at/after its attempt deadline is classified as
transport timeout before evaluating its status or Retry-After metadata. Only the
remaining attempt/deadline budgets can permit another invocation. Valid long
Retry-After minimums never cause a shorter fallback retry. Oversized positive
decimal encodings fail closed as unfulfillable waits without float conversion
or sleeping. These remain cooperative checks, not forced Ruby interruption.

The adapter pins the official API URL, removes ambient/incoming credentials and
custom headers, and blocks redirects before a second send. It explicitly disables
SDK telemetry and retries. Prompt/schema/model/max_tokens are server-owned; real
mode rejects every explicit scenario. No tools or browsing are enabled. A fixed
prompt is a data/instruction boundary, not a guarantee against semantic injection.
SDK response text is parsed independently, never executed.

Rails 8.1 logs handled exception messages through rescue_from instrumentation.
The classification action catches expected and unexpected failures before that
subscriber, retaining controlled error codes and class/UUID-only diagnostics.
Sentinel tests cover ticket, key, prompt, completion, error body and auth privacy
for both successful and failing SDK paths, and assert metadata-only writes.
Operators must also keep proxy/HTTP instrumentation from capturing bodies.
Retries may incur additional billing even after a timeout; final-response tokens
do not represent all billed usage. Live account access, quota and latency remain
unverified. No public deployment or live automated testing is approved.

The interactive dashboard is always Fake-only, enforced by explicit server-owned
configuration/provider injection even when all global Anthropic flags are enabled.
GET never executes a classification. Browser POST authenticates before CSRF,
requires a valid session authenticity token, reads a bounded form and filters all
body fields before controller logs. It rejects configuration overrides. Current
form input can appear only in its private no-store response; it is never put in
session/flash/cookies/URLs. Summaries and ticket text are escaped without raw/html_safe.

LlmRun has only explicit scalar metadata fields, no content or JSON payload
columns. UUID/provider/model/scenario/error/identifier and numeric values are
validated. Only a status=started conditional update may complete a run; a race
cannot overwrite a terminal result or generate duplicate terminal events.
The six-field Rails event contains no prompt, ticket, summary, key, auth, response
body or user identity. The minimal subscriber ignores event context/tags and
logs only the allowlist. Tests cover HTML script injection, metadata/events/log
sentinels, real CSRF tokens, concurrency and no extra calls after failures.

History requires authentication and shows only the latest ten fake rows, without
full UUIDs. Initial DB failure prevents execution; a terminal failure can leave a
started row or missing event. No outbox or background recovery is promised.
Use the manual retention guidance in [DASHBOARD.md](DASHBOARD.md); keep local DB
and logs private. Do not enable content capture in proxies or new subscribers.

## Final review scope

The [simulated engineering audit](AUDIT_REPORT.md) describes five hypothetical
unsafe patterns and their existing controls, not five newly discovered historical
vulnerabilities. [Final verification](VERIFICATION.md#final-portfolio-audit--pr-6-2026-10-20)
records executed code scanning, bounded Git-history credential-pattern checks and
privacy tests separately. A dependency advisory scanner was unavailable, so no
advisory-clean claim is made. No live Anthropic request was performed. See
[source-code readiness and unresolved verification limits](RELEASE_READINESS.md)
before interpreting a green local quality gate as production suitability.
