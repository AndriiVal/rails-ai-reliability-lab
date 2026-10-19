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

## Current classification API verification (PR #2)

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

The API uses only a deterministic Fake Provider. No real provider SDK, outbound
provider request, retry engine, classification persistence or telemetry exists.
See [API usage](API.md) for the implemented contract and limitations.

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
