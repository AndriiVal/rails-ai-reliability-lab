module Providers
  class Error < StandardError
    attr_reader :status, :kind, :retry_after

    def initialize(status: nil, kind: :http, retry_after: nil)
      unless %i[http connection timeout].include?(kind) && (kind != :http || (status.is_a?(Integer) && (100..599).cover?(status)))
        raise ArgumentError, "Invalid provider error metadata"
      end
      @status = status
      @kind = kind
      @retry_after = retry_after
      super("Provider failure")
    end
  end
end
