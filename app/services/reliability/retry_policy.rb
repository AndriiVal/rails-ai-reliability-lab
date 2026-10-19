require "time"

module Reliability
  class RetryPolicy
    attr_reader :max_attempts, :per_attempt_timeout, :overall_timeout

    def initialize(max_attempts: 3, per_attempt_timeout: 8.0, overall_timeout: 25.0,
      base_delay: 0.2, backoff_cap: 2.0, random: Random.new, wall_clock: -> { Time.now })
      unless max_attempts.is_a?(Integer) && (1..3).cover?(max_attempts) &&
          [ per_attempt_timeout, overall_timeout ].all? { |value| finite_number?(value) && value.positive? } &&
          [ base_delay, backoff_cap ].all? { |value| finite_number?(value) && value >= 0 }
        raise ArgumentError, "Invalid reliability settings"
      end
      @max_attempts, @per_attempt_timeout, @overall_timeout = max_attempts, per_attempt_timeout, overall_timeout
      @base_delay, @backoff_cap, @random, @wall_clock = base_delay, backoff_cap, random, wall_clock
    end

    def retryable?(error)
      %i[connection timeout].include?(error.kind) || [ 408, 409, 429 ].include?(error.status) || (500..599).cover?(error.status.to_i)
    end

    def code(error)
      return :provider_timeout if error.kind == :timeout
      return :provider_auth_error if [ 401, 403 ].include?(error.status)
      return :rate_limited if error.status == 429

      :provider_unavailable
    end

    def delay(error, retry_index:)
      header_delay = retry_after_seconds(error.retry_after)
      return header_delay if header_delay

      sample = @random.rand
      raise ArgumentError, "Invalid jitter sample" unless finite_number?(sample) && (0.0..1.0).cover?(sample)

      [ @base_delay * 2**retry_index, @backoff_cap ].min * (0.5 + sample * 0.5)
    end

    private

    def finite_number?(value)
      value.is_a?(Numeric) && value.real? && value.finite?
    end

    def retry_after_seconds(value)
      return value if finite_number?(value) && value.positive?
      return unless value.is_a?(String)

      seconds = if value.match?(/\A(?:\d+(?:\.\d+)?|\.\d+)\z/)
        return unless value.match?(/[1-9]/)
        # A valid oversized decimal must block retries, not fall back to a
        # shorter delay. The runner rejects this bound without sleeping.
        return Float::INFINITY if value.bytesize > 128

        Float(value)
      else
        return if value.bytesize > 128

        Time.httpdate(value) - @wall_clock.call
      end
      seconds if finite_number?(seconds) && seconds.positive?
    rescue ArgumentError, TypeError, RangeError
      nil
    end
  end
end
