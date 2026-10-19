module Providers
  class ConnectionFailure < Error
    def initialize
      super(kind: :connection)
    end
  end
end
