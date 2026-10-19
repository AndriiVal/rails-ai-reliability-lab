module Providers
  class TransportTimeout < Error
    def initialize
      super(kind: :timeout)
    end
  end
end
