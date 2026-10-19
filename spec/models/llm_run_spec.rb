require "rails_helper"

RSpec.describe LlmRun do
  let(:attributes) { { request_id: SecureRandom.uuid, provider: "fake", model_name: "fake-v1", scenario: "success", status: "started", attempt_count: 0 } }

  it "stores only the exact metadata schema and expected indexes" do
    expect(described_class.column_names).to match_array(%w[id request_id provider model_name scenario status attempt_count latency_ms input_tokens output_tokens error_code provider_request_id completed_at created_at updated_at])
    indexes = described_class.connection.indexes(:llm_runs)
    expect(indexes.any? { |i| i.unique && i.columns == [ "request_id" ] }).to be(true)
    expect(indexes.map(&:columns)).to include(%w[provider created_at])
    run = described_class.create!(attributes)
    expect(run.model_name).to eq("fake-v1")
    expect(described_class.model_name).to be_a(ActiveModel::Name)
    expect(run.created_at).to be_a(ActiveSupport::TimeWithZone)
    expect(run.completed_at).to be_nil
  end

  [ { request_id: "unsafe" }, { provider: "unknown" }, { model_name: "private-model" }, { scenario: "unknown" },
    { status: "unknown" }, { attempt_count: -1 }, { latency_ms: -1 }, { input_tokens: -1 }, { output_tokens: 1.5 },
    { error_code: "unsafe" }, { provider_request_id: "unsafe" }, { completed_at: Time.utc(2020) } ].each do |changes|
    it "rejects invalid metadata #{changes.keys}" do
      expect(described_class.new(attributes.merge(changes))).not_to be_valid
    end
  end

  it "enforces unique UUIDs in both validation and PostgreSQL" do
    described_class.create!(attributes)
    expect(described_class.new(attributes)).not_to be_valid
    expect { described_class.insert_all!([ attributes.merge(created_at: Time.current, updated_at: Time.current) ]) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  %w[succeeded failed].each do |state|
    it "permits started to #{state}, then rejects any terminal mutation" do
      run = described_class.create!(attributes)
      run.update!(status: state, completed_at: Time.current, error_code: state == "failed" ? "provider_timeout" : nil)
      expect(run.reload.status).to eq(state)
      expect(run.update(status: state == "failed" ? "succeeded" : "failed")).to be(false)
      expect(run.update(latency_ms: 999)).to be(false)
    end
  end

  it "requires terminal timestamps, safe failure codes and success attempt counts" do
    run = described_class.new(attributes.merge(status: "failed"))
    expect(run).not_to be_valid
    run.assign_attributes(completed_at: Time.current, error_code: "internal_error", attempt_count: nil)
    expect(run).to be_valid
  end

  it "keeps real provider metadata allowlisted and without a fake scenario" do
    run = described_class.new(attributes.merge(provider: "anthropic", model_name: LlmConfiguration::ANTHROPIC_MODELS.first))
    expect(run).not_to be_valid
    run.scenario = nil
    expect(run).to be_valid
  end
end
