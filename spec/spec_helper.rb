require "webmock/rspec"
WebMock.disable_net_connect!

RSpec.configure do |config|
  config.fail_if_no_examples = true
  config.order = :random
  Kernel.srand config.seed
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
end
