require "rails_helper"
require_relative "../support/reliability_time"

RSpec.describe ClassificationWorkflow do
  let(:time) { ReliabilityTestTime.new }
  let(:provider) { Providers::Fake.new }
  let(:runner) { Reliability::Runner.new(clock: time, sleeper: time.method(:sleep), policy: Reliability::RetryPolicy.new(random: double(rand: 1.0))) }
  let(:classifier) { TicketClassifier.new(configuration: { provider: "fake" }, provider: provider, runner: runner) }
  let(:workflow) { described_class.new(classifier: classifier) }
  let(:id) { SecureRandom.uuid }
  let(:events) { [] }

  around do |example|
    collector = Object.new
    captured = events
    collector.define_singleton_method(:emit) { |event| captured << event }
    Rails.event.subscribe(collector) { |event| event[:name] == RunRecorder::EVENT_NAME }
    example.run
  ensure
    Rails.event.unsubscribe(collector)
  end

  def execute(scenario = "success", ticket: "PRIVATE-SYNTHETIC-TICKET")
    workflow.call(request_id: id, ticket_text: ticket, scenario: scenario)
  end

  def event_payload
    events.fetch(0).fetch(:payload)
  end

  it "starts only after validation and records exactly one run/event across retries" do
    expect(provider).to receive(:classify).exactly(3).times.and_wrap_original do |method, **args|
      expect(LlmRun.find_by!(request_id: id).status).to eq("started")
      method.call(**args)
    end
    outcome = execute("server_error_then_success")
    run = LlmRun.find_by!(request_id: id)
    expect(run.attributes).to include("provider" => "fake", "model_name" => "fake-v1", "status" => "succeeded",
      "scenario" => "server_error_then_success", "attempt_count" => 3, "latency_ms" => 600, "input_tokens" => nil)
    expect(run.completed_at).not_to be_nil
    expect(outcome[:meta][:latency_ms]).to eq(run.latency_ms)
    expect(events.size).to eq(1)
    expect(event_payload).to eq(request_id: id, provider: "fake", outcome: "succeeded", attempt_count: 3, latency_ms: 600, error_code: nil)
    expect([ run.attributes, events ].to_json).not_to include("PRIVATE", "summary", "ticket_text", "completion", "Synthetic general support request.")
  end

  [ [ "always_rate_limited", "rate_limited", 3, 2000 ], [ "timeout", "provider_timeout", 3, 600 ],
    [ "malformed_json", "invalid_provider_output", 1, 0 ], [ "auth_error", "provider_auth_error", 1, 0 ] ].each do |scenario, code, attempts, latency|
    it "records accurate controlled failure for #{scenario}" do
      expect { execute(scenario) }.to raise_error(TicketClassifier::Error)
      run = LlmRun.find_by!(request_id: id)
      expect([ run.status, run.error_code, run.attempt_count, run.latency_ms ]).to eq([ "failed", code, attempts, latency ])
      expect(events.size).to eq(1)
      expect(event_payload).to include(error_code: code, attempt_count: attempts, outcome: "failed")
    end
  end

  it "excludes invalid inputs and disabled providers from recording and events" do
    expect(provider).not_to receive(:classify)
    expect { execute(ticket: "short") }.to raise_error(TicketClassifier::Error)
    disabled = described_class.new(classifier: TicketClassifier.new(configuration: { provider: "anthropic" }))
    expect { disabled.call(request_id: id, ticket_text: "Synthetic ticket") }.to raise_error(TicketClassifier::Error) { |e| expect(e.code).to eq(:provider_disabled) }
    expect(LlmRun.where(request_id: id)).to be_empty
    expect(events).to be_empty
  end

  it "marks unexpected exceptions failed with unknown counts and no sensitive diagnostics" do
    expect(provider).to receive(:classify).once.and_raise(StandardError, "PRIVATE-ERROR")
    expect { execute }.to raise_error(StandardError)
    run = LlmRun.find_by!(request_id: id)
    expect([ run.status, run.error_code, run.attempt_count, run.latency_ms ]).to eq([ "failed", "internal_error", nil, nil ])
    expect(events.size).to eq(1)
    expect(events.to_json).not_to include("PRIVATE", "StandardError")
  end

  it "fails closed before invocation if initial recording fails" do
    allow(LlmRun).to receive(:create!).and_raise(ActiveRecord::ConnectionNotEstablished, "PRIVATE-DB")
    expect(provider).not_to receive(:classify)
    expect { execute }.to raise_error(ActiveRecord::ConnectionNotEstablished)
    expect(events).to be_empty
  end

  it "never repeats a completed provider call when terminal recording fails" do
    expect(provider).to receive(:classify).once.and_call_original
    allow(LlmRun).to receive(:find).and_raise(ActiveRecord::ConnectionNotEstablished, "PRIVATE-DB")
    expect(execute[:result]).to be_a(Hash)
    expect(LlmRun.find_by!(request_id: id).status).to eq("started")
    expect(events).to be_empty
  end

  it "keeps completed metadata and does not repeat invocation if event publication fails" do
    expect(provider).to receive(:classify).once.and_call_original
    allow(Rails.event).to receive(:notify).with(RunRecorder::EVENT_NAME, anything).and_raise(StandardError, "PRIVATE-EVENT")
    expect(execute[:meta][:attempt_count]).to eq(1)
    expect(LlmRun.find_by!(request_id: id).status).to eq("succeeded")
  end

  it "does not repeat provider execution when a native Rails event subscriber raises" do
    subscriber = Object.new
    subscriber.define_singleton_method(:emit) { |_event| raise StandardError, "PRIVATE-SUBSCRIBER" }
    Rails.event.subscribe(subscriber) { |event| event[:name] == RunRecorder::EVENT_NAME }
    expect(provider).to receive(:classify).once.and_call_original
    expect(execute[:meta][:attempt_count]).to eq(1)
    expect(LlmRun.find_by!(request_id: id).status).to eq("succeeded")
  ensure
    Rails.event.unsubscribe(subscriber)
  end

  it "emits no duplicate event and cannot change a completed row" do
    recorder = RunRecorder.new(request_id: id)
    recorder.start!(provider: "fake", model_name: "fake-v1", scenario: "success")
    recorder.finish(status: "succeeded", attempt_count: 1, latency_ms: 5)
    recorder.finish(status: "failed", attempt_count: 3, error_code: "provider_timeout")
    expect(LlmRun.find_by!(request_id: id).status).to eq("succeeded")
    expect(events.size).to eq(1)
  end
end
