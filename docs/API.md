# Synthetic ticket classification API

POST /api/v1/classifications is a localhost-only demonstration using deterministic
keyword matching by default. Anthropic inference is optional and disabled by
default; see [Anthropic setup](ANTHROPIC_SETUP.md). Export your
reviewed .env variables as described in README and start bin/dev first.

```bash
curl --user "$BASIC_AUTH_USERNAME:$BASIC_AUTH_PASSWORD" \
  --header 'Content-Type: application/json' \
  --data '{"ticket_text":"I was charged twice for my synthetic subscription.","scenario":"success"}' \
  http://127.0.0.1:3000/api/v1/classifications
```

Use dummy credentials and synthetic data. HTTP Basic credentials require TLS
outside localhost; this application is not approved for public deployment.

## Request

The root must be a JSON object with exactly ticket_text and optional scenario.
The total body limit is 16,384 bytes, including JSON syntax/escapes, enforced by
actual reads. Content-Type must be application/json (optional charset is accepted).
Malformed JSON, invalid UTF-8, an empty/non-object body, unknown fields and an
oversized body return controlled HTTP 422, without Rails parser diagnostics.
Other media types return HTTP 415 unsupported_media_type.

Ticket text must be a valid UTF-8 string containing 10–3,000 Unicode codepoints
after stripping leading/trailing whitespace, including Unicode whitespace.
Entirely blank Unicode text is rejected. Query parameters are ignored; put classification inputs only in JSON.
Provider, model, api_key, url and every other unexpected JSON field are rejected.

In fake mode, scenario defaults to success when absent; null and unknown values
are invalid. In enabled Anthropic mode, scenario must be omitted: explicit
"success", null and unknown scenarios all return 422 without SDK construction.
All eight scenarios are supported:

- success: HTTP 200, exactly 1 attempt.
- rate_limit_then_success: HTTP 429 with Retry-After 1 second, then success;
  HTTP 200, exactly 2 attempts.
- server_error_then_success: HTTP 503, 503, success; HTTP 200, exactly 3 attempts.
- always_rate_limited: repeated HTTP 429; HTTP 429, normally 3 attempts.
- timeout: typed simulated transport timeouts; HTTP 504, normally 3 attempts.
- malformed_json: malformed provider JSON; HTTP 502, exactly 1 attempt, no retry.
- schema_violation: invalid schema; HTTP 502, exactly 1 attempt, no retry.
- auth_error: upstream HTTP 401; HTTP 502, exactly 1 attempt, no retry.

Deadline exhaustion can stop a transient sequence earlier. Attempt counts always
reflect actual calls. Detailed timing and curl examples are in
[Failure scenarios](FAILURE_SCENARIOS.md). The [interactive browser dashboard](DASHBOARD.md) runs these simulations with
CSRF protection and an explicit server-owned Fake workflow.

## Responses

Successful example (UUID and latency vary):

```json
{
  "request_id": "f2628048-a6cb-47c3-9a52-0dbf36ab0796",
  "result": {
    "category": "billing",
    "priority": "high",
    "summary": "Synthetic billing request requires review.",
    "requires_human_review": true
  },
  "meta": {
    "provider": "fake",
    "model": "fake-v1",
    "attempt_count": 1,
    "latency_ms": 0,
    "input_tokens": null,
    "output_tokens": null
  }
}
```

The server generates a fresh UUID independently of client request IDs. Latency
uses actual elapsed monotonic time rounded to milliseconds; fast calls may be 0.
Fake token counts are null. Inputs/results are never persisted; the application
UUID correlates with one metadata row and its terminal structured event.

The result has exactly category, priority, summary and requires_human_review.
Category is billing/technical/account/other; priority is low/medium/high. Summary
is a nonblank string of at most 240 characters. requires_human_review must be an
actual boolean; strings such as "true", missing/extra keys and invalid types fail.
The validated result and its values are immutable.

Invalid request, HTTP 422:

