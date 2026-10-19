module LabAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate
  end

  private

  def authenticate
    authenticated = authenticate_with_http_basic do |username, password|
      expected_username = ENV["BASIC_AUTH_USERNAME"]
      expected_password = ENV["BASIC_AUTH_PASSWORD"]
      next false unless username.is_a?(String) && password.is_a?(String)
      next false if expected_username.blank? || expected_password.blank?

      ActiveSupport::SecurityUtils.secure_compare(username, expected_username) &
        ActiveSupport::SecurityUtils.secure_compare(password, expected_password)
    end
    authentication_required unless authenticated
  end

  def authentication_required
    request_http_basic_authentication("Reliability Lab")
  end
end
