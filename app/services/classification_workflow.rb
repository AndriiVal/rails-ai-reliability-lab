class ClassificationWorkflow
  def initialize(classifier: TicketClassifier.new, recorder_class: RunRecorder)
    @classifier, @recorder_class = classifier, recorder_class
  end

  def call(request_id:, ticket_text:, **options)
    recorder = @recorder_class.new(request_id: request_id)
    started = false
    outcome = @classifier.call(ticket_text: ticket_text, **options) do |metadata|
      recorder.start!(**metadata)
      started = true
    end
    recorder.finish(status: "succeeded", **outcome.fetch(:meta).slice(:attempt_count, :latency_ms, :input_tokens, :output_tokens),
      provider_request_id: @classifier.provider_request_id, error_code: nil)
    outcome
  rescue TicketClassifier::Error => error
    recorder.finish(status: "failed", attempt_count: error.attempt_count, latency_ms: error.latency_ms, error_code: error.code.to_s) if started
    raise
  rescue StandardError
    recorder.finish(status: "failed", attempt_count: nil, latency_ms: nil, error_code: "internal_error") if started
    raise
  end
end
