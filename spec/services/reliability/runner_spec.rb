require "rails_helper"
require_relative "../../support/reliability_time"

RSpec.describe Reliability::Runner do
  let(:time) { ReliabilityTestTime.new }
  let(:policy) { Reliability::RetryPolicy.new(random: double(rand: 1.0), wall_clock: time.method(:wall_time)) }
  let(:runner) { described_class.new(policy: policy, clock: time, sleeper: time.method(:sleep)) }
  let(:valid) { JSON.generate(category: "billing", priority: "high", summary: "Synthetic request.", requires_human_review: true) }
  let(:provider) { instance_double(Providers::Fake) }
  let(:calls) { [] }

  def sequence(*outcomes, durations: [])
    allow(provider).to receive(:classify) do |**args|
      index = calls.length
      calls << args
      time.advance(durations.fetch(index, 0))
      outcome = outcomes.fetch(index)
      raise outcome if outcome.is_a?(Exception)
      Providers::Response.new(body: outcome, model: Providers::Fake::MODEL)
    end
  end

  def execute
    runner.call(provider: provider, ticket_text: "Synthetic ticket", scenario: "success")
  end

  def expect_failure(code, attempts, retryable)
    expect { execute }.to raise_error(described_class::Failure) do |failure|
      expect([ failure.code, failure.attempt_count, failure.retryable ]).to eq([ code, attempts, retryable ])
      expect(failure.latency_ms).to eq((time.call * 1000).round)
    end
    expect(calls.length).to eq(attempts)
  end

  it "never invokes the provider if the deadline expires before the first attempt" do
    readings = [ 0.0, 25.0, 25.0 ].each
    runner = described_class.new(policy: policy, clock: readings.method(:next), sleeper: time.method(:sleep))
    expect(provider).not_to receive(:classify)
    expect { runner.call(provider: provider, ticket_text: "Synthetic ticket", scenario: "success") }.to raise_error(described_class::Failure) { |error| expect([ error.code, error.attempt_count, error.latency_ms ]).to eq([ :provider_timeout, 0, 25_000 ]) }
  end

  it "counts immediate success and measures actual provider time" do
    sequence(valid, durations: [ 0.025 ])
    expect(execute).to include(attempt_count: 1, latency_ms: 25)
    expect(calls.first).to include(attempt: 1, timeout_seconds: 8.0)
    expect(time.sleeps).to be_empty
  end

  [ 408, 409, 429, 500, 503, 599 ].each do |status|
    it "retries transient HTTP #{status} once before success" do
      sequence(Providers::Error.new(status: status), valid)
      expect(execute[:attempt_count]).to eq(2)
      expect(time.sleeps).to eq([ 0.2 ])
    end
  end

  [ Providers::ConnectionFailure, Providers::TransportTimeout ].each do |klass|
    it "retries known #{klass}" do
      sequence(klass.new, valid)
      expect(execute[:attempt_count]).to eq(2)
    end
  end

  it "uses three calls for 503, 503, success" do
    sequence(Providers::Error.new(status: 503), Providers::Error.new(status: 503), valid)
    expect(execute).to include(attempt_count: 3, latency_ms: 600)
    expect(calls.map { |c| c[:attempt] }).to eq([ 1, 2, 3 ])
  end

  [ [ 429, :rate_limited ], [ 503, :provider_unavailable ] ].each do |status, code|
    it "stops at exactly three #{status} failures" do
      sequence(*Array.new(3) { Providers::Error.new(status: status) })
      expect_failure(code, 3, true)
      expect(time.sleeps.length).to eq(2)
    end
  end

  it "stops after three typed transport timeouts" do
    sequence(*Array.new(3) { Providers::TransportTimeout.new })
    expect_failure(:provider_timeout, 3, true)
  end

  [ 400, 401, 403, 404 ].each do |status|
    it "does not retry permanent HTTP #{status}" do
      sequence(Providers::Error.new(status: status))
      expect_failure([ 401, 403 ].include?(status) ? :provider_auth_error : :provider_unavailable, 1, false)
      expect(time.sleeps).to be_empty
    end
  end

  [ "{invalid", JSON.generate(category: "invalid") ].each do |output|
    it "does not retry malformed or schema-invalid output" do
      sequence(output)
      expect_failure(:invalid_provider_output, 1, false)
      expect(time.sleeps).to be_empty
    end
  end

  it "does not retry or normalize an unclassified Ruby exception" do
    sequence(StandardError.new("PRIVATE-SENTINEL"))
    expect { execute }.to raise_error(StandardError, "PRIVATE-SENTINEL")
    expect(calls.length).to eq(1)
    expect(time.sleeps).to be_empty
  end

  it "honors Retry-After without jittering it or capping to backoff" do
    sequence(Providers::Error.new(status: 429, retry_after: "3"), valid)
    expect(execute).to include(attempt_count: 2, latency_ms: 3000)
    expect(time.sleeps).to eq([ 3.0 ])
  end

  it "honors HTTP-date using separate wall and monotonic time sources" do
    sequence(Providers::Error.new(status: 429, retry_after: (time.wall_time + 1).httpdate), valid)
    expect(execute).to include(attempt_count: 2, latency_ms: 1000)
  end

  [ "25", "26", "3600" ].each do |delay|
    it "fails immediately if Retry-After #{delay} consumes or exceeds remaining budget" do
      sequence(Providers::Error.new(status: 429, retry_after: delay))
      expect_failure(:rate_limited, 1, true)
      expect(time.sleeps).to be_empty
    end
  end

  it "detects deadline expiration during Retry-After policy evaluation" do
    sequence(Providers::Error.new(status: 429, retry_after: (time.wall_time + 1).httpdate))
    policy = Reliability::RetryPolicy.new(wall_clock: -> { time.advance(25); time.wall_time }, random: double(rand: 1.0))
    runner = described_class.new(policy: policy, clock: time, sleeper: time.method(:sleep))
    expect { runner.call(provider: provider, ticket_text: "Synthetic ticket", scenario: "success") }.to raise_error(described_class::Failure) { |error| expect([ error.code, error.attempt_count ]).to eq([ :provider_timeout, 1 ]) }
    expect(calls.length).to eq(1)
    expect(time.sleeps).to be_empty
  end

  it "does not start another attempt after an oversleep exhausts 25 seconds" do
    sequence(Providers::Error.new(status: 503))
    runner = described_class.new(policy: policy, clock: time, sleeper: ->(_seconds) { time.advance(25) })
    expect { runner.call(provider: provider, ticket_text: "Synthetic ticket", scenario: "success") }.to raise_error(described_class::Failure) { |e| expect([ e.code, e.attempt_count, e.latency_ms ]).to eq([ :provider_timeout, 1, 25_000 ]) }
    expect(calls.length).to eq(1)
  end

  it "passes the decreasing remaining budget to a third attempt" do
    sequence(Providers::TransportTimeout.new, Providers::TransportTimeout.new, valid, durations: [ 8, 8, 0 ])
    policy = Reliability::RetryPolicy.new(overall_timeout: 17, random: double(rand: 1.0))
    runner = described_class.new(policy: policy, clock: time, sleeper: time.method(:sleep))
    expect(runner.call(provider: provider, ticket_text: "Synthetic ticket", scenario: "success")[:attempt_count]).to eq(3)
    expect(calls.first(2).map { |call| call[:timeout_seconds] }).to eq([ 8.0, 8.0 ])
    expect(calls.last[:timeout_seconds]).to be_within(1e-9).of(0.4)
  end

  it "rejects a successful provider return after the overall deadline" do
    sequence(valid, durations: [ 25 ])
    expect_failure(:provider_timeout, 1, true)
  end

  it "rejects a return at the per-attempt timeout and permits a bounded retry" do
    sequence(valid, valid, durations: [ 8, 0 ])
    expect(execute[:attempt_count]).to eq(2)
  end

  it "waits the full header minimum when an injected sleeper returns early" do
    sequence(Providers::Error.new(status: 429, retry_after: "1"), valid)
    sleeps = []
    sleeper = ->(seconds) { sleeps << seconds; time.advance(sleeps.length == 1 ? seconds / 2 : seconds) }
    result = described_class.new(policy: policy, clock: time, sleeper: sleeper).call(provider: provider, ticket_text: "Synthetic ticket", scenario: "success")
    expect(result[:latency_ms]).to eq(1000)
    expect(sleeps).to eq([ 1.0, 0.5 ])
  end

  it "fails closed instead of looping if an injected sleeper never advances time" do
    sequence(Providers::Error.new(status: 503))
    runner = described_class.new(policy: policy, clock: time, sleeper: ->(_seconds) { })
    expect { runner.call(provider: provider, ticket_text: "Synthetic ticket", scenario: "success") }.to raise_error(described_class::Failure)
    expect(calls.length).to eq(1)
  end

  it "supports a configured maximum of one without any sleep" do
    sequence(Providers::Error.new(status: 503))
    runner = described_class.new(policy: Reliability::RetryPolicy.new(max_attempts: 1), clock: time, sleeper: time.method(:sleep))
    expect { runner.call(provider: provider, ticket_text: "Synthetic ticket", scenario: "success") }.to raise_error(described_class::Failure) { |error| expect(error.attempt_count).to eq(1) }
    expect(time.sleeps).to be_empty
  end

  it "keeps sequential and concurrent execution counters independent on shared instances" do
    shared_provider = Providers::Fake.new
    shared_runner = described_class.new(policy: Reliability::RetryPolicy.new(base_delay: 0, backoff_cap: 0), sleeper: ->(_seconds) { raise "unexpected sleep" })
    results = Array.new(4) { Thread.new { shared_runner.call(provider: shared_provider, ticket_text: "Synthetic ticket", scenario: "server_error_then_success") } }.map(&:value)
    results << shared_runner.call(provider: shared_provider, ticket_text: "Synthetic ticket", scenario: "server_error_then_success")
    expect(results.map { |r| r[:attempt_count] }).to eq([ 3 ] * 5)
  end
  context "follow-up regressions" do
    context "with a single allowed invocation" do
      let(:policy) { Reliability::RetryPolicy.new(max_attempts: 1, random: double(rand: 1.0)) }

      [ [ 429, 9, :provider_timeout ], [ 401, 9, :provider_timeout ],
        [ 503, 8, :provider_timeout ], [ 503, 7.999, :provider_unavailable ] ].each do |status, duration, code|
        it "classifies HTTP #{status} raised after #{duration} seconds" do
          sequence(Providers::Error.new(status: status), durations: [ duration ])
          expect_failure(code, 1, true)
          expect(time.sleeps).to be_empty
        end
      end
    end

    [ [ 429, 9 ], [ 401, 9 ], [ 503, 8 ] ].each do |status, duration|
      it "retries late HTTP #{status} as a timeout when no header minimum blocks it" do
        sequence(Providers::Error.new(status: status), valid, durations: [ duration, 0 ])
        expect(execute).to include(attempt_count: 2, latency_ms: ((duration + 0.2) * 1000).round)
        expect(time.sleeps.length).to eq(1)
        expect(time.sleeps.first).to be_within(1e-9).of(0.2)
        expect(calls.length).to eq(2)
      end
    end

    it "preserves an excessive valid Retry-After when normalizing a late 429 to timeout" do
      sequence(Providers::Error.new(status: 429, retry_after: "86401"), valid, durations: [ 9, 0 ])
      expect_failure(:provider_timeout, 1, true)
      expect(time.sleeps).to be_empty
      expect(time.call).to eq(9)
    end

    it "honors a fitting header minimum when normalizing a late 503 to timeout" do
      sequence(Providers::Error.new(status: 503, retry_after: "1"), valid, durations: [ 9, 0 ])
      expect(execute).to include(attempt_count: 2, latency_ms: 10_000)
      expect(time.sleeps).to eq([ 1.0 ])
    end

    it "preserves a timely HTTP 503 and honors its Retry-After before retrying" do
      sequence(Providers::Error.new(status: 503, retry_after: "1"), valid, durations: [ 7.999, 0 ])
      expect(execute).to include(attempt_count: 2, latency_ms: 8999)
      expect(time.sleeps.length).to eq(1)
      expect(time.sleeps.first).to be_within(1e-9).of(1)
    end

    it "bounds repeated late errors by three invocations and the remaining overall budget" do
      sequence(*Array.new(3) { Providers::Error.new(status: 503) }, durations: [ 9, 9, 6.4 ])
      expect_failure(:provider_timeout, 3, true)
      expect(time.call).to be_within(1e-9).of(25)
      expect(calls.map { |call| call[:timeout_seconds] }.first(2)).to eq([ 8, 8 ])
      expect(calls.last[:timeout_seconds]).to be_within(1e-9).of(6.4)
    end

    [ "86401", "999999999", "9" * 129, "9" * 10_000, "3600", "25" ].each do |header|
      it "terminates without sleep or early retry for a positive #{header.bytesize}-byte Retry-After" do
        sequence(Providers::Error.new(status: 429, retry_after: header), valid)
        expect_failure(:rate_limited, 1, true)
        expect(time.sleeps).to be_empty
        expect(time.call).to eq(0)
      end
    end

    it "treats a valid HTTP-date two days ahead as an unfulfillable minimum wait" do
      sequence(Providers::Error.new(status: 429, retry_after: (time.wall_time + 172_800).httpdate), valid)
      expect_failure(:rate_limited, 1, true)
      expect(time.sleeps).to be_empty
    end

    it "compares Retry-After against remaining rather than initial budget" do
      sequence(Providers::Error.new(status: 429, retry_after: "20"), valid, durations: [ 6, 0 ])
      expect_failure(:rate_limited, 1, true)
      expect(time.sleeps).to be_empty
    end

    it "still retries malformed Retry-After using ordinary bounded backoff" do
      sequence(Providers::Error.new(status: 429, retry_after: "not-a-delay"), valid)
      expect(execute[:attempt_count]).to eq(2)
      expect(time.sleeps).to eq([ 0.2 ])
    end
  end
end
