class TicketClassifier
  class Error < StandardError
    attr_reader :code, :attempt_count, :retryable, :latency_ms

    def initialize(code, attempt_count: 0, retryable: false, latency_ms: nil)
      @latency_ms = latency_ms
      @code = code
      @attempt_count = attempt_count
      @retryable = retryable
      super(code.to_s)
    end
  end

  attr_reader :provider_request_id

  def initialize(configuration: Rails.application.config.x.llm, provider: nil, runner: Reliability::Runner.new)
    @configuration = configuration
    @provider = provider
    @runner = runner
  end

  def call(ticket_text:, scenario: :omitted)
    unless ticket_text.is_a?(String) && ticket_text.encoding == Encoding::UTF_8 && ticket_text.valid_encoding?
      raise Error.new(:invalid_input)
    end
    normalized = ticket_text.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "")
    unless normalized.present? && (10..3000).cover?(normalized.length)
      raise Error.new(:invalid_input)
    end
    mode = @configuration.fetch(:provider)
    if mode == "fake"
      scenario = "success" if scenario == :omitted
      raise Error.new(:invalid_input) unless scenario.is_a?(String) && Providers::Fake::SCENARIOS.include?(scenario)
      model = Providers::Fake::MODEL
    elsif mode == "anthropic"
      raise Error.new(:provider_disabled) unless LlmConfiguration.anthropic_enabled?(@configuration)
      raise Error.new(:invalid_input) unless scenario == :omitted
      scenario = nil
      model = @configuration.fetch(:anthropic_model)
    else
      raise Error.new(:provider_disabled)
    end

    yield({ provider: mode, model_name: model, scenario: scenario }) if block_given?
    provider = @provider || (mode == "fake" ? Providers::Fake.new : Providers::Anthropic.new(configuration: @configuration))
    outcome = @runner.call(provider: provider, ticket_text: normalized, scenario: scenario)
    response = outcome.fetch(:response)
    @provider_request_id = response.provider_request_id
    {
      result: outcome.fetch(:result),
      meta: {
        provider: mode, model: response.model, attempt_count: outcome.fetch(:attempt_count),
        latency_ms: outcome.fetch(:latency_ms),
        input_tokens: response.input_tokens, output_tokens: response.output_tokens
      }
    }
  rescue Reliability::Runner::Failure => failure
    raise Error.new(failure.code, attempt_count: failure.attempt_count, retryable: failure.retryable, latency_ms: failure.latency_ms)
  end
end
