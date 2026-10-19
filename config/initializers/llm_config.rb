require Rails.root.join("lib/llm_configuration")

Rails.application.config.x.llm = LlmConfiguration.from_env
