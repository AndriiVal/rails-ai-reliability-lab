# Verification

Verified with Ruby 4.0.6, Bundler 4.0.16, Rails 8.1.4 and PostgreSQL 17.11.
Full dependency versions and checksums are recorded in Gemfile.lock.

## Historical Foundation baseline

The Foundation baseline passed its local verification on 2026-10-19:

- RSpec: **28 examples, 0 failures**.
- RuboCop: **30 files, no offenses**.
- Brakeman: **0 errors, 0 security warnings**.
- Dependency checks, dedicated development/test database preparation, Rails boot,
  public health/authenticated page smoke checks, Zeitwerk and asset compilation.
- All seven steps of the shared `bin/ci` command.

These counts describe the Foundation baseline, not the current classification API.

## Historical classification API verification (PR #2)

The [successful feature CI run](https://github.com/AndriiVal/rails-ai-reliability-lab/actions/runs/39248235555)
verified commit `0b8eaded7692aca4f6afec9a46bb225cbf0f124a`:

- RSpec: **126 examples, 0 failures**, including all Foundation coverage.
- RuboCop: **39 files, no offenses**.
- Brakeman: **0 errors, 0 security warnings**.
- The complete `bin/ci` gate: dependencies, test database preparation, Zeitwerk,
  Tailwind/assets, RSpec, RuboCop and Brakeman.

The same gate passed locally. Localhost HTTP smoke checks verified 200 success,
401 authentication, 422 invalid input, 502 invalid fake output and 503 disabled
provider responses. The static `/lab` page and public `/up` endpoint still pass.

That baseline used only a deterministic Fake Provider, with no real provider
SDK, outbound request, retry engine, persistence or telemetry.
See [API usage](API.md) for the implemented contract and limitations.

## Current reliability engine verification

The full local `bin/ci` gate passed with Ruby 4.0.6 and Rails 8.1.4:

- RSpec: **215 examples, 0 failures**, retaining Foundation and API regressions.
- RuboCop: **49 files, no offenses**.
- Brakeman: **0 errors, 0 security warnings**.
- Dependencies, dedicated PostgreSQL test database, Zeitwerk and Tailwind/assets pass.
- Localhost smoke requests for all eight scenarios verified statuses and actual
  counts: success 200/1, rate_limit_then_success 200/2,
  server_error_then_success 200/3, always_rate_limited 429/3, timeout 504/3,
  malformed_json 502/1, schema_violation 502/1 and auth_error 502/1.

Timing tests inject virtual clocks, sleeper and jitter without real retry waits.
They cover budget exhaustion, late output, Retry-After dates and equal-budget
cutoffs, early wakeups, configuration validation, concurrency and terminal output
validation. Real smoke calls use the production sleeper. These are fake provider
simulations, not verified real HTTP transport timeouts. No provider SDK, database
persistence or telemetry is added. See FAILURE_SCENARIOS.md for exact limits.

## Diagnostic and scanning limits

Unexpected controller errors receive a generic HTTP 500. The broad StandardError
handler logs only the exception class and opaque request UUID; it intentionally
omits exception messages, backtraces, causes and payloads to protect sensitive
input. That information alone cannot identify the failing line or reconstruct
the cause. Handled exceptions may also bypass normal unhandled-exception reporting.
Investigation requires reproducing the issue with synthetic data in a controlled
local environment. This is a minimal privacy boundary, not production observability.

Secret checks used credential-pattern and file-policy scans plus manual review.
No secret patterns were found; these checks do not prove every possible secret
has been detected. A clean Brakeman result is not a complete security assessment.
