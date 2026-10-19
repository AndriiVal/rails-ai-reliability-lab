class TicketClassifier
  class Error < StandardError
    attr_reader :code, :attempt_count

    def initialize(code, attempt_count: 0)
      @code = code
      @attempt_count = attempt_count
      super(code.to_s)
    end
  end

  def initialize(configuration: Rails.application.config.x.llm, provider: Providers::Fake.new)
    @configuration = configuration
    @provider = provider
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

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    output = @provider.classify(ticket_text: normalized, scenario: scenario)
    result = ClassificationValidator.call(output)
    {
      result: result,
      meta: {
        provider: "fake", model: Providers::Fake::MODEL, attempt_count: 1,
        latency_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round,
        input_tokens: nil, output_tokens: nil
      }
    }
  rescue ClassificationValidator::InvalidOutput
    raise Error.new(:invalid_provider_output, attempt_count: 1)
  end
end
