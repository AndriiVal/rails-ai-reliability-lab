# Source-code portfolio release readiness

**Verification date:** 2026-10-20 (Europe/Kyiv).
**Verified application commit:** `171235e24e5a41a02e9da1702eff2b2db2753e74`.
PR #6 changes documentation only; its exact documentation commit and Actions run
are recorded in the Draft PR. This report is not a production-hosting assessment
or security certification. [Executed evidence](VERIFICATION.md#final-portfolio-audit--pr-6-2026-10-20).

## Scope and versions — PASS

Public repository ID 1425489686 and merged PR #5 were verified, origin/master
fetched, clean workspace preserved, and a dedicated documentation branch created.
No archive was edited. Controllers, domain workflow, reliability engine, both
providers, validation, metadata persistence, structured events and tests reviewed.
Ruby **4.0.6**, Bundler **4.0.16**, Rails **8.1.4**, PostgreSQL **17.11** and
Anthropic SDK **1.80.0** verified from commands/lockfile; other exact dependencies
are listed in [README](../README.md#stack) and [Gemfile.lock](../Gemfile.lock).

## Quality gates — PASS locally

`bin/ci`: all seven steps passed, **396 RSpec examples / 0 failures**, **65 Ruby
files / no offenses**, Brakeman **0 errors / 0 warnings**. Dependencies, test DB,
Zeitwerk and assets passed. `db:migrate:status` shows the sole metadata migration up.
A fresh tracked-source snapshot repeated the gate successfully using existing
dependencies and the dedicated DB. Full commands, seeds and environment failures
are recorded in [verification](VERIFICATION.md). [Hosted GitHub Actions](https://github.com/AndriiVal/rails-ai-reliability-lab/actions/runs/39438363465)
passed for documentation commit `9d07378c33e77dacd8da54384336e8d261255a26`.
[Draft PR #6](https://github.com/AndriiVal/rails-ai-reliability-lab/pull/6) tracks the
final evidence-only follow-up status; local CI is not substituted for hosted evidence.

## Reproducibility — PASS within stated limits

Reviewed shell-compatible local configuration was explicitly exported; the app
never assumes automatic `.env` loading. Compose config validated and the existing
dedicated PostgreSQL service started healthy on loopback **5433** without removing
volumes. Development/test database preparation, loopback `bin/dev`, health, private
dashboard/API, browser CSRF and actual Fake scenarios were exercised. README gives
Ruby/Bundler prerequisites, install commands and separate DB names.

**NOT VERIFIED:** A pristine Ubuntu installation, dependency downloads into an
empty bundle, initial image pull and initialization of an empty PostgreSQL volume.
The isolated source run reused installed gems and the existing test database;
it does not prove those fresh-machine steps. No user database was reset.

## Privacy and security — PASS for bounded local controls

Authentication fails closed; only boot health is public. Browser CSRF, stateless
API boundaries, Fake isolation, escaping, no client provider/model overrides,
metadata/event allowlists, sensitive sentinel handling and recording-failure
behavior are covered by passing specs. See [security](SECURITY.md),
[architecture](ARCHITECTURE.md) and [audit proof](AUDIT_REPORT.md).
History is authenticated, newest-ten Fake-only. No public metadata API or permissive
CORS configuration was found. Current inputs stay out of sessions/flash/cookies/URLs.

Manual history/credential-pattern scanning and screenshot inspection found no
matching secrets or client content within their stated scope. **NOT VERIFIED:**
Comprehensive secret detection and dependency advisory scanning (scanner unavailable).
Brakeman does not substitute for either. No current High/Critical issue was identified
by this bounded review, and no production code was changed.

## Simulation and UI — PASS with capture limits

All eight localhost response statuses/counts matched the documented defaults;
observed timings are in [verification](VERIFICATION.md). Browser recovery used a
real CSRF token and returned two attempts; missing CSRF returned 422. Tests cover
all eight browser scenarios. These are synthetic control-flow proofs, not model
accuracy or live-provider reliability measurements.

Desktop/mobile PNGs inspected and reused. Mobile capture is a cropped viewport;
full mobile page overflow/scroll interaction was not independently exercised in
this audit. **NOT VERIFIED:** New browser/device capture and full-page mobile
interaction. **NOT APPLICABLE:** Optional video deliverable; deferred with an
honest [45-second storyboard](DEMO_GUIDE.md), no fabricated recording.

## Documentation — PASS after final link/diff checks

README provides value, real visuals, setup, exact stack, expected scenarios, curl,
checks and limitations. Architecture distinguishes HTTP, domain, adapters, retry,
persistence and events. Five explicitly simulated findings link real files and
existing test names; ADR rationale and a 3–5 minute walkthrough are present.
[Specification](../SPEC.md) records completion only where supported by evidence.
Relative Markdown paths and code fences are checked; Mermaid source reviewed for
actual flow. **NOT VERIFIED:** GitHub's rendered Mermaid layout on every viewport.

## Open findings and production exclusions

- Dependency advisory scan unavailable; run an approved read-only scanner before
  making dependency-security claims. No unrelated upgrades were made.
- Basic Auth only; no public traffic throttling, application usage/billing quotas
  or multi-user authorization.
- Synchronous requests and cooperative timeouts; no hard interruption or exactly-once billing.
- No transactional event outbox, background recovery or automated metadata retention.
- No production observability infrastructure, live Anthropic smoke, production
  load testing or real accuracy benchmark.
- Full fresh-machine installation and full mobile interaction remain unverified.

## Go / no-go

**GO for public source-code portfolio review**, provided the Draft PR's final
GitHub Actions run passes and these verification limits remain visible. This is
an evidence-backed local engineering demonstration, not a hosted product.

**NO-GO for public hosted deployment.** Deployment, paid live tests, tags, GitHub
Releases and merging are excluded from this milestone and were not performed.
Owner review and manual merge remain required. The [simulated audit](AUDIT_REPORT.md)
is not a client assessment or production-security approval.