```json
{"request_id":"server-generated-uuid","error":{"code":"invalid_input","message":"Invalid classification request.","retryable":false},"meta":{"provider":"fake","attempt_count":0}}
```

Invalid fake output, HTTP 502:

```json
{"request_id":"server-generated-uuid","error":{"code":"invalid_provider_output","message":"The provider returned an invalid classification.","retryable":false},"meta":{"provider":"fake","attempt_count":1}}
```

Missing/incorrect Basic Auth returns 401 unauthorized and a WWW-Authenticate
challenge. Blank/missing server credentials always fail closed. A trusted server
configuration selecting an unknown or incompletely enabled provider returns 503
provider_disabled with provider disabled and attempt_count 0, without SDK requests. Unexpected programming bugs return a generic
500 internal_error, with attempt_count null rather than an invented count.
All error messages exclude input. Error mappings are:

- 422 invalid_input, 401 unauthorized and 415 unsupported_media_type: non-retryable.
- 503 provider_disabled: non-retryable configuration failure, zero attempts.
- 502 provider_auth_error: non-retryable timely upstream 401/403, normally one attempt.
- 502 invalid_provider_output: non-retryable parse/schema failure, one attempt.
- 429 rate_limited: exhausted or budget-limited upstream 429, retryable true.
- 503 provider_unavailable: exhausted transient HTTP/connection failures,
  retryable true. Permanent upstream 400/404 also map here but retryable is false.
- 504 provider_timeout: transport or overall timeout, retryable true. A typed HTTP
  failure arriving at/after its attempt deadline is classified as a timeout
  instead of its original HTTP status; any valid Retry-After minimum is retained.
- 500 internal_error: non-retryable unexpected bug, attempt count null.

`error.retryable` advises whether a separate future client request might be useful;
it does not mean the server will make another attempt or promise success. Invalid
provider output, authentication and configuration failures never retry. No fourth
provider call occurs. Fake token counts remain null. Retry-After metadata is used
internally and is not echoed as a raw provider header or response payload.

## Deterministic examples and limits

"I was charged twice for my subscription." matches billing (high, review true).
"The application crashes with an error." matches technical (medium, review false).
"I cannot sign in to my account." matches account (medium, review true).
"Please explain the available options." matches other (low, review false).
When several categories match, precedence is billing, technical, account, other.
Summaries are fixed synthetic strings, not copies of user text or model output.
This fixture offers predictable behavior and does not measure classification quality.

Run bin/ci or bundle exec rspec after preparing the dedicated test database.
Tests deny unmocked HTTP and cover schema enforcement, privacy, metadata-only database writes,
authentication, bounded parsing, Unicode lengths and exact invocation counts.

## Optional Anthropic success metadata

The same result/envelope applies in enabled real mode, with provider anthropic,
model claude-haiku-4-5-20251001 and actual nonnegative SDK input/output tokens
(or null if absent). Usage describes only the final successful attempt, not total
billed usage across retries. Latency and attempt counts still come from Runner.
Provider request IDs stay internal; the public request_id is always a fresh
application UUID. Real summaries may reflect submitted text, so use synthetic
input only. No raw prompt or completion is persisted. Final-success usage is
recorded as nullable integer metadata. Truncation, refusal,
invalid content and schema violations produce non-retryable HTTP 502. See
[setup and transport limitations](ANTHROPIC_SETUP.md); no live calls run in CI.

## Metadata recording

Authenticated accepted executions create one llm_runs row, including one row for
a run that retries. Controlled failures retain actual counts and Runner latency;
unexpected errors use null for unknown counts. The response request_id is the
same UUID stored in metadata and the terminal event. No input/result/body content
is recorded. Invalid/malformed/unauthenticated requests and disabled provider
configuration create no row or terminal event. Initial recording failure prevents
provider invocation and returns safe 500. Terminal recording/event failures never
repeat a provider call; rows/events may be incomplete after a crash or DB failure.
See [recording and retention contract](DASHBOARD.md). No public history API exists.
