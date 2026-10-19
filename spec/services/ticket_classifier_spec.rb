require "rails_helper"
require_relative "../support/reliability_time"

RSpec.describe TicketClassifier do
  let(:provider) { Providers::Fake.new }
  let(:time) { ReliabilityTestTime.new }
  let(:runner) { Reliability::Runner.new(clock: time, sleeper: time.method(:sleep)) }
  subject(:classifier) { described_class.new(configuration: { provider: "fake", enable_real_llm: false }, provider: provider, runner: runner) }

  it "normalizes input, invokes the provider once and validates its output" do
    expect(provider).to receive(:classify).with(ticket_text: "Synthetic billing ticket", scenario: "success", attempt: 1, timeout_seconds: 8).once.and_wrap_original { |method, **args| time.advance(0.025); method.call(**args) }
    expect(ClassificationValidator).to receive(:call).once.and_call_original
    outcome = classifier.call(ticket_text: "　 Synthetic billing ticket　 ")
    expect(outcome[:meta]).to eq(provider: "fake", model: "fake-v1", attempt_count: 1, latency_ms: 25, input_tokens: nil, output_tokens: nil)
  end

  [ nil, 1, [], {}, "", "  ", "short", "　" * 10, "a" * 3001, "bad\xff".b.force_encoding("UTF-8") ].each do |ticket|
    it "rejects invalid input #{ticket.inspect} before invoking the provider" do
      expect(provider).not_to receive(:classify)
      expect { classifier.call(ticket_text: ticket) }.to raise_error(described_class::Error) { |error| expect([ error.code, error.attempt_count ]).to eq([ :invalid_input, 0 ]) }
    end
  end

  [ "unknown", nil, 1 ].each do |scenario|
    it "rejects invalid scenario #{scenario.inspect} before invoking the provider" do
      expect(provider).not_to receive(:classify)
      expect { classifier.call(ticket_text: "Synthetic ticket", scenario: scenario) }.to raise_error(described_class::Error)
    end
  end

  %w[malformed_json schema_violation].each do |scenario|
    it "validates #{scenario} with one actual attempt and no retry" do
      expect(provider).to receive(:classify).once.and_call_original
      expect { classifier.call(ticket_text: "Synthetic ticket", scenario: scenario) }.to raise_error(described_class::Error) { |error| expect([ error.code, error.attempt_count ]).to eq([ :invalid_provider_output, 1 ]) }
    end
  end

  it "refuses an unimplemented provider even with the real-provider flag enabled" do
    expect(provider).not_to receive(:classify)
    service = described_class.new(configuration: { provider: "anthropic", enable_real_llm: true }, provider: provider)
    expect { service.call(ticket_text: "Synthetic ticket") }.to raise_error(described_class::Error) { |error| expect([ error.code, error.attempt_count ]).to eq([ :provider_disabled, 0 ]) }
  end

  it "does not hide unexpected programming errors as provider validation failures" do
    allow(provider).to receive(:classify).and_raise(NoMethodError, "synthetic bug")
    expect { classifier.call(ticket_text: "Synthetic ticket") }.to raise_error(NoMethodError)
  end
end
