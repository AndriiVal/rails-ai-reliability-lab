# Synthetic ticket classification API

POST /api/v1/classifications is a localhost-only demonstration using deterministic
keyword matching. It performs no AI inference or external requests. Export your
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

Scenario defaults to success when absent; null and unknown values are invalid.
Supported scenarios:

- success: valid synthetic result, one invocation, HTTP 200.
- malformed_json: deliberately malformed provider JSON, HTTP 502.
- schema_violation: syntactically valid provider JSON with an invalid schema, HTTP 502.

There are no retries, fault sequences or interactive scenario controls yet.

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
Fake token counts are null. No input, result or request identifier is persisted.

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
configuration selecting an unimplemented provider returns 503 provider_disabled
with provider disabled and attempt_count 0; enabling the future real-provider flag
does not install or activate a client. Unexpected programming bugs return a generic
500 internal_error, with attempt_count null rather than an invented count.
Every currently supported error is non-retryable; error messages contain no input.

## Deterministic examples and limits

"I was charged twice for my subscription." matches billing (high, review true).
"The application crashes with an error." matches technical (medium, review false).
"I cannot sign in to my account." matches account (medium, review true).
"Please explain the available options." matches other (low, review false).
When several categories match, precedence is billing, technical, account, other.
Summaries are fixed synthetic strings, not copies of user text or model output.
This fixture offers predictable behavior and does not measure classification quality.

Run bin/ci or bundle exec rspec after preparing the dedicated test database.
Tests deny unmocked HTTP and cover schema enforcement, privacy, no database writes,
authentication, bounded parsing, Unicode lengths and exact invocation counts.
