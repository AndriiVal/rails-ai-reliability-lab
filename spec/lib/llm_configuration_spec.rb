require "spec_helper"
require "active_support/core_ext/object/blank"
require_relative "../../lib/llm_configuration"

RSpec.describe LlmConfiguration do
  it "defaults to fake mode without credentials" do
    expect(described_class.from_env({})).to eq(provider: "fake", enable_real_llm: false, anthropic_api_key: nil, anthropic_model: nil)
  end

  [ nil, "", " ", "false", "FALSE", "0", "yes", "invalid" ].each do |value|
    it "keeps real usage disabled for #{value.inspect}" do
      env = value.nil? ? {} : { "ENABLE_REAL_LLM" => value }
      expect(described_class.from_env(env)[:enable_real_llm]).to be(false)
    end
  end

  it "recognizes explicit true without making provider requests" do
    expect(described_class.from_env("ENABLE_REAL_LLM" => "true")[:enable_real_llm]).to be(true)
  end

  it "treats blank provider selection as fake" do
    expect(described_class.from_env("LLM_PROVIDER" => " ")[:provider]).to eq("fake")
  end
end

RSpec.describe "Anthropic opt-in configuration" do
  let(:env) do
    { "LLM_PROVIDER" => "anthropic", "ENABLE_REAL_LLM" => "true",
      "ANTHROPIC_API_KEY" => "synthetic-key", "ANTHROPIC_MODEL" => LlmConfiguration::ANTHROPIC_MODELS.first }
  end

  it "requires all trusted server settings" do
    expect(LlmConfiguration.anthropic_enabled?(LlmConfiguration.from_env(env))).to be(true)
  end

  { "LLM_PROVIDER" => [ "fake", "unknown", "" ], "ENABLE_REAL_LLM" => [ nil, "false", "1", "yes" ],
    "ANTHROPIC_API_KEY" => [ nil, "", "  " ], "ANTHROPIC_MODEL" => [ nil, "", "other", "claude-haiku-4-5" ] }.each do |key, values|
    values.each do |value|
      it "disables real calls for #{key}=#{value.inspect}" do
        configuration = LlmConfiguration.from_env(env.merge(key => value))
        expect(LlmConfiguration.anthropic_enabled?(configuration)).to be(false)
      end
    end
  end
end
