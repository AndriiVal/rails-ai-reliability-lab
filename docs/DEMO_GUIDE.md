# Reviewer walkthrough — 3–5 minutes

Use invented tickets only. This demonstration measures synthetic reliability
behavior, not AI accuracy. No Anthropic account or API key is required.

## Start (before the walkthrough)

Follow [README quick start](../README.md#quick-start--ubuntu), including the reviewed
`.env` export, dedicated PostgreSQL startup and development/test `db:prepare`.
Run `bin/dev`; open <http://127.0.0.1:3000/up> (public boot health only), then
<http://127.0.0.1:3000/lab>. Authenticate with your privately configured credentials.
Never put credentials in a URL or recording. Keep the lab bound to loopback.

## Demonstrate

1. **0:00–0:30:** Read the simulation disclaimer. Keep the default invented ticket.
   Select **Immediate success** (`success`); submit. Show HTTP 200 / 1 actual attempt.
2. **0:30–1:00:** Select **Rate limit, then recover** (`rate_limit_then_success`).
   Show 200 / 2 attempts after at least a one-second retry wait. The displayed
   elapsed time is observed, not a fixed scenario timing or SLA.
3. **1:00–1:30:** Select **Server errors, then recover** (`server_error_then_success`).
   Show 200 / 3 attempts. Explain two typed simulated 503 failures and Runner-owned
   backoff; the Fake Provider itself never sleeps.
4. **1:30–2:15:** Run `auth_error`: terminal 502 / 1 attempt. Then run
   `malformed_json` and `schema_violation`: both 502 / 1 attempt. Valid JSON alone
   is insufficient, and permanent/validation failures are not retried.
5. **2:15–2:45:** Scroll to **Recent simulated runs**. Show scenario/status/count/
   latency/error/timestamp only, with no ticket or classification content. At most
   ten Fake rows are displayed; mobile history scrolls horizontally inside its container.
6. **2:45–3:30:** Open [the simulated audit](AUDIT_REPORT.md). Read its first-line
   disclaimer and one finding's real test evidence. Open [architecture](ARCHITECTURE.md)
   to point out the shared workflow, single retry owner and recording boundary.
7. **3:30–4:00:** Explain [Anthropic opt-in](ANTHROPIC_SETUP.md), without changing
   configuration or running its manual command. The browser cannot call Anthropic;
   API real mode separately requires flags, key and an allowlisted model. SDK
   retries are disabled. No live call was performed for this release audit.

For the complete eight-scenario CLI loop, use [failure scenarios](FAILURE_SCENARIOS.md).
Default counts can be lower when deadlines expire. `timeout` simulates typed
transport failure; it does not block for eight seconds on each attempt.

## Optional 45-second recording storyboard

Video is deferred; no verified recording is included. Existing Chromium/ffmpeg
executables alone do not establish a working, privacy-reviewed screen-capture pipeline.
Use this storyboard if capture is later arranged:

- 0–8 seconds: dashboard heading and synthetic-only disclaimer.
- 8–20 seconds: select `rate_limit_then_success`, run, show actual attempts = 2.
- 20–32 seconds: run `schema_violation`, show terminal validation failure / 1 attempt.
- 32–40 seconds: show metadata-only recent history.
- 40–45 seconds: end on the project's reliability-demo purpose and audit link.

Capture only the app viewport after authentication. Review every frame for tokens,
password UI, real personal data and unrelated browser content before sharing.
No deployment, fictional screenshots or generated demo video is needed.
