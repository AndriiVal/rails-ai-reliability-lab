class RunRecorder
  EVENT_NAME = "llm.classification.finished".freeze
  TERMINAL_FIELDS = %i[status attempt_count latency_ms input_tokens output_tokens error_code provider_request_id].freeze

  def initialize(request_id:)
    @request_id = request_id
  end

  def start!(provider:, model_name:, scenario:)
    @run = LlmRun.create!(request_id: @request_id, provider: provider, model_name: model_name,
      scenario: scenario, status: "started", attempt_count: 0)
  end

  def finish(**metadata)
    return unless @run

    # No transaction spans provider execution. Conditional update is the single
    # terminal transition gate, including concurrent or duplicate finish calls.
    attributes = metadata.slice(*TERMINAL_FIELDS).merge(completed_at: Time.current, updated_at: Time.current)
    candidate = LlmRun.find(@run.id)
    candidate.assign_attributes(attributes)
    raise ArgumentError, "Invalid terminal metadata" unless %w[succeeded failed].include?(candidate.status) && candidate.valid?
    changed = LlmRun.where(id: @run.id, status: "started").update_all(attributes)
    return unless changed == 1

    payload = { request_id: @request_id, provider: @run.provider, outcome: metadata.fetch(:status),
                attempt_count: metadata[:attempt_count], latency_ms: metadata[:latency_ms], error_code: metadata[:error_code] }.freeze
    publish(payload)
  rescue StandardError => error
    Rails.logger.error("Run recording failure #{error.class.name} request_id=#{@request_id}")
    nil
  end

  private

  def publish(payload)
    Rails.event.notify(EVENT_NAME, payload)
  rescue StandardError => error
    Rails.logger.error("Run event failure #{error.class.name} request_id=#{@request_id}")
  end
end
