# Optional Anthropic adapter

Fake is the default. Ordinary development and CI need no API key and make no
Anthropic requests. No live API call was made during this implementation.
Only synthetic tickets are permitted. This is a localhost engineering lab,
not a production service or an accuracy/billing benchmark.

## Verified dependency and model

The official `anthropic` gem is pinned to **1.80.0**, with checksums in
Gemfile.lock. RubyGems listed this as the latest stable release on 2026-10-19;
its requirement is Ruby >=3.2. Installation and mocked SDK tests run on Ruby
4.0.6 and Rails 8.1.4. Only its required `opentelemetry-api` and
`standardwebhooks` dependencies were added; existing versions did not change.
The telemetry API dependency does not enable application telemetry: the client
explicitly sets `open_telemetry: false`.

The initial allowlist contains only **`claude-haiku-4-5-20251001`**. Official
model lifecycle documentation lists it as active, and the structured-output
compatibility list includes Haiku 4.5. It is a small, lower-cost classification
model with a dated snapshot and no adaptive-thinking setup required. This choice
favors a simple verified request contract over adding several model modes.
Account access, quota and actual response latency remain unverified. There is no
alias substitution, model upgrade or fallback. Review the lifecycle again before
an authorized live experiment; changing the allowlist requires a code review.

Sources consulted:

