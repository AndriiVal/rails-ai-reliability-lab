module LlmConfiguration
  def self.from_env(env = ENV)
    {
      provider: env.fetch("LLM_PROVIDER", "fake").presence || "fake",
      enable_real_llm: env.fetch("ENABLE_REAL_LLM", "").strip.downcase == "true"
    }.freeze
  end
end
