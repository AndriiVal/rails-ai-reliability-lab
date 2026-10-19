require "rails_helper"

RSpec.describe "Foundation", type: :request do
  let(:username) { "foundation-spec-user" }
  let(:password) { "foundation-spec-password" }
  let(:authorization) { ActionController::HttpAuthentication::Basic.encode_credentials(username, password) }

  around do |example|
    original = ENV.to_h.slice("BASIC_AUTH_USERNAME", "BASIC_AUTH_PASSWORD")
    ENV["BASIC_AUTH_USERNAME"] = username
    ENV["BASIC_AUTH_PASSWORD"] = password
    example.run
  ensure
    %w[BASIC_AUTH_USERNAME BASIC_AUTH_PASSWORD].each { |key| ENV.delete(key) }
    ENV.update(original)
  end

  it "challenges requests without credentials" do
    get "/lab"
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["WWW-Authenticate"]).to include("Basic")
  end

  it "rejects incorrect credentials" do
    get "/lab", headers: { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("wrong", "wrong") }
    expect(response).to have_http_status(:unauthorized)
  end

  it "renders the authenticated simulation page and local assets" do
    get "/lab", headers: { "Authorization" => authorization }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Simulation environment", "No real LLM requests", "Rails AI Reliability Lab")
    document = Nokogiri::HTML(response.body)
    assets = document.css('link[rel="stylesheet"]').map { |link| link["href"] }
    imports = JSON.parse(document.at_css('script[type="importmap"]').text).fetch("imports")
    expect(imports.keys).to include("application", "@hotwired/turbo-rails", "@hotwired/stimulus")
    assets.concat(imports.values)
    expect(assets).not_to be_empty
    assets.each do |path|
      expect(path).to start_with("/assets/")
      get path
      expect(response).to have_http_status(:ok)
    end
    expect(File.read(Rails.root.join("app/assets/builds/tailwind.css"))).to include(".text-indigo-700")
  end

  %w[BASIC_AUTH_USERNAME BASIC_AUTH_PASSWORD].each do |key|
    [ nil, "", "   " ].each do |value|
      it "fails closed with #{key} configured as #{value.inspect}" do
        value.nil? ? ENV.delete(key) : ENV[key] = value
        get "/lab", headers: { "Authorization" => authorization }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  it "does not accept empty credentials when configuration is blank" do
    ENV["BASIC_AUTH_USERNAME"] = ""
    ENV["BASIC_AUTH_PASSWORD"] = ""
    get "/lab", headers: { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("", "") }
    expect(response).to have_http_status(:unauthorized)
  end

  it "serves a public minimal health check without confidential information" do
    get "/up"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(username, password, "DB_PASSWORD", "postgresql", "ANTHROPIC", "4.0.6", "8.1.4")
    expect(response.body).to include("background-color: green")
  end
end
