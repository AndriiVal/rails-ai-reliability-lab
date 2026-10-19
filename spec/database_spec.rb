require "rails_helper"

RSpec.describe "Foundation database" do
  it "connects to the dedicated PostgreSQL 17 test database" do
    connection = ActiveRecord::Base.connection
    expect(connection.adapter_name).to eq("PostgreSQL")
    expect(connection.select_value("SELECT current_database()")).to eq(ENV.fetch("DB_TEST_NAME", "rails_ai_reliability_lab_test"))
    expect(connection.select_value("SHOW server_version_num").to_i).to be_between(170000, 179999)
  end

  it "loads FactoryBot without adding unused application models" do
    FactoryBot.define do
      factory :synthetic_attributes, class: Hash do
        label { "synthetic" }
        initialize_with { attributes }
      end
    end
    expect(build(:synthetic_attributes)).to eq(label: "synthetic")
  end
end
