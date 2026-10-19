require "rails_helper"
require "anthropic"
require_relative "../support/reliability_time"

RSpec.describe "Interactive simulation dashboard", type: :request do
  let(:auth) { ActionController::HttpAuthentication::Basic.encode_credentials("lab-user", "lab-password") }
  let(:headers) { { "HTTP_AUTHORIZATION" => auth } }

  around do |example|
    saved = ENV.to_h.slice("BASIC_AUTH_USERNAME", "BASIC_AUTH_PASSWORD")
    prior = Rails.application.config.x.llm
    csrf = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    ENV.update("BASIC_AUTH_USERNAME" => "lab-user", "BASIC_AUTH_PASSWORD" => "lab-password")
    Rails.application.config.x.llm = { provider: "anthropic", enable_real_llm: true,
      anthropic_api_key: "PRIVATE-KEY", anthropic_model: LlmConfiguration::ANTHROPIC_MODELS.first }
    example.run
  ensure
    ENV.delete("BASIC_AUTH_USERNAME"); ENV.delete("BASIC_AUTH_PASSWORD"); ENV.update(saved)
    Rails.application.config.x.llm = prior
    ActionController::Base.allow_forgery_protection = csrf
  end

  before do
    time = ReliabilityTestTime.new
    allow(Reliability::Runner).to receive(:new).and_wrap_original do |method, **args|
      method.call(**args, clock: time, sleeper: time.method(:sleep), policy: Reliability::RetryPolicy.new(random: double(rand: 1.0)))
    end
    expect(::Anthropic::Client).not_to receive(:new)
  end

  def token
    get "/lab", headers: headers
    Nokogiri::HTML(response.body).at_css('input[name="authenticity_token"]')["value"]
  end

  def run_scenario(scenario = "success", ticket: "Synthetic invented billing ticket", **extra)
    authenticity_token = token
    post "/lab/run", params: { ticket_text: ticket, scenario: scenario, authenticity_token: authenticity_token }.merge(extra), headers: headers
  end

  it "renders an accessible no-JavaScript form without executing a provider on GET" do
    expect_any_instance_of(Providers::Fake).not_to receive(:classify)
    get "/lab", headers: headers
    expect(response.status).to eq(200)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css('form[action="/lab/run"][method="post"][data-turbo="false"]')).not_to be_nil
    expect(html.at_css('label[for="ticket_text"]').text).to eq("Synthetic support ticket")
    expect(html.at_css('textarea[name="ticket_text"]')["maxlength"]).to be_nil
    expect(html.css('select[name="scenario"] option').map { |o| o["value"] }).to eq(Providers::Fake::SCENARIOS)
    expect(response.body).to include(LabController::DEFAULT_TICKET, "No simulated runs yet", "Simulation environment")
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  [ nil, "Basic invalid" ].each do |credentials|
    it "rejects unauthenticated POST before CSRF or recording" do
      post "/lab/run", params: { ticket_text: "Synthetic ticket" }, headers: { "HTTP_AUTHORIZATION" => credentials }
      expect(response.status).to eq(401)
      expect(LlmRun.count).to eq(0)
    end
  end

  %w[BASIC_AUTH_USERNAME BASIC_AUTH_PASSWORD].each do |key|
    [ nil, "", " " ].each do |value|
      it "rejects POST with blank #{key}" do
        value.nil? ? ENV.delete(key) : ENV[key] = value
        post "/lab/run", headers: headers
        expect(response.status).to eq(401)
      end
    end
  end

  [ nil, "invalid" ].each do |csrf_token|
    it "enforces real CSRF verification for token #{csrf_token.inspect}" do
      expect_any_instance_of(Providers::Fake).not_to receive(:classify)
      post "/lab/run", params: { ticket_text: "Synthetic ticket", scenario: "success", authenticity_token: csrf_token }, headers: headers
      expect(response.status).to eq(422)
      expect(LlmRun.count).to eq(0)
    end
  end

  { "success" => [ 200, 1 ], "rate_limit_then_success" => [ 200, 2 ], "server_error_then_success" => [ 200, 3 ],
    "always_rate_limited" => [ 429, 3 ], "timeout" => [ 504, 3 ], "malformed_json" => [ 502, 1 ],
    "schema_violation" => [ 502, 1 ], "auth_error" => [ 502, 1 ] }.each do |scenario, (status, attempts)|
    it "runs #{scenario} with real CSRF, actual counts and Fake-only isolation under real configuration" do
      before = Rails.application.config.x.llm.dup
      run_scenario(scenario)
      expect(response.status).to eq(status)
      expect(Nokogiri::HTML(response.body).at_css('[data-testid="attempt-count"]').text).to eq(attempts.to_s)
      run = LlmRun.last
      expect([ run.provider, run.scenario, run.attempt_count ]).to eq([ "fake", scenario, attempts ])
      expect(response.body).not_to include(run.request_id, "PRIVATE-KEY")
      expect(Rails.application.config.x.llm).to eq(before)
      expect(WebMock::RequestRegistry.instance.requested_signatures.hash).to be_empty
    end
  end

  [ { ticket: "short" }, { scenario: "unknown" }, { scenario: nil } ].each do |values|
    it "rejects invalid input #{values} without recording or provider execution" do
      expect_any_instance_of(Providers::Fake).not_to receive(:classify)
      run_scenario(values.fetch(:scenario, "success"), ticket: values.fetch(:ticket, "Synthetic ticket"))
      expect(response.status).to eq(422)
      expect(response.body).to include('role="alert"', "10–3,000")
      expect(LlmRun.count).to eq(0)
    end
  end

  it "does not execute a scenario through GET /lab/run" do
    expect_any_instance_of(Providers::Fake).not_to receive(:classify)
    get "/lab/run", headers: headers
    expect(response.status).to eq(404)
    expect(LlmRun.count).to eq(0)
  end

  it "rejects an oversized authenticated form without execution" do
    expect_any_instance_of(Providers::Fake).not_to receive(:classify)
    run_scenario(ticket: "a" * 70_000)
    expect(response.status).to eq(422)
    expect(LlmRun.count).to eq(0)
  end

  it "accepts the 3,000-codepoint Unicode limit within the bounded encoded form" do
    run_scenario(ticket: "🎫" * 3000)
    expect(response.status).to eq(200)
    expect(LlmRun.last.status).to eq("succeeded")
  end

  it "rejects browser provider overrides" do
    expect_any_instance_of(Providers::Fake).not_to receive(:classify)
    run_scenario("success", provider: "anthropic", api_key: "PRIVATE-KEY")
    expect(response.status).to eq(422)
    expect(LlmRun.count).to eq(0)
  end

  it "escapes both editable ticket text and untrusted classification summaries" do
    script = '<script>alert("synthetic")</script>'
    allow_any_instance_of(Providers::Fake).to receive(:classify).and_return(Providers::Response.new(
      body: JSON.generate(category: "other", priority: "low", summary: script, requires_human_review: false), model: "fake-v1"))
    run_scenario(ticket: script)
    expect(response.status).to eq(200)
    expect(response.body).not_to include(script)
    expect(response.body).to include("&lt;script&gt;")
    expect(LlmRun.last.attributes.to_json).not_to include("synthetic", "script")
    get "/lab", headers: headers
    expect(response.body).not_to include("alert", "&lt;script&gt;")
  end

  it "shows at most ten fake rows, newest first, and no real-provider rows or full identifiers" do
    12.times { |i| LlmRun.create!(request_id: SecureRandom.uuid, provider: "fake", model_name: "fake-v1", scenario: "success", attempt_count: i) }
    LlmRun.create!(request_id: SecureRandom.uuid, provider: "anthropic", model_name: LlmConfiguration::ANTHROPIC_MODELS.first)
    get "/lab", headers: headers
    html = Nokogiri::HTML(response.body)
    rows = html.css("tbody tr")
    expect(rows.size).to eq(10)
    expect(rows.first.css("td")[2].text).to eq("11")
    LlmRun.pluck(:request_id).each { |id| expect(response.body).not_to include(id) }
    expect(response.body).not_to include(LlmConfiguration::ANTHROPIC_MODELS.first)
  end

  it "logs neither submitted fields nor unexpected exception messages" do
    log = StringIO.new
    capture = ActiveSupport::Logger.new(log)
    Rails.logger.broadcast_to(capture)
    expect_any_instance_of(Providers::Fake).to receive(:classify).once.and_raise(StandardError, "PRIVATE-EXCEPTION")
    run_scenario(ticket: "PRIVATE-TICKET-SENTINEL")
    expect(response.status).to eq(500)
    expect(log.string).not_to include("PRIVATE", "lab-password", auth)
    expect(response.body).not_to include("PRIVATE-EXCEPTION")
    expect(LlmRun.last.attempt_count).to be_nil
    expect(LlmRun.last.error_code).to eq("internal_error")
  ensure
    Rails.logger.stop_broadcasting_to(capture)
  end
end
