class RunEventSubscriber
  FIELDS = %i[request_id provider outcome attempt_count latency_ms error_code].freeze

  # ActiveSupport::EventReporter in Rails 8.1.4 calls emit(event) positionally.
  def emit(event)
    return unless event[:name] == "llm.classification.finished"

    Rails.logger.info(JSON.generate(event[:payload].slice(*FIELDS).merge(event: event[:name])))
  rescue StandardError
    # Logging must never affect classification or report exception payloads.
    nil
  end
end
