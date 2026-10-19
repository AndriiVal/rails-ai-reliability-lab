# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_20_090000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "llm_runs", force: :cascade do |t|
    t.string "request_id", limit: 36, null: false
    t.string "provider", limit: 16, null: false
    t.string "model_name", limit: 100, null: false
    t.string "scenario", limit: 40
    t.string "status", limit: 16, default: "started", null: false
    t.integer "attempt_count"
    t.integer "latency_ms"
    t.integer "input_tokens"
    t.integer "output_tokens"
    t.string "error_code", limit: 40
    t.string "provider_request_id", limit: 104
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "created_at"], name: "index_llm_runs_on_provider_and_created_at"
    t.index ["request_id"], name: "index_llm_runs_on_request_id", unique: true
    t.check_constraint "attempt_count IS NULL OR attempt_count >= 0", name: "llm_runs_attempt_count_nonnegative"
    t.check_constraint "input_tokens IS NULL OR input_tokens >= 0", name: "llm_runs_input_tokens_nonnegative"
    t.check_constraint "latency_ms IS NULL OR latency_ms >= 0", name: "llm_runs_latency_ms_nonnegative"
    t.check_constraint "output_tokens IS NULL OR output_tokens >= 0", name: "llm_runs_output_tokens_nonnegative"
    t.check_constraint "provider::text = ANY (ARRAY['fake'::character varying, 'anthropic'::character varying]::text[])", name: "llm_runs_provider"
    t.check_constraint "status::text = ANY (ARRAY['started'::character varying, 'succeeded'::character varying, 'failed'::character varying]::text[])", name: "llm_runs_status"
  end
end
