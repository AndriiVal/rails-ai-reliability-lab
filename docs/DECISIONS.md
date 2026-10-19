# Decisions

- Pin Ruby 4.0.6 locally; require Rails 8.1.4 within the 8.1 series and commit
  the lockfile. Never modify global Ruby configuration or upgrade silently.
- Use a Rails monolith with host-run Rails, local PostgreSQL-only Compose and
  standard MVC. Keep Fake as default; defer jobs and metadata models.
- Keep the lab local and authenticated; leave only the standard health route public.
- Use strict environment parsing and fake defaults; guard the optional real SDK.
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
- Report actual provider invocations, zero before invocation,
  and null for an unexpected internal error whose attempt count is unknown.
  Fake token counts are null; latency uses measured monotonic elapsed time.
- Synthetic keyword precedence is billing, technical, account, other. Fixed
  summaries never reproduce ticket text. This is a deterministic fixture,
  not AI inference. All eight documented failure scenarios are deterministic.

- Reliability::Runner is the only retry owner. Classifier input validation happens
  before it starts; invalid outputs and unknown Ruby exceptions are never retried.
- Use constructor-injected limits, monotonic clock, sleeper and randomness. No
  environment flags control tests or retry settings. Total invocations are capped
  at three even with configured policies; fake state comes from a call's attempt.
- Pass timeout_seconds to every provider invocation. Check late returns and the
  overall deadline cooperatively; do not interrupt arbitrary synchronous Ruby.
- Use equal jitter in [50%, 100%] of capped exponential delay. Valid Retry-After
  bypasses jitter and the 2-second normal cap; wait >= remaining budget terminates
  immediately, preserving the last failure code and actual attempt count.
- Parse positive delta-seconds or HTTP dates with a separate injected wall clock.
  Valid long minimum waits never fall back to a shorter delay. Positive decimal
  strings over 128 bytes use an unfulfillable comparison bound without conversion
  or sleeping, conservatively including padded/small encodings. Malformed,
  nonfinite/nonpositive numeric values and past dates use normal backoff. HTTP-date
  precision is seconds, but subtract the unrounded current time without flooring.
- Apply the per-attempt deadline to typed provider failures as well as returns.
  A late HTTP error becomes a transport timeout but retains Retry-After minimums;
  overall expiration remains terminal. Timely permanent errors still
  do not retry.
- Client retry advice remains distinct from the server's exhausted retry budget.
  The reliability engine itself adds no telemetry, SDK or data model.

## Opt-in Anthropic adapter

- Lock the official anthropic gem at 1.80.0, verified from the released artifact
  under Ruby 4.0.6. Add only required transitive dependencies, no unrelated upgrades.
- Start with one active dated Haiku 4.5 model, no aliases/fallbacks. A nonblank key,
  allowlisted model, server provider selection and explicit true are all required.
- Preserve one Runner retry layer. Set client and request max_retries to zero,
  pass remaining timeout at both levels, and block second sends due to redirects.
- Pin the official Messages origin, replace ambient custom headers, disable SDK
  telemetry. Do not let SDK environment/profile settings select credentials/URLs.
- Request raw-schema GA output_config.format. Keep original JSON text in the
  shared Response and independently validate it. The API grammar omits maxLength;
  the application enforces 240 characters. Bound output to 512 tokens.
- Tokens describe the final successful response only; null is preferable to
  invented usage. Safe request IDs stay internal. No persistence or billing totals.
- Distinguish scenario omission from explicit null/success in real mode.
- Catch API action errors before Rails rescue_from can log SDK error messages.
  Keep class/UUID-only diagnostics; no new observability system.
- Exercise the installed SDK using WebMock, no live calls or API secrets in CI.
  Manual smoke requires separate approval and uses a one-attempt Runner.