- [RubyGems released gem metadata](https://rubygems.org/gems/anthropic/versions/1.80.0)
- [Official Ruby SDK docs](https://platform.claude.com/docs/en/cli-sdks-libraries/sdks/ruby)
- [Official SDK source](https://github.com/anthropics/anthropic-sdk-ruby)
- [SDK structured-output helpers](https://github.com/anthropics/anthropic-sdk-ruby/blob/main/helpers.md)
- [Structured outputs and supported schema features](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)
- [Model IDs and snapshot semantics](https://platform.claude.com/docs/en/about-claude/models/model-ids-and-versions)
- [Model lifecycle](https://platform.claude.com/docs/en/about-claude/model-deprecations)

Implementation was checked against the **released gem**, not only GitHub main:
`lib/anthropic/client.rb`, `resources/messages.rb`, `request_options.rb`,
`middleware.rb`, `errors.rb`, `helpers/messages.rb` and
`internal/transport/{base_client,pooled_net_requester}.rb`.

## Guard and configuration

Keep normal settings as follows:

```dotenv
LLM_PROVIDER=fake
ENABLE_REAL_LLM=false
ANTHROPIC_API_KEY=
ANTHROPIC_MODEL=
```

Real mode requires all of: server selection `anthropic`; a trimmed,
case-insensitive `true` flag (other values remain disabled); a nonblank API key;
and an exact allowlisted model. A missing prerequisite yields HTTP 503
`provider_disabled` with zero attempts and no authenticated SDK client creation.
Unknown providers also fail closed. Basic Auth and input validation remain in
front of API execution. Request JSON cannot set provider, model, key, endpoints,
prompts, tools, retry options or budgets.

For an explicitly approved local experiment, configure a personal key privately
in your own ignored environment file, set `LLM_PROVIDER=anthropic`,
`ENABLE_REAL_LLM=true`, and `ANTHROPIC_MODEL=claude-haiku-4-5-20251001`. Export
that reviewed file as described in README and restart Rails. Never paste the key
into chat, GitHub, screenshots or command arguments. Do not use employer keys.
Only an omitted `scenario` field is accepted in real mode; even explicit
`"success"` or `null` returns HTTP 422. Fake mode keeps its default success
scenario and all eight simulations.

The client always uses `https://api.anthropic.com`, ignoring `ANTHROPIC_BASE_URL`.
Explicit API-key credentials prevent ambient auth/profile fallback. Per-request
middleware replaces outbound headers with application-owned JSON/version/key
headers, removing ambient `ANTHROPIC_CUSTOM_HEADERS` and incoming Authorization.
It checks the exact Messages URL and permits only one send per invocation,
blocking same-origin and cross-origin redirects. SDK tracing is explicitly off,
even if enabled by ambient SDK variables. Host TLS trust, DNS, proxies and other
process-level instrumentation remain the operator's responsibility; do not enable
HTTP body capture or untrusted proxy/TLS settings.

## Request, validation and reliability

`Providers::Anthropic#classify` retains Runner's ticket_text, timeout_seconds,
attempt and scenario interface (scenario must be nil). It sends one
`client.messages.create` request with fixed system instructions, `PROMPT_VERSION`
`v1`, ticket text in one user message, **max_tokens 512**, and
`output_config: {format: {type: "json_schema", schema: ...}}`. No stream,
tools, web search, sampling overrides or caller-supplied system messages are used.
512 bounds output cost for a small JSON classification; long Unicode summaries
or a slow response may still truncate or time out. Input remains bounded to
3,000 characters. Prompt isolation is not a guarantee of semantic immunity to
injection; output is data, never instructions.

The schema requires exactly category, priority, summary and
requires_human_review, with the documented enums/types and no extra properties.
The API does not support maxLength constraints in its grammar: the summary
constraint is described in the prompt/schema description and independently
checked by ClassificationValidator. A raw schema hash avoids SDK parsed-model
helpers that might coerce classification field values. Both providers return an
immutable Providers::Response containing the original JSON text; Runner parses
and validates that text. Missing/extra fields, wrong types, string booleans and
summaries over 240 characters fail without retry. Only one text block with
`end_turn` and the exact configured model is accepted. Empty, malformed,
truncated, refusal and tool-use responses fail as invalid output.

Both client and request options explicitly set **max_retries: 0**. Inspection
verified that base_client applies this to its retry gate and pooled_net_requester
also sets Net::HTTP max_retries to zero. WebMock tests verify one outbound send
per invocation and exactly two for 429 followed by success. Runner alone owns
up to three attempts, 8 seconds per attempt and 25 seconds overall. It passes
the remaining capped budget as both client `timeout` and
`request_options: {timeout: ..., max_retries: 0}`. No default 10-minute timeout,
second retry loop or Timeout.timeout wrapper is used.

The released SDK derives a monotonic transport deadline, includes connection-pool
wait, and recalibrates Net::HTTP open/read/write timeouts and response chunk reads.
This is cooperative transport enforcement, not a hard end-to-end interruption:
Ruby scheduling, DNS/TLS internals, middleware/setup and decoding can add time.
Runner still rejects late returns/errors and checks the overall deadline.
An eight-second budget may be too short for live inference or initial schema
compilation. A timeout can still incur usage; no SLA or exactly-once billing is
claimed. Changing 8/25-second budgets needs a separate owner-approved change.

SDK translation is explicit: APITimeoutError before its APIConnectionError
parent maps to TransportTimeout; connection failures map to ConnectionFailure;
APIStatusError supplies only status and Retry-After to Providers::Error. Runner
retains 401/403 terminal auth mapping, 408/409/429/5xx retry policy and deadline
precedence. SDK conversion/JSON errors become non-retryable invalid output.
Unexpected Ruby errors retain the safe HTTP 500 path without retry. SDK exception
messages, bodies and causes are not propagated into public errors or logs.
Retry-After parsing remains exclusively in RetryPolicy.

Success metadata retains the application's UUID, measured latency and actual
attempt count. Model is the exact configured/returned allowlisted ID. Token
counts use SDK-reported nonnegative integers from the **final successful response
only**, with missing usage null. They exclude failed/ambiguous attempts, cache
accounting and any other usage fields, so they are not total billed tokens.
The documented SDK APIResponse middleware header interface provides `request-id`;
only a bounded `req_` opaque identifier is retained internally in Response. It is
not returned publicly or logged and never replaces the public UUID. The shared
workflow may store this bounded opaque value in its metadata-only row.
The adapter itself owns no storage or telemetry. The shared application workflow
now records allowlisted metadata and terminal Rails events; see
[DASHBOARD.md](DASHBOARD.md). Raw input/output remains unrecorded, and the
interactive dashboard is always Fake-only.

## Optional manual smoke test — separate authorization required

Do not run this automatically or in CI. First verify personal account billing,
quota and access to the exact model. Obtain explicit owner approval for **one
potentially billable SDK attempt**. The ordinary HTTP API can retry three times;
use this trusted local one-off service invocation to cap the manual experiment at
one attempt. It still applies the configuration/input guards and Runner output
validation; HTTP Basic Auth is an HTTP boundary, not a Rails console identity.
Do not expose a console or runner publicly.

With the approved private environment already exported, run manually:

```bash
bin/rails runner '
  policy = Reliability::RetryPolicy.new(max_attempts: 1)
  classifier = TicketClassifier.new(runner: Reliability::Runner.new(policy: policy))
  outcome = classifier.call(ticket_text: "Synthetic ticket: a duplicate subscription charge.")
  puts JSON.generate(outcome.fetch(:meta))
'
```

This prints metadata only, omits scenario, uses max_tokens 512 and performs at
most one SDK request. A failure exits without an application retry; do not rerun
without reviewing quota/billing and obtaining authorization. Verify the validated
success and actual usage, without copying content/keys into reports. Live account
access, model behavior, actual billing and latency have **not** been verified by
mocked tests. CI uses WebMock with all unmocked HTTP forbidden and no Anthropic
secrets; no manual smoke command is part of its workflow.

To return safely to fake: set `LLM_PROVIDER=fake`, `ENABLE_REAL_LLM=false`, clear
ANTHROPIC_API_KEY and ANTHROPIC_MODEL from the local environment and restart Rails.
Keep secrets out of shell history and all committed files.
