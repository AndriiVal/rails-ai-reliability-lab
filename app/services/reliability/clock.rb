module Reliability
  class Clock
    def self.call
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
