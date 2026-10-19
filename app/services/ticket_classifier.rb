class TicketClassifier
  class Error < StandardError
    attr_reader :code, :attempt_count, :retryable

    def initialize(code, attempt_count: 0, retryable: false)
      @code = code
      @attempt_count = attempt_count
      @retryable = retryable
      super(code.to_s)
    end
  end

  def initialize(configuration: Rails.application.config.x.llm, provider: Providers::Fake.new, runner: Reliability::Runner.new)
    @configuration = configuration
    @provider = provider
    @runner = runner
  end

  def call(ticket_text:, scenario: "success")
    unless ticket_text.is_a?(String) && ticket_text.encoding == Encoding::UTF_8 && ticket_text.valid_encoding?
      raise Error.new(:invalid_input)
    end
    normalized = ticket_text.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "")
    unless normalized.present? && (10..3000).cover?(normalized.length) && scenario.is_a?(String) && Providers::Fake::SCENARIOS.include?(scenario)
      raise Error.new(:invalid_input)
    end
    raise Error.new(:provider_disabled) unless @configuration.fetch(:provider) == "fake"

    outcome = @runner.call(provider: @provider, ticket_text: normalized, scenario: scenario)
    {
      result: outcome.fetch(:result),
      meta: {
        provider: "fake", model: Providers::Fake::MODEL, attempt_count: outcome.fetch(:attempt_count),
        latency_ms: outcome.fetch(:latency_ms),
        input_tokens: nil, output_tokens: nil
      }
    }
  rescue Reliability::Runner::Failure => failure
    raise Error.new(failure.code, attempt_count: failure.attempt_count, retryable: failure.retryable)
  end
end
