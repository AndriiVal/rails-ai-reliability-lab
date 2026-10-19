require "rails_helper"
require_relative "../support/reliability_time"

RSpec.describe "Classification API", type: :request do
  let(:ticket) { "I was charged twice for my synthetic subscription." }
  let(:auth) { ActionController::HttpAuthentication::Basic.encode_credentials("api-spec-user", "api-spec-password") }
  let(:headers) { { "CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => auth } }

  around do |example|
    saved = ENV.to_h.slice("BASIC_AUTH_USERNAME", "BASIC_AUTH_PASSWORD")
    configuration = Rails.application.config.x.llm
    ENV["BASIC_AUTH_USERNAME"] = "api-spec-user"
    ENV["BASIC_AUTH_PASSWORD"] = "api-spec-password"
    Rails.application.config.x.llm = { provider: "fake", enable_real_llm: false }
    example.run
  ensure
    %w[BASIC_AUTH_USERNAME BASIC_AUTH_PASSWORD].each { |key| ENV.delete(key) }
    ENV.update(saved)
    Rails.application.config.x.llm = configuration
  end

  before do
    time = ReliabilityTestTime.new
    policy = Reliability::RetryPolicy.new(random: double(rand: 1.0), wall_clock: time.method(:wall_time))
    allow(Reliability::Runner).to receive(:new).and_wrap_original do |method, **args|
      method.call(**args, clock: time, sleeper: time.method(:sleep), policy: policy)
    end
  end

  def classify(payload = nil, request_headers: headers, **attributes)
    payload ||= attributes.presence || { ticket_text: ticket }
    post "/api/v1/classifications", params: JSON.generate(payload), headers: request_headers
  end

  def body
    response.parsed_body
  end

  def expect_error(status, code, attempts)
    expect(response).to have_http_status(status)
    expect(body.keys.sort).to eq(%w[error meta request_id])
    expect(body["request_id"]).to match(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/)
    expect(body["error"].keys.sort).to eq(%w[code message retryable])
    expect(body["error"]).to include("code" => code, "retryable" => false)
    expect(body["meta"]["attempt_count"]).to eq(attempts)
  end

  it "returns the canonical success envelope and a fresh server UUID" do
    classify
    expect(response).to have_http_status(:ok)
    expect(body.keys.sort).to eq(%w[meta request_id result])
    expect(body["result"]).to eq("category" => "billing", "priority" => "high", "summary" => "Synthetic billing request requires review.", "requires_human_review" => true)
    expect(body["meta"].keys.sort).to eq(%w[attempt_count input_tokens latency_ms model output_tokens provider])
    expect(body["meta"]).to include("provider" => "fake", "model" => "fake-v1", "attempt_count" => 1, "input_tokens" => nil, "output_tokens" => nil)
    expect(body["meta"]["latency_ms"]).to be_a(Integer).and be >= 0
    expect(body["request_id"]).to match(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/)
    first = body["request_id"]
    classify
    expect(body["request_id"]).not_to eq(first)
    expect(response.headers).not_to have_key("Set-Cookie")
    expect(response.headers).not_to have_key("Access-Control-Allow-Origin")
  end

  [ nil, "Basic invalid", ActionController::HttpAuthentication::Basic.encode_credentials("wrong", "wrong") ].each do |authorization|
    it "requires valid Basic Auth #{authorization.inspect}" do
      classify(request_headers: headers.merge("HTTP_AUTHORIZATION" => authorization))
      expect_error(401, "unauthorized", 0)
      expect(response.headers["WWW-Authenticate"]).to include("Basic")
    end
  end

  %w[BASIC_AUTH_USERNAME BASIC_AUTH_PASSWORD].each do |key|
    [ nil, "", "   " ].each do |value|
      it "fails closed when #{key} is #{value.inspect}" do
        value.nil? ? ENV.delete(key) : ENV[key] = value
        classify
        expect_error(401, "unauthorized", 0)
      end
    end
  end

  [ nil, 1, [], {}, "", "  ", "short", "　" + "ї" * 9 + "　", "　" * 10, "a" * 3001 ].each do |value|
    it "rejects invalid ticket #{value.inspect}" do
      classify(ticket_text: value)
      expect_error(422, "invalid_input", 0)
    end
  end

  [ "ї" * 10, "🎫" * 3000, "  Synthetic ticket  " ].each do |value|
    it "accepts valid Unicode or normalized ticket at #{value.length} characters" do
      classify(ticket_text: value)
      expect(response).to have_http_status(:ok)
    end
  end

  [ "success?", "not_a_scenario", nil, 1 ].each do |scenario|
    it "rejects unsupported scenario #{scenario.inspect}" do
      classify(ticket_text: ticket, scenario: scenario)
      expect_error(422, "invalid_input", 0)
    end
  end

  %w[provider model api_key url extra request_id].each do |key|
    it "rejects the client-controlled #{key} field" do
      expect_any_instance_of(Providers::Fake).not_to receive(:classify)
      classify({ ticket_text: ticket, key => "private-sentinel" })
      expect_error(422, "invalid_input", 0)
      expect(response.body).not_to include("private-sentinel")
    end
  end

  [ "{invalid", "[]", "null", '"text"', "123", "", '{"ticket_text":"secret-sentinel",' ].each do |raw|
    it "returns a controlled error for malformed/non-object JSON #{raw.inspect}" do
      post "/api/v1/classifications", params: raw, headers: headers
      expect_error(422, "invalid_input", 0)
      expect(response.body).not_to include("secret-sentinel", "ParserError")
    end
  end

  it "rejects invalid UTF-8" do
    post "/api/v1/classifications", params: "{\"ticket_text\":\"bad\xff\"}".b, headers: headers
    expect_error(422, "invalid_input", 0)
  end

  it "limits actual body bytes without trusting Content-Length" do
    post "/api/v1/classifications", params: JSON.generate(ticket_text: "a" * 20_000), headers: headers
    expect_error(422, "invalid_input", 0)
  end

  it "explicitly rejects unsupported media types" do
    classify(request_headers: headers.merge("CONTENT_TYPE" => "text/plain"))
    expect_error(415, "unsupported_media_type", 0)
  end

  %w[malformed_json schema_violation].each do |scenario|
    it "maps #{scenario} to a safe non-retryable 502" do
      classify(ticket_text: ticket, scenario: scenario)
      expect_error(502, "invalid_provider_output", 1)
      expect(response.body).not_to include(ticket)
    end
  end

  it "returns 503 for a server-selected unimplemented provider" do
    Rails.application.config.x.llm = { provider: "anthropic", enable_real_llm: true }
    classify
    expect_error(503, "provider_disabled", 0)
    expect(body["meta"]["provider"]).to eq("disabled")
  end

  it "uses a stateless API while preserving browser CSRF protection" do
    expect(Api::V1::ClassificationsController.ancestors).to include(ActionController::API)
    expect(Api::V1::ClassificationsController.ancestors).not_to include(ActionController::RequestForgeryProtection)
    expect(ApplicationController._process_action_callbacks.map(&:filter)).to include(:verify_authenticity_token)
    classify
    expect(response).to have_http_status(:ok)
  end

  it "never exposes body fields to request logging, including malformed input" do
    payloads = []
    log = StringIO.new
    capture = ActiveSupport::Logger.new(log)
    Rails.logger.broadcast_to(capture)
    subscriber = ActiveSupport::Notifications.subscribe("start_processing.action_controller") { |event| payloads << event.payload[:params] }
    classify(ticket_text: "SENSITIVE-TICKET-SENTINEL", extra: "SENSITIVE-SECRET-SENTINEL")
    post "/api/v1/classifications", params: '{"ticket_text":"SENSITIVE-BROKEN-SENTINEL",', headers: headers
    Providers::Fake::SCENARIOS.each do |scenario|
      classify(ticket_text: "SENSITIVE-SYNTHETIC-SENTINEL", scenario: scenario)
      expect(response.body).not_to include("SENSITIVE")
    end
    expect(payloads.size).to eq(10)
    expect(payloads.map(&:keys)).to all(match_array([ :controller, :action ]))
    expect(response.body).not_to include("SENSITIVE")
    expect(log.string).not_to include("SENSITIVE", auth, "api-spec-password")
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
    Rails.logger.stop_broadcasting_to(capture)
  end

  it "writes exactly one metadata row per run and no unrelated data or outbound HTTP" do
    writes = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |event|
      writes << event.payload[:sql] if event.payload[:sql].match?(/\A\s*(?:INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TRUNCATE)\b/i)
    end
    before_count = LlmRun.count
    classify
    expect(response).to have_http_status(:ok)
    expect(LlmRun.find_by!(request_id: body["request_id"]).status).to eq("succeeded")
    Providers::Fake::SCENARIOS.each { |scenario| classify(ticket_text: ticket, scenario: scenario) }
    expect(LlmRun.count - before_count).to eq(9)
    expect(writes.length).to eq(18)
    expect(writes).to all(match(/\A(?:INSERT INTO|UPDATE) "llm_runs"/))
    expect(LlmRun.all.map(&:attributes).to_json).not_to include(ticket, "api-spec-password", "Synthetic billing request requires review.")
    expect(WebMock::RequestRegistry.instance.requested_signatures.hash).to be_empty
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it "returns a controlled 500 and logs only the error class for unexpected bugs" do
    allow_any_instance_of(Providers::Fake).to receive(:classify).and_raise(NoMethodError, "PRIVATE-BUG-SENTINEL")
    expect(Rails.logger).to receive(:error).with(/Classification failure NoMethodError request_id=/)
    classify
    expect_error(500, "internal_error", nil)
    expect(response.body).not_to include("PRIVATE-BUG-SENTINEL", "NoMethodError", ticket)
  end
  {
    "success" => [ 200, 1, nil, false ],
    "rate_limit_then_success" => [ 200, 2, nil, false ],
    "server_error_then_success" => [ 200, 3, nil, false ],
    "always_rate_limited" => [ 429, 3, "rate_limited", true ],
    "timeout" => [ 504, 3, "provider_timeout", true ],
    "auth_error" => [ 502, 1, "provider_auth_error", false ],
    "malformed_json" => [ 502, 1, "invalid_provider_output", false ],
    "schema_violation" => [ 502, 1, "invalid_provider_output", false ]
  }.each do |scenario, (status, attempts, code, retryable)|
    it "runs #{scenario} with actual invocation counts and canonical responses" do
      expect_any_instance_of(Providers::Fake).to receive(:classify).exactly(attempts).times.and_call_original
      classify(ticket_text: ticket, scenario: scenario)
      expect(response).to have_http_status(status)
      expect(body["meta"]["attempt_count"]).to eq(attempts)
      if code
        expect(body.keys.sort).to eq(%w[error meta request_id])
        expect(body["error"]).to include("code" => code, "retryable" => retryable)
        expect(response.body).not_to include(ticket, "Provider failure", "retry_after")
      else
        expect(body.keys.sort).to eq(%w[meta request_id result])
        expect(body["result"].keys.sort).to eq(%w[category priority requires_human_review summary])
        expect(body["meta"]).to include("provider" => "fake", "input_tokens" => nil, "output_tokens" => nil)
        expect(body["meta"]["latency_ms"]).to eq(scenario == "rate_limit_then_success" ? 1000 : (scenario == "server_error_then_success" ? 600 : 0))
      end
    end
  end
end
