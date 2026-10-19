module LabHelper
  SCENARIOS = {
    "success" => [ "Immediate success", "Returns a valid synthetic classification without a simulated failure." ],
    "rate_limit_then_success" => [ "Rate limit, then recover", "Simulates 429 with a one-second minimum wait before success." ],
    "server_error_then_success" => [ "Server errors, then recover", "Simulates two 503 responses before success, subject to the remaining budget." ],
    "always_rate_limited" => [ "Persistent rate limit", "Simulates repeated 429 responses until the attempt or deadline budget stops retries." ],
    "timeout" => [ "Transport timeouts", "Simulates transport timeout errors; no real network timeout occurs." ],
    "malformed_json" => [ "Malformed JSON", "Returns broken JSON. Output validation stops the run without retry." ],
    "schema_violation" => [ "Invalid classification schema", "Returns an invalid category. Strict validation stops the run without retry." ],
    "auth_error" => [ "Upstream authentication error", "Simulates HTTP 401. Credential failures are terminal without retry." ]
  }.freeze

  def run_explanation
    return "The request was rejected before classification. Check the ticket and scenario." if @error_code == :invalid_input
    return "An unexpected error occurred. The attempt count is unknown; no automatic application retry was added." if @error_code == :internal_error

    attempts = @outcome ? @outcome[:meta][:attempt_count] : @attempt_count
    text = SCENARIOS.fetch(@scenario, [ "", "" ]).last
    "#{text} Execution used #{attempts} provider invocation(s). Retries remain bounded to three attempts and 25 seconds overall; counts and elapsed time below come from this run."
  end
end
