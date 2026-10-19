require "rails_helper"
require_relative "../support/anthropic_response"
require_relative "../support/reliability_time"

RSpec.describe "Anthropic classification API", type: :request do
  include AnthropicResponse
  let(:model) { LlmConfiguration::ANTHROPIC_MODELS.first }
  let(:configuration) { { provider: "anthropic", enable_real_llm: true, anthropic_api_key: "synthetic-key-sentinel", anthropic_model: model } }
  let(:ticket) { "PRIVATE-SYNTHETIC-TICKET-SENTINEL" }
  let(:auth) { ActionController::HttpAuthentication::Basic.encode_credentials("spec-user", "spec-password") }
  let(:headers) { { "CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => auth } }

  around do |example|
    saved = ENV.to_h.slice("BASIC_AUTH_USERNAME", "BASIC_AUTH_PASSWORD")
    prior = Rails.application.config.x.llm
    ENV.update("BASIC_AUTH_USERNAME" => "spec-user", "BASIC_AUTH_PASSWORD" => "spec-password")
    Rails.application.config.x.llm = configuration
    example.run
  ensure
    %w[BASIC_AUTH_USERNAME BASIC_AUTH_PASSWORD].each { |key| ENV.delete(key) }
    ENV.update(saved)
    Rails.application.config.x.llm = prior
  end

  before do
    time = ReliabilityTestTime.new
    allow(Reliability::Runner).to receive(:new).and_wrap_original do |method, **args|
      method.call(**args, clock: time, sleeper: time.method(:sleep), policy: Reliability::RetryPolicy.new(random: double(rand: 1.0)))
    end
  end

  def classify(**extra)
    post "/api/v1/classifications", params: JSON.generate({ ticket_text: ticket }.merge(extra)), headers: headers
  end

  def body
    response.parsed_body
  end

  it "accepts an omitted scenario, validates JSON and exposes only final successful usage" do
    stub = stub_anthropic.with { |request| !request.headers.key?("Authorization") }
    classify
    expect(response).to have_http_status(:ok)
    expect(body["result"]).to eq(JSON.parse(JSON.generate(classification)))
    expect(body["meta"]).to include("provider" => "anthropic", "model" => model,
      "attempt_count" => 1, "input_tokens" => 120, "output_tokens" => 45)
    expect(body["meta"].keys).to match_array(%w[provider model attempt_count latency_ms input_tokens output_tokens])
    expect(body["request_id"]).to match(/\A[0-9a-f-]{36}\z/)
    expect(response.body).not_to include("req_synthetic", "synthetic-key", ticket)
    expect(response.headers).not_to have_key("Set-Cookie")
    expect(stub).to have_been_requested.once
  end

  [ "success", nil, "unknown" ].each do |scenario|
    it "rejects explicitly supplied scenario #{scenario.inspect} without client creation" do
      expect(::Anthropic::Client).not_to receive(:new)
      classify(scenario: scenario)
      expect(response).to have_http_status(:unprocessable_content)
      expect(body.dig("error", "code")).to eq("invalid_input")
      expect(body.dig("meta", "attempt_count")).to eq(0)
    end
  end

  [ { enable_real_llm: false }, { enable_real_llm: "true" }, { anthropic_api_key: nil },
    { anthropic_api_key: "" }, { anthropic_api_key: "  " }, { anthropic_model: nil },
    { anthropic_model: "unsupported" }, { provider: "unknown" } ].each do |changes|
    it "fails closed with zero SDK calls for #{changes.keys}" do
      Rails.application.config.x.llm = configuration.merge(changes)
      expect(::Anthropic::Client).not_to receive(:new)
      classify
      expect(response).to have_http_status(:service_unavailable)
      expect(body.dig("error", "code")).to eq("provider_disabled")
      expect(body.dig("meta", "attempt_count")).to eq(0)
      expect(response.body).not_to include(model, "synthetic-key")
    end
  end

  %i[provider model api_key base_url budget request_options system tools].each do |key|
    it "rejects untrusted #{key} configuration without client creation" do
      expect(::Anthropic::Client).not_to receive(:new)
      classify(**{ key => "unsafe" })
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  it "requires authentication before SDK construction" do
    expect(::Anthropic::Client).not_to receive(:new)
    post "/api/v1/classifications", params: JSON.generate(ticket_text: ticket), headers: headers.except("HTTP_AUTHORIZATION")
    expect(response).to have_http_status(:unauthorized)
  end

  it "validates input before SDK construction" do
    expect(::Anthropic::Client).not_to receive(:new)
    classify(ticket_text: "short")
    expect(response).to have_http_status(:unprocessable_content)
  end

  [ [ 401, 502, "provider_auth_error", 1 ], [ 403, 502, "provider_auth_error", 1 ],
    [ 408, 503, "provider_unavailable", 3 ], [ 409, 503, "provider_unavailable", 3 ],
    [ 429, 429, "rate_limited", 3 ], [ 503, 503, "provider_unavailable", 3 ] ].each do |upstream, status, code, attempts|
    it "maps upstream #{upstream} to safe HTTP #{status} after #{attempts} real SDK attempts" do
      stub = stub_anthropic({ error: { type: "api_error", message: "PRIVATE-ERROR-SENTINEL" } }, status: upstream)
      classify
      expect(response.status).to eq(status)
      expect(body.dig("error", "code")).to eq(code)
      expect(body.dig("meta", "attempt_count")).to eq(attempts)
      expect(response.body).not_to include("PRIVATE", "synthetic-key", model)
      expect(stub).to have_been_requested.times(attempts)
    end
  end

  it "maps SDK timeouts to HTTP 504 with no fourth attempt" do
    stub = stub_request(:post, "https://api.anthropic.com/v1/messages").to_timeout
    classify
    expect(response.status).to eq(504)
    expect(body.dig("error", "code")).to eq("provider_timeout")
    expect(body.dig("meta", "attempt_count")).to eq(3)
    expect(stub).to have_been_requested.times(3)
  end

  it "does not log or persist ticket, key, prompt, completion, error bodies or credentials" do
    log = StringIO.new
    capture = ActiveSupport::Logger.new(log)
    Rails.logger.broadcast_to(capture)
    writes = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |event|
      writes << event.payload[:sql] if event.payload[:sql].match?(/\A\s*(?:INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TRUNCATE)\b/i)
    end
    stub_anthropic(anthropic_response(content: [ { type: "text", text: JSON.generate(classification.merge(summary: "PRIVATE-COMPLETION-SENTINEL")) } ]))
    classify
    expect(response.status).to eq(200)
    stub_anthropic({ error: { type: "api_error", message: "PRIVATE-ERROR-SENTINEL" } }, status: 401)
    classify
    expect(response.status).to eq(502)
    expect_any_instance_of(::Anthropic::Resources::Messages).to receive(:create).once.and_raise(StandardError, "PRIVATE-UNEXPECTED-SENTINEL")
    classify
    expect(response.status).to eq(500)
    expect(body.dig("error", "code")).to eq("internal_error")
    expect(log.string).not_to include("PRIVATE", "synthetic-key", "spec-password", auth, Providers::Anthropic::SYSTEM_PROMPT)
    expect(response.body).not_to include("PRIVATE", "synthetic-key", "StandardError")
    expect(writes.length).to eq(6)
    expect(writes).to all(match(/\A(?:INSERT INTO|UPDATE) "llm_runs"/))
    runs = LlmRun.order(:id).last(3)
    expect(runs.map(&:status)).to eq(%w[succeeded failed failed])
    expect(runs.map(&:attempt_count)).to eq([ 1, 1, nil ])
    expect(runs.first.attributes).to include("provider" => "anthropic", "model_name" => model, "input_tokens" => 120, "output_tokens" => 45)
    expect(runs.map(&:attributes).to_json).not_to include("PRIVATE", "synthetic-key", "spec-password", auth, Providers::Anthropic::SYSTEM_PROMPT)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
    Rails.logger.stop_broadcasting_to(capture)
  end
end
