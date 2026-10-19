module Providers
  class TransportTimeout < Error
    def initialize(retry_after: nil)
      super(kind: :timeout, retry_after: retry_after)
    end
  end
end
