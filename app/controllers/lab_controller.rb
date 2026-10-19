class LabController < ApplicationController
  before_action :authenticate

  def index
  end

  private

  def authenticate
    authenticate_or_request_with_http_basic("Reliability Lab") do |username, password|
      expected_username = ENV["BASIC_AUTH_USERNAME"]
      expected_password = ENV["BASIC_AUTH_PASSWORD"]
      next false if expected_username.blank? || expected_password.blank?

      ActiveSupport::SecurityUtils.secure_compare(username, expected_username) &
        ActiveSupport::SecurityUtils.secure_compare(password, expected_password)
    end
  end
end
