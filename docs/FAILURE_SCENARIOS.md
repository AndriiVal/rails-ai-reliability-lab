# Synthetic failure scenarios and reliability budgets

These are deterministic simulations, not evidence of real upstream faults or
real HTTP transport timeout enforcement. No provider SDK, external request,
API key or real provider is involved. The dashboard and API record metadata only
and emit allowlisted terminal events for accepted executions. Use only
synthetic tickets and dummy Basic Auth credentials on localhost; public hosting
is not approved. Start Rails and export reviewed environment variables per README.

```bash
for scenario in success rate_limit_then_success server_error_then_success \
  always_rate_limited timeout malformed_json schema_violation auth_error; do
  printf '\n%s\n' "$scenario"
  curl --silent --show-error \
    --user "$BASIC_AUTH_USERNAME:$BASIC_AUTH_PASSWORD" \
    --header 'Content-Type: application/json' \
    --data "{\"ticket_text\":\"Synthetic subscription billing request.\",\"scenario\":\"$scenario\"}" \
    http://127.0.0.1:3000/api/v1/classifications
 done
```

## Outcomes with default budgets

- success: valid output; 200, 1 attempt.
- rate_limit_then_success: typed 429 with 1-second Retry-After, valid output;
  200, 2 attempts, at least the required one-second wait.
- server_error_then_success: typed 503, 503, valid output; 200, 3 attempts.
- always_rate_limited: typed 429 with 1-second Retry-After on every attempt;
  429 rate_limited, 3 attempts unless deadline constraints terminate earlier.
- timeout: typed simulated TransportTimeout on each attempt; 504 provider_timeout,
  3 attempts unless deadline constraints terminate earlier. No timeout sleep
  occurs inside the provider; only retry backoff occurs in the runner.
- malformed_json: invalid JSON; 502 invalid_provider_output, 1 attempt, no retry.
- schema_violation: invalid classification schema; 502 invalid_provider_output,
  1 attempt, no retry.
- auth_error: typed upstream 401; 502 provider_auth_error, 1 attempt, no retry.

The same provider can be invoked repeatedly/concurrently because scenario
selection uses the explicit one-based attempt argument, never a shared counter.

## Policy

Reliability::RetryPolicy defaults: maximum 3 total calls, 8-second per-attempt
budget, 25-second overall deadline, base backoff 0.2 seconds, multiplier 2,
and 2-second non-header cap. Constructors validate positive finite timeout limits,
1–3 attempts and finite nonnegative delays. Reliability settings are server-owned,
not JSON parameters. The runner counts calls only when invoking the provider.

Retry HTTP 408/409/429/5xx and typed connection/transport-timeout failures, subject
to both limits. Never retry timely HTTP 400/401/403/404 responses, invalid input/configuration,
malformed/schema-invalid output or arbitrary StandardError. The HTTP controller
maps normalized outcomes; it never decides to retry. There is only one retry layer.

For zero-based retry index i, capped delay is min(0.2 * 2**i, 2.0). Equal jitter
selects [0.5 * capped_delay, capped_delay] from injected randomness. A valid
Retry-After bypasses that calculation, including the cap. Positive numeric
seconds (including decimal values) and valid HTTP dates have no one-day cutoff.
A valid minimum wait that cannot fit the remaining budget terminates immediately;
it never falls back to a shorter delay. Positive decimal strings over 128 bytes
are conservatively represented as an unfulfillable wait (an infinite comparison
bound), without numeric conversion. The runner rejects that bound before sleeping;
it is not an actual infinite sleep or an overflow. Even an oversized positive
encoding of a small number is treated conservatively this way. Malformed,
nonpositive, nonfinite numeric values and past dates use normal backoff. Invalid
non-decimal metadata over 128 bytes is rejected without attempting date parsing.

HTTP dates have whole-second precision. The policy subtracts its separate current
wall-clock Time without rounding down the resulting fractional delay. Monotonic
time measures all execution/wait budgets, so wall-clock adjustments do not alter
the active overall deadline. If the wait is >= remaining budget, terminate
immediately without sleeping or counting a proposed attempt; preserve the last
failure code (for example rate_limited), with retryable client advice. Equality
leaves no invocation time and is therefore terminal. At deadline expiration,
provider_timeout is returned without a new call. Early sleep wakeups wait the
remaining minimum; oversleeping cannot start another call after the deadline.

## Timeout contract and limits

Each provider invocation receives timeout_seconds=min(8, remaining_budget), or
the corresponding configured per-attempt limit. Both successful returns and
typed provider failures at/after the attempt deadline are treated as transport
timeouts. Timeout classification takes precedence over a late HTTP status,
including 401 or 429, while retaining any valid Retry-After minimum. It can
therefore retry as a timeout if both budgets allow, even when the original late
HTTP status would have been permanent. A timely failure retains its normal HTTP
classification. A return or validation completion
at/after the overall deadline is terminal. No Timeout.timeout, asynchronous
interruption or forced cancellation is used. A blocking provider or sleeper can
return late: these checks reject that result and prevent further calls but
cannot force Ruby to return precisely at the deadline. The optional Anthropic
adapter propagates budgets and disables SDK retries;
installed-SDK/WebMock tests cover those boundaries. Live transport behavior
remains unverified.

## Testing and response interpretation

Unit and request specs inject virtual monotonic time, wall time, sleeper and
jitter. Virtual waits advance the clock without Kernel.sleep, giving exact
attempt decisions and elapsed latency without slowing the suite. Real localhost
smoke requests use the production sleeper and therefore incur actual waits.
latency_ms measures provider, validation and wait time with monotonic time;
it is never a fixed scenario value. input_tokens/output_tokens remain null.

error.retryable is false for permanent/configuration/schema/client failures.
For exhausted transient or timeout failures it is true, meaning a separate
future client request may be appropriate. The current server request has
terminated; this advice neither restarts it nor promises future success.
See API.md for every public status code. No raw error metadata is returned.

## Browser simulations

Use authenticated `/lab`, enter a synthetic ticket, select one of the same eight
scenarios and submit the CSRF-protected form. The dashboard is always Fake-only
even under real-provider configuration. Results display actual attempts and
Runner latency, plus a plain-language scenario explanation; no per-attempt
trace is invented. Recent history contains only bounded fake metadata. See
[dashboard and telemetry](DASHBOARD.md) for the shared recording lifecycle.
