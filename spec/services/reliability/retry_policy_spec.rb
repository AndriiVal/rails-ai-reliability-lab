require "rails_helper"
require_relative "../../support/reliability_time"

RSpec.describe Reliability::RetryPolicy do
  let(:time) { ReliabilityTestTime.new }
  let(:random) { double(rand: 1.0) }
  subject(:policy) { described_class.new(random: random, wall_clock: time.method(:wall_time)) }

  [ 408, 409, 429, 500, 503, 599 ].each do |status|
    it("retries HTTP #{status}") { expect(policy.retryable?(Providers::Error.new(status: status))).to be(true) }
  end

  [ 400, 401, 403, 404, 422 ].each do |status|
    it("does not retry HTTP #{status}") { expect(policy.retryable?(Providers::Error.new(status: status))).to be(false) }
  end

  it "retries only known connection and transport timeout failures" do
    expect(policy.retryable?(Providers::ConnectionFailure.new)).to be(true)
    expect(policy.retryable?(Providers::TransportTimeout.new)).to be(true)
  end

  it "uses bounded exponential backoff" do
    error = Providers::Error.new(status: 503)
    expect((0..5).map { |i| policy.delay(error, retry_index: i) }).to eq([ 0.2, 0.4, 0.8, 1.6, 2.0, 2.0 ])
  end

  [ 0.0, 0.5, 1.0 ].each do |sample|
    it "bounds jitter for sample #{sample}" do
      allow(random).to receive(:rand).and_return(sample)
      expect(policy.delay(Providers::Error.new(status: 503), retry_index: 5)).to eq(2 * (0.5 + sample * 0.5))
    end
  end

  [ "1", "0.25", 3, 10.5 ].each do |value|
    it "honors numeric Retry-After #{value}" do
      expect(random).not_to receive(:rand)
      expect(policy.delay(Providers::Error.new(status: 429, retry_after: value), retry_index: 0)).to eq(value.to_f)
    end
  end

  it "keeps valid Retry-After above the normal backoff cap" do
    expect(policy.delay(Providers::Error.new(status: 429, retry_after: "60"), retry_index: 0)).to eq(60)
  end

  it "uses the injected wall clock without rounding an HTTP-date delay down" do
    date = (time.wall_time + 2).httpdate
    time.advance(0.25)
    expect(policy.delay(Providers::Error.new(status: 429, retry_after: date), retry_index: 0)).to eq(1.75)
  end

  [ nil, "", "invalid", "-1", "0", -1, 0, Float::INFINITY, Float::NAN, "1e99", "86401", "9" * 129, "Wed, 01 Jan 2020 00:00:00 GMT" ].each do |value|
    it "falls back for invalid, past or unreasonable Retry-After #{value.inspect}" do
      expect(policy.delay(Providers::Error.new(status: 429, retry_after: value), retry_index: 0)).to eq(0.2)
    end
  end

  [ { max_attempts: 0 }, { max_attempts: 4 }, { max_attempts: 2.5 }, { overall_timeout: 0 },
    { per_attempt_timeout: -1 }, { overall_timeout: Float::INFINITY }, { per_attempt_timeout: Float::NAN },
    { base_delay: -0.1 }, { backoff_cap: -1 }, { base_delay: "1" } ].each do |settings|
    it("rejects invalid settings #{settings}") { expect { described_class.new(**settings) }.to raise_error(ArgumentError) }
  end

  it "permits explicit zero backoff and rejects out-of-range randomness" do
    zero = described_class.new(base_delay: 0, backoff_cap: 0, random: random)
    expect(zero.delay(Providers::Error.new(status: 503), retry_index: 0)).to eq(0)
    allow(random).to receive(:rand).and_return(2.0)
    expect { policy.delay(Providers::Error.new(status: 503), retry_index: 0) }.to raise_error(ArgumentError)
  end
end
