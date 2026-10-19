# Foundation security

Local demonstration only; no production deployment is approved. Basic Auth needs
TLS for use beyond localhost. Do not enter client data or real provider keys.
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

Only a deterministic Fake Provider exists; no network LLM clients are installed. Configuration defaults to fake/disabled and never needs an
API key. WebMock prevents unmocked HTTP in tests. Future real requests need a
separate approved implementation and explicit owner opt-in.

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
non-retryable and maps to 502. No database writes, telemetry, SDK calls, sleeps,
retries, instruction execution or HTML rendering of input/results are performed.
