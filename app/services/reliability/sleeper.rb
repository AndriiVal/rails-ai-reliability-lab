module Reliability
  class Sleeper
    def self.call(seconds)
      Kernel.sleep(seconds)
    end
  end
end
