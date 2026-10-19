require "rails_helper"
require "net/http"

RSpec.describe "Foundation security" do
  it "filters sensitive parameters and authorization headers" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    keys = %w[password api_key anthropic_api_key prompt ticket_text completion summary Authorization HTTP_AUTHORIZATION]
    payload = keys.to_h { |key| [ key, "private-sentinel" ] }
    expect(filter.filter(payload).values).to all(eq("[FILTERED]"))
  end

  it "preserves the application CSRF protection callback" do
    expect(ApplicationController._process_action_callbacks.map(&:filter)).to include(:verify_authenticity_token)
  end

  it "blocks unmocked external HTTP" do
    expect { Net::HTTP.get(URI("https://example.com/unmocked")) }.to raise_error(WebMock::NetConnectNotAllowedError)
  end

  it "boots in fake mode without provider credentials" do
    expect(Rails.application.config.x.llm[:provider]).to eq("fake")
    expect(Rails.application.config.x.llm[:enable_real_llm]).to be(false)
  end
end
