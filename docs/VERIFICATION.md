# Foundation verification

Verified locally on 2026-10-19 with Ruby 4.0.6, Bundler 4.0.16,
Rails 8.1.4 and PostgreSQL 17.11. Full dependency versions and checksums
are recorded in Gemfile.lock.

Both the original Foundation source and this clean release candidate passed:

- Dependency resolution checks using the locked, locally installed bundle.
- Development and test database preparation against dedicated PostgreSQL databases.
- Rails boot and public health/authenticated page smoke checks for the candidate.
- Zeitwerk autoloading checks and Tailwind/asset compilation.
- The complete RSpec suite: **28 examples, 0 failures** for each source tree.
- RuboCop: **30 files, no offenses** for each source tree.
- Brakeman: **0 errors, 0 security warnings** for each source tree.
- All seven steps of the shared `bin/ci` command.

Application logic, dependencies, configuration and all RSpec tests are unchanged.
The dashboard status sentence was updated to describe the current release.
No real provider SDK, real API request or retry engine exists. The deterministic
classification API is documented in API.md. The 28-example results above record
the Foundation baseline; current API validation is recorded by the feature CI run.

The original implementation has a successful historical GitHub Actions run.
This candidate has been tested locally; a newly published repository requires
its own GitHub Actions run before claiming remote CI success. Secret scanning
used credential-pattern and file-policy checks plus manual review; those checks
do not prove that every possible secret has been detected.

Current classification feature validation: 126 examples, 0 failures. The full
bin/ci gate passes, including Zeitwerk, assets, 39 RuboCop files without offenses,
and Brakeman without warnings. Localhost HTTP smoke checks verified 200, 401,
422, 502 and 503. The static Foundation page and public health check still pass.
