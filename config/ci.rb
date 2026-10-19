# Run the same checks locally and on GitHub Actions.
ENV["RAILS_ENV"] = "test"

CI.run do
  step "Dependencies", "bundle check"
  step "Database", "bin/rails db:prepare"
  step "Autoloading", "bin/rails zeitwerk:check"
  step "Assets", "bin/rails assets:precompile"
  step "RSpec", "bundle exec rspec"
  step "Style: Ruby", "bin/rubocop"
  step "Security: Brakeman", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
end
