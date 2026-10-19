require "rails_helper"

RSpec.describe ClassificationValidator do
  let(:valid) { { "category" => "billing", "priority" => "high", "summary" => "Synthetic billing request.", "requires_human_review" => true } }

  it "accepts and deeply freezes a complete classification" do
    result = described_class.call(JSON.generate(valid))
    expect(result).to eq(valid)
    expect(result).to be_frozen
    expect(result.values).to all(be_frozen)
  end

  %w[category priority summary requires_human_review].each do |key|
    it "rejects a missing #{key}" do
      expect { described_class.call(JSON.generate(valid.except(key))) }.to raise_error(described_class::InvalidOutput)
    end
  end

  {
    "extra key" => { "extra" => "ignored?" },
    "invalid category" => { "category" => "unknown" },
    "invalid priority" => { "priority" => "urgent" },
    "empty summary" => { "summary" => "" },
    "Unicode blank summary" => { "summary" => "　" },
    "long summary" => { "summary" => "a" * 241 },
    "non-string summary" => { "summary" => 123 },
    "string boolean" => { "requires_human_review" => "true" },
    "null boolean" => { "requires_human_review" => nil },
    "numeric boolean" => { "requires_human_review" => 1 }
  }.each do |name, overrides|
    it "rejects #{name}" do
      expect { described_class.call(JSON.generate(valid.merge(overrides))) }.to raise_error(described_class::InvalidOutput)
    end
  end

  [ "{invalid", "[]", "null", '"string"', "true", "42" ].each do |body|
    it "rejects invalid or non-object output #{body}" do
      expect { described_class.call(body) }.to raise_error(described_class::InvalidOutput)
    end
  end

  it "accepts false and the Unicode summary length boundary" do
    expect(described_class.call(JSON.generate(valid.merge("summary" => "ї" * 240, "requires_human_review" => false)))).to include("requires_human_review" => false)
  end
end
