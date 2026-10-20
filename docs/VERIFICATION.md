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

## Historical reliability engine verification (PR #3)

The full local `bin/ci` gate passed with Ruby 4.0.6 and Rails 8.1.4:

- RSpec: **238 examples, 0 failures**, retaining Foundation and API regressions.
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

The focused correctness follow-up passes 104 runner/policy examples. Regression
coverage includes late typed HTTP failures at/after per-attempt deadlines,
preserved Retry-After minimums during timeout normalization, long numeric and
future-date minimums, oversized decimals without conversion, exact remaining-budget
cutoffs and malformed-value fallback. Both reported defects were reproduced before
fixing the production code. All eight localhost scenario status/count checks pass.

## Historical Anthropic opt-in adapter verification (PR #4)

On Ruby 4.0.6 / Rails 8.1.4 / PostgreSQL 17.11:

- Official anthropic **1.80.0** installed into the local bundle; released gem API,
  retry gates, Net::HTTP retry disabling and deadline propagation inspected.
- Full RSpec: **336 examples, 0 failures** (98 more than the PR #3 baseline).
- Focused adapter specs: **53 examples, 0 failures**, using the actual installed
  SDK against WebMock, including transport deadline propagation and exact counts.
- `bin/ci`: all seven steps passed; **336 examples, 0 failures**.
- RuboCop: **54 files, no offenses**.
- Brakeman: **0 errors, 0 security warnings**.
- `bundle check`, Rails version, Zeitwerk, assets and `git diff --check` passed.
- All eight localhost Fake Provider scenario status/count checks passed unchanged:
  success 200/1, rate_limit_then_success 200/2, server_error_then_success 200/3,
  always_rate_limited 429/3, timeout 504/3, malformed_json 502/1,
  schema_violation 502/1 and auth_error 502/1.

New coverage verifies all opt-in guards, missing usage as null, original JSON
schema validation, final-response token metadata, request-ID filtering, scenario
omission vs explicit null/success, endpoint/header isolation, redirect blocking,
actual SDK HTTP/connection/timeout errors, one request per invocation and bounded
Runner retries. The third SDK invocation receives a reduced 6.4-second budget in
the virtual late-error test. Timeout options are also observed at the SDK transport
boundary. No arbitrary sleeps or real requests are used in SDK specs.

A sentinel test exposed Rails 8.1 rescue_from instrumentation logging unexpected
exception messages. Action-local rescue now prevents that leak; successful output,
upstream failures and unexpected SDK errors are checked for sensitive logging and
no database writes. This does not add production observability.

Default fake-only CI needs no key and denies unmocked HTTP. No live Anthropic call
was made. Account access, model behavior, actual billing and network latency are
unverified. See [Anthropic setup](ANTHROPIC_SETUP.md) for compatibility evidence,
limits and separately authorized manual instructions. GitHub run results are
recorded in the Draft PR description after completion.

## Historical dashboard and safe telemetry verification (PR #5)

Verified on 2026-10-20 with Ruby 4.0.6, Rails 8.1.4, PostgreSQL 17.11 and the
unchanged Anthropic 1.80.0 lockfile:

- Full RSpec: **396 examples, 0 failures** (60 new examples).
- `bin/ci`: all seven steps passed, including **396 examples, 0 failures**.
- RuboCop: **65 files, no offenses**; Brakeman: **0 errors, 0 security warnings**.
- Development/test db:prepare and new metadata migration passed, along with
  dependency checks, Zeitwerk, assets and git diff --check.
- Actual localhost form POSTs used server-generated CSRF tokens/cookies for all
  eight scenarios; all eight API scenarios also passed expected status/counts.
  A missing-token browser POST was rejected with 422. All calls used Fake.
- Desktop/mobile synthetic screenshots were reviewed; no browser driver or new
  frontend dependency was added to the test suite.
- Independent read-only review completed. Its browser UTF-16 maxlength finding
  was fixed by keeping the Unicode length limit authoritative on the server.

Tests verify Fake isolation with fully enabled real settings, request UUID/row/
event correlation, one metadata row per invocation across retries, controlled
failure counts/latency and unknown counts on unexpected exceptions. PostgreSQL
concurrent completion publishes one event. Initial recording failures stop before
provider invocation; terminal DB/event/subscriber failures do not repeat calls.
Model/schema/index constraints, immutable terminal states, exact event payloads,
no content fields, private bounded history, CSRF, missing/blank credentials,
HTML escaping and log/content sentinels are covered. Existing API privacy tests
now require authorized metadata-only writes rather than removing those checks.

No live Anthropic call was made. WebMock still denies unmocked HTTP. No unrelated
gem upgrades, external exporters, background recovery, deployment or Milestone 6
implementation is included. Crash gaps can leave started rows or omit terminal
events; delivery is best effort. See [DASHBOARD.md](DASHBOARD.md) for failure and
manual retention policy. Actual GitHub Actions results are recorded in the Draft
PR description after the run completes.

## Diagnostic and scanning limits

Unexpected action errors receive a generic HTTP 500. The action-level StandardError
handler logs only the exception class and opaque request UUID; it intentionally
omits exception messages, backtraces, causes and payloads to protect sensitive
input. That information alone cannot identify the failing line or reconstruct
the cause. Handled exceptions may also bypass normal unhandled-exception reporting.
Investigation requires reproducing the issue with synthetic data in a controlled
local environment. This is a minimal privacy boundary, not production observability.

Secret checks used credential-pattern and file-policy scans plus manual review.
No secret patterns were found; these checks do not prove every possible secret
has been detected. A clean Brakeman result is not a complete security assessment.

## Final portfolio audit — PR #6 (2026-10-20)

Source baseline: `171235e24e5a41a02e9da1702eff2b2db2753e74` (verified merged
PR #5). Repository ID **1425489686**, public `AndriiVal/rails-ai-reliability-lab`;
origin fetched before branch creation. The visible 13-commit history starts at the
public Foundation commit; no archive history or private remote was found.
PR #6 is documentation-only. Results below are newly executed, not reused baseline counts.

### Executed quality gates

- `ruby -v`: **4.0.6**; `bundle -v`: **4.0.16**;
  `bin/rails --version`: **8.1.4**; `bundle check`: satisfied.
- `bin/ci`: **PASS**, all seven steps. RSpec **396 examples, 0 failures**,
  seed **52886**; RuboCop **65 files inspected, no offenses**;
  Brakeman **8.1.0**, **0 errors / 0 security warnings**.
- Zeitwerk eager loading and asset precompilation passed inside that gate.
  Brakeman printed optional concurrent_ruby_ext LoadError diagnostics but completed
  successfully with no scanner errors; no dependency changes were needed.
- Dedicated development `db:prepare` passed; test `db:prepare` passed inside CI.
  `RAILS_ENV=test bin/rails db:migrate:status`: migration **20261020090000 up**.
  A read-only query confirmed the configured test database and PostgreSQL **17.11**.
- Initial attempts without a running project DB failed with connection errors
  (0 examples, 15 load errors). Starting the existing project Compose service and
  exporting reviewed configuration resolved the environment failure; tests were unchanged.
- Fresh `git archive origin/master` snapshot in an isolated temporary directory:
  **all seven bin/ci steps passed**, **396 examples / 0 failures**, seed **57664**.
  It reused the existing installed bundle and dedicated test DB, with privately
  exported configuration; no `.env` was copied. This is source-tree isolation,
  **not a fresh OS, empty volume or dependency-download verification**.

### Observed localhost HTTP evidence

Rails ran with `bin/dev -p 3106`, bound to 127.0.0.1, fake mode forced and real
provider disabled/key unset. These are actual response status/attempt_count values
from eight JSON POSTs, using invented subscription text and private Basic Auth.
Wall latency was measured by the smoke client, not copied from expected scenarios:

- `success`: **200 / 1**, wall **101 ms**, response Runner latency **1 ms**.
- `rate_limit_then_success`: **200 / 2**, wall **1038 ms**, Runner **1001 ms**.
- `server_error_then_success`: **200 / 3**, wall **502 ms**, Runner **462 ms**.
- `always_rate_limited`: **429 / 3**, wall **2039 ms**.
- `timeout`: **504 / 3**, wall **399 ms**.
- `malformed_json`: **502 / 1**, wall **28 ms**.
- `schema_violation`: **502 / 1**, wall **23 ms**.
- `auth_error`: **502 / 1**, wall **28 ms**.

Error API envelopes do not expose latency_ms; wall measurements above are client
observations, not invented Runner values. The 429 recovery minimum is one second;
persistent 429 requires two one-second waits. Remaining wall time includes HTTP,
Rails, database and scheduling overhead. Backoff jitter makes 503/timeout timings
vary. Fake timeout raises immediately; it does not simulate a real socket stall.

Public `/up` returned **200**; unauthenticated `/lab` returned **401**. A real cookie/
server-generated CSRF browser POST for rate-limit recovery returned **200 / 2**;
a missing-token POST returned **422**. Full request specs separately execute all
eight browser scenarios with real CSRF verification and virtual retry time.

### Scanning and review boundaries

- **Code scanning:** locked Brakeman executed as above; this is not an advisory audit.
- **Dependency advisories: NOT VERIFIED.** Neither bundle-audit executable nor
  bundler-audit gem was installed (`bundle exec bundler-audit --version` unavailable).
  No scanner gem, service or unrelated dependency upgrade was added.
- **Secrets:** read-only regex review of **13 visible commits / 186 unique blobs**
  found no matches for PEM private keys, Anthropic token patterns, GitHub token
  patterns or AWS access-key IDs. History path review found no `.env`, master key,
  archive/client/employer-named artifacts. This bounded heuristic is not exhaustive
  secret detection; no hosted secret-scanner status is claimed.
- `.env`, master key and credential file ignore rules were checked with
  `git check-ignore`; no such sensitive file is tracked. Active dependency declarations,
  lockfile, routes, controller guards, model/schema, subscriber and tests were reviewed.
  No debug/TODO/FIXME markers in app/lib/config indicated a critical omission.
  No employer/client material was identified; this is not a provenance/legal audit.
- **Visuals:** desktop **1440×1400**, mobile **390×1800** PNGs visually inspected.
  Text/layout are readable; no visible keys, passwords, tokens or real personal data.
  Mobile image ends partway through history and does not prove the full-page scroll
  behavior. Prior capture method used rendered HTML with tokens removed; images
  are reused, not newly captured. Video deferred to [storyboard](DEMO_GUIDE.md).
- **Manual architecture/privacy review:** documented in [simulated findings](AUDIT_REPORT.md)
  and [security](SECURITY.md). No High/Critical current code vulnerability was identified
  in this bounded review; that is not a blanket absence-of-vulnerabilities claim.

GitHub Actions for the documentation commit is reported separately after the Draft
PR is opened. No live Anthropic request, deployment, tag, release or merge occurred.

### Final documentation review

A separate read-only review context inspected the complete documentation diff and
new audit/demo/readiness reports against actual controllers, workflow, providers,
runner/policy, model/schema, subscriber and tests. It reported **no actionable
findings**, confirming the mandatory disclaimer, exact cited test names and scoped
readiness claims. It did not independently rerun tests, authenticate historical
execution logs, reinspect screenshots or check hosted CI. No external AI review
provider was invoked.

Relative Markdown targets/heading anchors and balanced fences were checked across
13 Markdown files; 92 references passed before final evidence links were added.
`git diff --check` passed; all changes are Markdown documentation.

Public HTTPS documentation references returned HTTP 200 (13 URLs). The configured
API origin is not a documentation page and returned 404 on an unauthenticated GET;
no Messages/inference endpoint was called by the link check. Relative/new-branch
file links were checked locally before publication. No paid request was made.
