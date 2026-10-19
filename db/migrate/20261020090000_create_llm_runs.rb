class CreateLlmRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :llm_runs do |t|
      t.string :request_id, limit: 36, null: false
      t.string :provider, limit: 16, null: false
      t.string :model_name, limit: 100, null: false
      t.string :scenario, limit: 40
      t.string :status, limit: 16, null: false, default: "started"
      t.integer :attempt_count
      t.integer :latency_ms
      t.integer :input_tokens
      t.integer :output_tokens
      t.string :error_code, limit: 40
      t.string :provider_request_id, limit: 104
      t.datetime :completed_at
      t.timestamps
    end
    add_index :llm_runs, :request_id, unique: true
    add_index :llm_runs, [ :provider, :created_at ]
    add_check_constraint :llm_runs, "status IN ('started', 'succeeded', 'failed')", name: "llm_runs_status"
    add_check_constraint :llm_runs, "provider IN ('fake', 'anthropic')", name: "llm_runs_provider"
    %w[attempt_count latency_ms input_tokens output_tokens].each do |column|
      add_check_constraint :llm_runs, "#{column} IS NULL OR #{column} >= 0", name: "llm_runs_#{column}_nonnegative"
    end
  end
end
