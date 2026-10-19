# Foundation architecture

A conventional full Rails monolith runs on the Ubuntu host. PostgreSQL 17 runs
alone in project-scoped Docker Compose, bound to loopback port 5433. Development
and test databases have distinct names. No application models beyond
ApplicationRecord or database migrations are needed yet.

GET /lab uses LabController and a server-rendered view with Tailwind and
Hotwire/importmap assets. Rails Basic Auth compares both configured credentials
using ActiveSupport secure comparison and rejects absent/blank configuration.
GET /up uses the standard Rails health controller and checks app boot, not DB
availability. It returns no database diagnostics.

LlmConfiguration reads an injected environment mapping and provides immutable
fake defaults and strict boolean parsing. No provider, network client,
classification endpoint, retry engine or telemetry exists in Foundation.
Future service boundaries are deferred until used. Rails CSRF protection stays
on ApplicationController. No SDK or API key is required for startup.
