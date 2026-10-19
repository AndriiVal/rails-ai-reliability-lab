require "spec_helper"
ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"
abort "Tests require the test environment" unless Rails.env.test?
require "rspec/rails"

ActiveRecord::Migration.maintain_test_schema!

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.include FactoryBot::Syntax::Methods
  config.filter_rails_from_backtrace!
end
