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

No LLM clients exist. Configuration defaults to fake/disabled and never needs an
API key. WebMock prevents unmocked HTTP in tests. Future real requests need a
separate approved implementation and explicit owner opt-in.

Compose exposes PostgreSQL only on 127.0.0.1:5433 with project-owned persistent
storage. Do not remove volumes, change Docker socket permissions or connect to
unrelated databases. CI has read-only repository permissions, dummy credentials,
no provider keys and no deployment step. A passing scanner is only one review aid.
