class LlmRun < ApplicationRecord
  # The required metadata column collides with ActiveModel's instance helper.
  # Keep this exception local; class-level model_name (used by Rails) is intact.
  def self.dangerous_attribute_method?(name)
    name == "model_name" ? false : super
  end

  ERROR_CODES = %w[invalid_provider_output provider_auth_error rate_limited provider_unavailable provider_timeout internal_error].freeze
  validates :request_id, format: { with: /\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/ }, uniqueness: true
  validates :provider, inclusion: { in: %w[fake anthropic] }
  validates :status, inclusion: { in: %w[started succeeded failed] }
  validates :scenario, inclusion: { in: Providers::Fake::SCENARIOS }, allow_nil: true
  validates :error_code, inclusion: { in: ERROR_CODES }, allow_nil: true
  validates :model_name, presence: true, length: { maximum: 100 }
  validates :attempt_count, :latency_ms, :input_tokens, :output_tokens,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :provider_request_id, format: { with: /\Areq_[A-Za-z0-9_-]{1,100}\z/ }, allow_nil: true
  validate :consistent_metadata
  validate :terminal_is_immutable, on: :update

  scope :recent_simulated, -> { where(provider: "fake").order(created_at: :desc, id: :desc).limit(10) }

  private

  def consistent_metadata
    allowed_models = provider == "fake" ? [ Providers::Fake::MODEL ] : LlmConfiguration::ANTHROPIC_MODELS
    errors.add(:model_name, "is not supported") unless allowed_models.include?(model_name)
    errors.add(:scenario, "must be absent for real providers") if provider == "anthropic" && scenario
    errors.add(:completed_at, "must match status") unless (status == "started") == completed_at.nil?
    errors.add(:error_code, "must match status") unless (status == "failed") == error_code.present?
    errors.add(:attempt_count, "is required for success") if status == "succeeded" && attempt_count.nil?
  end

  def terminal_is_immutable
    errors.add(:base, "Completed runs cannot change") if status_in_database != "started" && changed?
  end
end
