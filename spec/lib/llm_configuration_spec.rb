require "spec_helper"
require "active_support/core_ext/object/blank"
require_relative "../../lib/llm_configuration"

RSpec.describe LlmConfiguration do
  it "defaults to fake mode without credentials" do
    expect(described_class.from_env({})).to eq(provider: "fake", enable_real_llm: false)
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
