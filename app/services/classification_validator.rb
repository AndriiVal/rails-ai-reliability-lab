class ClassificationValidator
  class InvalidOutput < StandardError; end

  KEYS = %w[category priority summary requires_human_review].freeze
  CATEGORIES = %w[billing technical account other].freeze
  PRIORITIES = %w[low medium high].freeze

  def self.call(body)
    result = JSON.parse(body)
    valid = result.is_a?(Hash) && result.keys.sort == KEYS.sort &&
      CATEGORIES.include?(result["category"]) && PRIORITIES.include?(result["priority"]) &&
      result["summary"].is_a?(String) && result["summary"].valid_encoding? &&
      result["summary"].present? && result["summary"].length <= 240 &&
      [ true, false ].include?(result["requires_human_review"])
    raise InvalidOutput, "Invalid classification output" unless valid

    result.each_value(&:freeze)
    result.freeze
  rescue JSON::ParserError, EncodingError, TypeError
    raise InvalidOutput, "Invalid classification output"
  end
end
