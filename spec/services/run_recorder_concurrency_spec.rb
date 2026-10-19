require "rails_helper"

RSpec.describe "Concurrent run completion" do
  self.use_transactional_tests = false

  it "atomically completes once and publishes one event under competing finish calls" do
    request_id = SecureRandom.uuid
    recorder = RunRecorder.new(request_id: request_id)
    recorder.start!(provider: "fake", model_name: "fake-v1", scenario: "success")
    events = Queue.new
    subscriber = Object.new
    subscriber.define_singleton_method(:emit) { |event| events << event if event[:payload][:request_id] == request_id }
    Rails.event.subscribe(subscriber) { |event| event[:name] == RunRecorder::EVENT_NAME }
    gate = Queue.new
    threads = [ 1, 2 ].map do |attempts|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          recorder.finish(status: "succeeded", attempt_count: attempts, latency_ms: 1)
        end
      end
    end
    2.times { gate << true }
    threads.each(&:value)
    expect(LlmRun.where(request_id: request_id).count).to eq(1)
    expect(LlmRun.find_by!(request_id: request_id).status).to eq("succeeded")
    expect(events.size).to eq(1)
  ensure
    Rails.event.unsubscribe(subscriber) if subscriber
    LlmRun.where(request_id: request_id).delete_all if request_id
  end
end
