# Application architecture

A conventional full Rails monolith runs on the Ubuntu host. PostgreSQL 17 runs
alone in project-scoped Docker Compose, bound to loopback port 5433. Development
and test databases have distinct names. No classification model or migration is
needed: classification never persists input, results, request IDs or metadata.

GET /lab remains a static server-rendered page with Tailwind, Hotwire and importmap.
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
Fake Provider, invokes it exactly once, validates output, and measures elapsed
time with the monotonic clock. Expected application errors use TicketClassifier::Error
with a controlled code and actual attempt count. ClassificationValidator::InvalidOutput
remains distinct at the provider-output boundary. Unexpected programming exceptions
propagate from the service; the API returns a controlled 500 and logs only an
error class and opaque request ID, never the exception message or raw input.

Providers::Fake is stateless. It performs deterministic keyword matching and
returns fixed synthetic summaries as JSON. ClassificationValidator strictly
checks exactly four fields, enums, summary length/type and the actual boolean,
then freezes the result and its values. A future runner can repeatedly invoke
the same provider method; no sequence playback, retry policy or runner exists.

LlmConfiguration provides fake/disabled defaults and strict boolean parsing.
All unimplemented providers fail closed even if the future real-provider flag
is enabled. No provider SDK, API key, outbound HTTP or telemetry is required.
