Simulated engineering audit of the Rails AI Reliability Lab. Not a client assessment. All failures and results are synthetic.

# Reliability and privacy findings

Reviewed on **2026-10-20**, against production source based on
`171235e24e5a41a02e9da1702eff2b2db2753e74`. PR #6 changes documentation only.
The unsafe snippets below are deliberately illustrative pseudocode, **not recovered
production code or evidence that these vulnerabilities existed historically**.
Severity describes potential impact in a hypothetical hosted integration; this
application remains a localhost lab. These are simulated risk findings with
implemented controls, not five unresolved vulnerabilities or a security certification.

## Evidence and method

Read the controllers, configuration, workflow, providers, runner/policy, validator,
recorder, model/schema, subscriber and corresponding specs. Executed `bin/ci`:
**396 examples, 0 failures**, including every example named below; **65 Ruby files,
no offenses**; Brakeman **0 errors / 0 warnings**. WebMock intercepts SDK HTTP;
virtual time proves decision boundaries without real network timing. Localhost
Fake-only API checks exercise all eight default status/count pairs.
[Verification](VERIFICATION.md) separates those observed results from expected values.
No live Anthropic call, financial-loss measurement or accuracy evaluation occurred.

Reproduce focused proofs after the [local setup](../README.md#quick-start--ubuntu),
using `bundle exec rspec <test-file> -e '<exact example name>'`. Each finding gives
literal existing example names; omit `-e` to execute its complete test file.

## F-01 — Double retries / nested retry layers

**Severity:** High in a hypothetical paid deployment: multiplicative retries can
amplify upstream traffic and billable ambiguous requests beyond the application cap.
**Layer:** Provider adapter and retry orchestration.

**Simulated unsafe pattern:**

```ruby
# Illustrative only: both SDK and application retry independently.
client = SDK.new(max_retries: 2)
application_retry(max_attempts: 3) { client.classify(ticket) }
```

Three application invocations with up to three SDK sends each could permit nine
sends in this illustrative configuration. This is arithmetic, not an observed lab
incident or billing measurement. Attempt metadata would undercount actual sends.

**Reproduction / proof:** Run
`bundle exec rspec spec/services/providers/anthropic_spec.rb -e 'makes exactly two SDK requests for 429 then success, respecting Retry-After'`.
That exact example uses the installed SDK and WebMock, asserting two intercepted
sends and a 1,000 ms virtual wait. The same file's exact example
`uses the released SDK with zero retries, bounded timeout, official origin and telemetry disabled`
checks client/request options and the transport deadline. Fake reproduction:
`rate_limit_then_success` returns observed HTTP 200 / 2 attempts on localhost.

**Mitigation / exact production files:**
[anthropic.rb](../app/services/providers/anthropic.rb) sets client and request
`max_retries: 0`, disables telemetry and prevents a second send through redirects;
[runner.rb](../app/services/reliability/runner.rb) alone owns retries;
[retry_policy.rb](../app/services/reliability/retry_policy.rb) caps total attempts at three.
**Verified result:** Existing mocked SDK examples pass within the full suite;
Fake counts agree with localhost evidence. No nested application retry was found.
**Residual risk:** A timed-out request may still consume provider resources;
exactly-once billing is not guaranteed. **Proof limitation:** SDK mocks do not
prove account billing, real transport behavior or future SDK versions.

## F-02 — Ignoring HTTP 429 Retry-After

**Severity:** Medium: premature retries can violate an upstream minimum wait,
waste capacity and worsen throttling. **Layer:** RetryPolicy / Runner time budget.

**Simulated unsafe pattern:**

```ruby
# Illustrative only: ignores the provider's Retry-After minimum.
rescue RateLimited
  sleep(0.2)
  retry
```

**Reproduction / proof:** Run
`bundle exec rspec spec/services/reliability/runner_spec.rb -e 'honors Retry-After without jittering it or capping to backoff'`.
Also in that exact test file:
`honors HTTP-date using separate wall and monotonic time sources`,
`treats a valid HTTP-date two days ahead as an unfulfillable minimum wait`, and
`compares Retry-After against remaining rather than initial budget`.
In [retry_policy_spec.rb](../spec/services/reliability/retry_policy_spec.rb),
`keeps valid Retry-After above the normal backoff cap` and
`represents an oversized positive decimal without overflowing or using jitter`
exercise policy edge cases. `always_rate_limited` is the actual Fake reproduction:
observed HTTP 429 / 3 attempts on localhost, with two minimum one-second waits.

**Mitigation / exact production files:**
[retry_policy.rb](../app/services/reliability/retry_policy.rb) parses positive
numeric seconds and HTTP dates using an independent wall clock. Valid long
minimums bypass jitter/backoff caps. Invalid or past values fall back to bounded
backoff. Oversized positive decimals conservatively block retries without conversion.
[runner.rb](../app/services/reliability/runner.rb) terminates without sleeping if
the delay consumes or exceeds remaining monotonic budget; early wakeups wait again.
**Verified result:** Named tests pass; no early retry is permitted by the tested
budget/date cases. **Residual risk:** Incorrect provider headers or host wall-clock
skew can affect HTTP-date interpretation. **Proof limitation:** Fake 429 headers
and virtual time do not establish real-provider throttling behavior. Wall latency
in localhost evidence includes more than the configured minimum wait.

## F-03 — Missing overall deadline

**Severity:** Medium: independent attempt timeouts plus retry waits can occupy a
synchronous worker beyond the intended request budget. **Layer:** Retry/time management.

**Simulated unsafe pattern:**

```ruby
# Illustrative only: each attempt gets a fresh budget; no overall deadline.
3.times { provider.call(timeout: 8) rescue sleep(2) }
```

**Reproduction / proof:** Run
`bundle exec rspec spec/services/reliability/runner_spec.rb -e 'passes the decreasing remaining budget to a third attempt'`.
The same file contains exact examples
`rejects a successful provider return after the overall deadline` and
`bounds repeated late errors by three invocations and the remaining overall budget`.
[anthropic_spec.rb](../spec/services/providers/anthropic_spec.rb) contains
`passes the reduced remaining budget to the third SDK transport call` (8, 8,
then approximately 6.4 seconds in virtual time).
The `timeout` Fake scenario returns observed HTTP 504 / 3 attempts; it raises
immediately and is **not** proof of a real eight-second transport timeout.

**Mitigation / exact production files:**
[clock.rb](../app/services/reliability/clock.rb) supplies monotonic time;
[runner.rb](../app/services/reliability/runner.rb) establishes the 25-second overall
deadline and caps each invocation to min(8, remaining budget), rechecking late
results/errors and validation. [anthropic.rb](../app/services/providers/anthropic.rb)
propagates the remaining budget to SDK client/request transport options.
**Verified result:** Named deadline/reduced-budget tests pass. Late typed failures
follow the existing timeout-precedence policy; valid Retry-After remains respected.
**Residual risk:** Cooperative checks cannot interrupt arbitrary Ruby, DNS/TLS,
scheduling or a blocking provider precisely at the deadline. **Proof limitation:**
No real-provider latency, public load or hard wall-clock SLA was tested.

## F-04 — Unvalidated LLM JSON

**Severity:** Medium: parseable but invalid classifications can corrupt downstream
routing or review decisions. **Layer:** Provider-output/domain trust boundary.

**Simulated unsafe pattern:**

```ruby
# Illustrative only: parsing alone validates neither fields nor meaning.
classification = JSON.parse(response.body)
```

**Reproduction / proof:** Run
`bundle exec rspec spec/services/classification_validator_spec.rb`.
Exact examples include `rejects a missing category`, `rejects extra key`,
`rejects invalid category`, `rejects invalid priority`, `rejects string boolean`,
`rejects long summary`, and `accepts false and the Unicode summary length boundary`.
[runner_spec.rb](../spec/services/reliability/runner_spec.rb) also contains
`does not retry malformed or schema-invalid output` (parameterized over both
invalid outputs). Run both actual Fake scenarios `malformed_json` and
`schema_violation`: each observed HTTP 502 / 1 attempt on localhost.

**Mitigation / exact production files:**
[classification_validator.rb](../app/services/classification_validator.rb) requires
exactly four fields, strict enums, real boolean and nonblank string summary of at
most 240 characters, without coercion. [runner.rb](../app/services/reliability/runner.rb)
validates the original provider JSON and treats invalid output as terminal.
[anthropic.rb](../app/services/providers/anthropic.rb) requests a fixed schema but
does not rely on upstream enforcement; its grammar omits maxLength, so local
length validation remains necessary.
**Verified result:** All validator examples pass and both Fake failures stop after
one attempt. **Residual risk:** Structurally valid output can still be wrong or
semantically influenced by injection. **Proof limitation:** This is schema integrity,
not measured classification accuracy or guaranteed semantic prompt-injection immunity.

## F-05 — Sensitive ticket content in logs or telemetry

**Severity:** High in a hypothetical integration handling sensitive content:
logging prompts, completions, exception bodies or authorization can disclose
customer data or paid-provider credentials. **Layer:** HTTP instrumentation,
error handling, persistence and observability.

**Simulated unsafe pattern:**

```ruby
# Illustrative only; never log these values.
logger.error(error.message)
Rails.event.notify('classification', ticket: ticket, completion: response.body)
```

**Reproduction / proof:** Run
`bundle exec rspec spec/requests/anthropic_classifications_spec.rb -e 'does not log or persist ticket, key, prompt, completion, error bodies or credentials'`.
It uses synthetic sentinels and intercepted SDK success, upstream 401 and unexpected
exception paths, asserting safe logs/responses and six metadata-only SQL writes.
[lab_spec.rb](../spec/requests/lab_spec.rb) contains exact examples
`logs neither submitted fields nor unexpected exception messages` and
`escapes both editable ticket text and untrusted classification summaries`.
[classification_workflow_spec.rb](../spec/services/classification_workflow_spec.rb)
contains `marks unexpected exceptions failed with unknown counts and no sensitive diagnostics`.
No Fake scenario alone proves every log path; these focused tests supply that proof.

**Mitigation / exact production files:**
[classifications_controller.rb](../app/controllers/api/v1/classifications_controller.rb)
and [lab_controller.rb](../app/controllers/lab_controller.rb) catch action errors
before Rails 8.1 rescue_from instrumentation can log exception messages; unexpected
failures log class/opaque UUID only. This documents an existing privacy fix, not a
new PR #6 code patch. [filter_parameter_logging.rb](../config/initializers/filter_parameter_logging.rb)
filters sensitive parameters; bounded controller parsers suppress raw body logging.
[run_recorder.rb](../app/services/run_recorder.rb), [llm_run.rb](../app/models/llm_run.rb),
[schema.rb](../db/schema.rb) and [run_event_subscriber.rb](../lib/run_event_subscriber.rb)
restrict persistence/events/logging to explicit scalar metadata. The terminal event
has only request_id, provider, outcome, attempt_count, latency_ms and error_code.
**Verified result:** Sentinel, escaping and workflow tests pass; screenshots show
only invented content and metadata. **Residual risk:** Proxy/body capture, additional
subscribers, host instrumentation or future manual logging can bypass these controls;
class-only diagnostics reduce incident detail. **Proof limitation:** Sentinels cover
specified paths, not every possible secret encoding or external logging system.

## Residual risks and overall local-lab assessment

Controls are supported by executable synthetic tests and manual source review.
Basic Auth alone, synchronous workers, absent traffic/billing quotas and cooperative
timeouts are insufficient for an unauthenticated public service. Initial DB failure
prevents invocation; terminal DB/event failure never repeats a provider call, but
crash gaps can leave started rows or missing events. There is no transactional
outbox, background recovery or automated retention.

No installed dependency advisory scanner was available; that check was not performed.
Credential-pattern/history review is bounded, not comprehensive secret detection.
No live Anthropic smoke, production load test, accuracy benchmark or production
monitoring assessment was performed. See [release readiness](RELEASE_READINESS.md)
for explicit PASS / NOT VERIFIED / NOT APPLICABLE categories. The appropriate
conclusion is suitability for local demonstration and public source review within
these limits, never production-security certification.
