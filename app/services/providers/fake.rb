module Providers
  class Fake
    class UnsupportedScenario < StandardError; end

    MODEL = "fake-v1".freeze
    SCENARIOS = %w[success malformed_json schema_violation].freeze
    RESULTS = {
      "billing" => [ "high", "Synthetic billing request requires review.", true ],
      "technical" => [ "medium", "Synthetic technical issue needs investigation.", false ],
      "account" => [ "medium", "Synthetic account access request needs assistance.", true ],
      "other" => [ "low", "Synthetic general support request.", false ]
    }.freeze

    def classify(ticket_text:, scenario: "success")
      raise UnsupportedScenario, "Unsupported fake scenario" unless SCENARIOS.include?(scenario)
      return "{invalid" if scenario == "malformed_json"
      return JSON.generate(category: "unsupported") if scenario == "schema_violation"

      category = case ticket_text.downcase
      when /charg|bill|refund|subscription/ then "billing"
      when /error|crash|broken|bug/ then "technical"
      when /sign in|login|password|account/ then "account"
      else "other"
      end
      priority, summary, review = RESULTS.fetch(category)
      JSON.generate(category: category, priority: priority, summary: summary, requires_human_review: review)
    end
  end
end
