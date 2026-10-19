module LlmConfiguration
  ANTHROPIC_MODELS = %w[claude-haiku-4-5-20251001].freeze

  def self.anthropic_enabled?(configuration)
    configuration[:provider] == "anthropic" && configuration[:enable_real_llm] == true &&
      configuration[:anthropic_api_key].is_a?(String) && configuration[:anthropic_api_key].present? &&
      ANTHROPIC_MODELS.include?(configuration[:anthropic_model])
  end

  def self.from_env(env = ENV)
    {
      provider: env.fetch("LLM_PROVIDER", "fake").presence || "fake",
      enable_real_llm: env.fetch("ENABLE_REAL_LLM", "").to_s.strip.downcase == "true",
      anthropic_api_key: env["ANTHROPIC_API_KEY"]&.dup&.freeze,
      anthropic_model: env["ANTHROPIC_MODEL"]&.dup&.freeze
    }.freeze
  end
end
