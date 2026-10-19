require Rails.root.join("lib/run_event_subscriber")
# Initializers run once per boot. Reloadable application classes are not captured.
Rails.event.subscribe(RunEventSubscriber.new) { |event| event[:name] == "llm.classification.finished" }
