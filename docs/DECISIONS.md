# Decisions

- Pin Ruby 4.0.6 locally; require Rails 8.1.4 within the 8.1 series and commit
  the lockfile. Never modify global Ruby configuration or upgrade silently.
- Use a Rails monolith with host-run Rails, local PostgreSQL-only Compose and
  standard MVC. Defer jobs, providers, retry/error abstractions and metadata models.
- Keep the lab local and authenticated; leave only the standard health route public.
- Use strict environment parsing, fake defaults and no provider SDK in Foundation.
- Use RSpec, FactoryBot and WebMock. Block unmocked HTTP and fail empty runs.
- Use one bin/ci entry point for local and GitHub checks, without deployment.
- Pin the verified Docker Hub PostgreSQL 17 linux/amd64 manifest digest in Compose
  and CI. Update it deliberately after checking compatibility and security.
- Use a locked Brakeman scanner without the generated network-dependent
  ensure-latest flag, so offline checks remain reproducible.
- The project is MIT-licensed; dependencies retain their own licenses.
- Build CSS and launch Rails directly with bin/dev; no global process manager is required.
