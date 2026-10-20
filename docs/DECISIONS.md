# Decisions

- Pin Ruby 4.0.6 locally; require Rails 8.1.4 within the 8.1 series and commit
  the lockfile. Never modify global Ruby configuration or upgrade silently.
- Use a Rails monolith with host-run Rails, local PostgreSQL-only Compose and
  standard MVC. Keep Fake as default; defer background jobs.
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
  invented usage. Safe provider request IDs stay internal; only allowlisted metadata is persisted,
  never raw content or billing totals.
- Distinguish scenario omission from explicit null/success in real mode.
- Catch API action errors before Rails rescue_from can log SDK error messages.
  Keep class/UUID-only diagnostics; no new observability system.
- Exercise the installed SDK using WebMock, no live calls or API secrets in CI.
  Manual smoke requires separate approval and uses a one-attempt Runner.

## Interactive simulation and safe metadata

- Keep the dashboard Fake-only through explicit configuration/provider injection;
  do not mutate global settings or forward browser provider controls.
- Share ClassificationWorkflow between UI/API. Use a metadata-only pre-execution
  block after validation/guards so invalid or disabled requests do not create runs.
- Create one started row per accepted invocation, not per retry. Record controlled
  failure counts/latency faithfully; unknown exceptions use null metrics.
- Use a conditional status=started update as the terminal transition gate. Validate
  explicit metadata first; avoid database transactions over calls or retry sleeps.
- Fail closed if initial recording fails. Preserve execution results if terminal
  storage/events fail, without repeating potentially billable calls. No outbox.
- Emit six allowlisted fields through Rails.event. The released Rails 8.1.4 calls
  emit(event) positionally. Keep one boot subscriber and no third-party exporter.
- Use standard forms, native labels/focus states and escaped HTML. No Stimulus
  controller is needed for this workflow. Keep full CSRF plus Basic Auth.
- Show ten indexed, authenticated Fake-only history rows, never full UUIDs or
  content. Recommend manual 30-day metadata retention; no scheduled cleanup.

## ADR summary — rationale and rejected alternatives

### Rails monolith and synchronous execution

**Decision:** Keep HTTP, orchestration, validation and local metadata in one Rails
application; execute classifications synchronously. **Rationale:** A reviewer can
trace one request and reproduce failures without additional services. **Tradeoff:**
Retries occupy Puma workers; an overall cooperative budget is not traffic control.
**Rejected for this scope:** Separate API services and job workers add deployment,
queue state and recovery contracts that this localhost demonstration does not need.
A public service would need a separate capacity and asynchronous-work design.

### One retry owner and no circuit breaker

**Decision:** Reliability::Runner exclusively owns retries; disable SDK retries and
redirect resends. **Rationale:** Attempt counts and deadlines remain inspectable
across adapters. **Tradeoff:** Adapter integration must be tested against the locked
SDK. **Rejected:** Nested SDK retries obscure send counts; a process-local circuit
breaker adds state that does not establish a meaningful multi-process outage policy.
No shared circuit breaker or job recovery system is claimed.

### Deterministic Fake and explicit real-provider opt-in

**Decision:** Fake is default and mandatory for browser execution. Real API use
requires all server-owned guards. **Rationale:** CI and interviews need reproducible
failure sequences without billing or credentials. **Tradeoff:** Fake fixtures prove
control flow, not model quality or network behavior. **Rejected:** Live-provider CI
would be nondeterministic, credential-dependent and potentially billable; automatic
fallback could hide configuration failures and spend money unexpectedly.

### Independent validation and final-success-only usage

**Decision:** Validate original JSON even after structured-output requests; report
only nonnegative usage from the final successful SDK response. **Rationale:** Schema
contracts must reject coercion, extra keys and overlong summaries independently;
unknown usage is null. **Tradeoff:** Structurally valid output can remain inaccurate,
and returned token counts understate total billed work after retries. **Rejected:**
Trusting provider grammar or inventing aggregate usage would overstate the evidence.
This project is not a billing ledger or accuracy benchmark.

### Content-free metadata and best-effort terminal events

**Decision:** Store bounded scalar metadata, conditionally transition started to one
terminal state, then attempt a six-field event. **Rationale:** Demonstrate correlation
and failure handling without retaining prompt/completion content. **Tradeoff:**
Reduced diagnostic detail; crashes can leave started rows or omit events. **Rejected:**
Raw JSON payload storage increases privacy risk; an outbox/recovery worker adds
operational scope. No transactional event delivery or automated retention is promised.

### Basic Auth for a local demonstration

**Decision:** Use Rails Basic Auth with fail-closed environment credentials, browser
CSRF and escaped output; leave only boot health public. **Rationale:** A compact
single-owner access gate is sufficient for a loopback demo. **Tradeoff:** No user
identities, quotas, audit-grade authorization or traffic throttling. **Rejected:**
Public commercial access under this gate; it would require TLS, stronger identity,
authorization and abuse/budget controls as a separate project.

### WebMock and virtual time

**Decision:** Exercise the installed SDK with WebMock and inject monotonic/wall clocks,
sleeper and jitter into reliability tests. **Rationale:** Exact request counts and
budget boundaries can be asserted quickly without live calls. **Tradeoff:** Mocks
cannot verify account access, actual transport latency or billing. **Rejected:**
Real sleep-based edge tests are slower and scheduling-sensitive; live network tests
are unsuitable for ordinary CI. Localhost Fake smoke checks separately exercise
real Rails HTTP boundaries and real retry waits.
