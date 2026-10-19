module Providers
  class Fake
    class UnsupportedScenario < StandardError; end

    MODEL = "fake-v1".freeze
    SCENARIOS = %w[success rate_limit_then_success server_error_then_success always_rate_limited timeout malformed_json schema_violation auth_error].freeze
    RESULTS = {
      "billing" => [ "high", "Synthetic billing request requires review.", true ],
      "technical" => [ "medium", "Synthetic technical issue needs investigation.", false ],
      "account" => [ "medium", "Synthetic account access request needs assistance.", true ],
      "other" => [ "low", "Synthetic general support request.", false ]
    }.freeze

    def classify(ticket_text:, timeout_seconds:, scenario: "success", attempt: 1)
      raise UnsupportedScenario, "Unsupported fake scenario" unless SCENARIOS.include?(scenario)
      unless attempt.is_a?(Integer) && (1..3).cover?(attempt) && timeout_seconds.is_a?(Numeric) && timeout_seconds.real? && timeout_seconds.finite? && timeout_seconds.positive?
        raise ArgumentError, "Invalid fake attempt budget"
      end
      case scenario
      when "rate_limit_then_success"
        raise Error.new(status: 429, retry_after: "1") if attempt == 1
      when "server_error_then_success"
        raise Error.new(status: 503) if attempt < 3
      when "always_rate_limited"
        raise Error.new(status: 429, retry_after: "1")
      when "timeout"
        raise TransportTimeout
      when "auth_error"
        raise Error.new(status: 401)
      end
      return Response.new(body: "{invalid", model: MODEL) if scenario == "malformed_json"
      return Response.new(body: JSON.generate(category: "unsupported"), model: MODEL) if scenario == "schema_violation"

      category = case ticket_text.downcase
      when /charg|bill|refund|subscription/ then "billing"
      when /error|crash|broken|bug/ then "technical"
      when /sign in|login|password|account/ then "account"
      else "other"
      end
      priority, summary, review = RESULTS.fetch(category)
      Response.new(body: JSON.generate(category: category, priority: priority, summary: summary, requires_human_review: review), model: MODEL)
    end
  end
end
