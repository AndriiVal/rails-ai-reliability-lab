# Decisions

- Pin Ruby 4.0.6 locally; require Rails 8.1.4 within the 8.1 series and commit
  the lockfile. Never modify global Ruby configuration or upgrade silently.
- Use a Rails monolith with host-run Rails, local PostgreSQL-only Compose and
  standard MVC. Implement only the Fake Provider; defer jobs, retries and metadata models.
- Keep the lab local and authenticated; leave only the standard health route public.
- Use strict environment parsing, fake defaults and no real-provider SDK.
- Use RSpec, FactoryBot and WebMock. Block unmocked HTTP and fail empty runs.
- Use one bin/ci entry point for local and GitHub checks, without deployment.
- Pin the verified Docker Hub PostgreSQL 17 linux/amd64 manifest digest in Compose
  and CI. Update it deliberately after checking compatibility and security.
- Use a locked Brakeman scanner without the generated network-dependent
  ensure-latest flag, so offline checks remain reproducible.
- The project is MIT-licensed; dependencies retain their own licenses.
- Build CSS and launch Rails directly with bin/dev; no global process manager is required.

- Use ActionController::API for the stateless JSON endpoint, sharing only the
  Basic Auth concern with browser controllers. No session-based authentication,
  permissive CORS or global CSRF exemption is introduced.
- Parse at most 16 KiB directly and suppress Rails body-parameter parsing before
  instrumentation. This yields controlled 422 errors for malformed JSON without
  parser diagnostics or raw payloads entering logs. Unsupported media types use 415.
- Use typed expected failures and an immutable validated result. Unexpected bugs
  retain a generic 500 path and safe error-class/request-ID logging.
- Report exactly one attempt for invoked fake scenarios, zero before invocation,
  and null for an unexpected internal error whose attempt count is unknown.
  Token counts are null; latency uses measured monotonic elapsed time.
- Synthetic keyword precedence is billing, technical, account, other. Fixed
  summaries never reproduce ticket text. This is a deterministic fixture,
  not AI inference. Only success, malformed_json and schema_violation exist.
