module Reliability
  class Runner
    class Failure < StandardError
      attr_reader :code, :attempt_count, :latency_ms, :retryable

      def initialize(code:, attempt_count:, latency_ms:, retryable:)
        @code, @attempt_count, @latency_ms, @retryable = code, attempt_count, latency_ms, retryable
        super(code.to_s)
      end
    end

    def initialize(policy: RetryPolicy.new, clock: Clock, sleeper: Sleeper)
      @policy, @clock, @sleeper = policy, clock, sleeper
    end

    def call(provider:, ticket_text:, scenario:)
      started = @clock.call
      deadline = started + @policy.overall_timeout
      attempts = 0
      loop do
        now = @clock.call
        fail_with(:provider_timeout, attempts, started, true) if now >= deadline
        timeout = [ @policy.per_attempt_timeout, deadline - now ].min
        attempt_deadline = now + timeout
        attempts += 1
        begin
          output = provider.classify(ticket_text: ticket_text, scenario: scenario, attempt: attempts, timeout_seconds: timeout)
          raise Providers::TransportTimeout if @clock.call >= attempt_deadline

          result = ClassificationValidator.call(output)
          fail_with(:provider_timeout, attempts, started, true) if @clock.call >= deadline
          return { result: result, attempt_count: attempts, latency_ms: elapsed_ms(started) }
        rescue ClassificationValidator::InvalidOutput
          code = @clock.call >= deadline ? :provider_timeout : :invalid_provider_output
          fail_with(code, attempts, started, code == :provider_timeout)
        rescue Providers::Error => error
          fail_with(:provider_timeout, attempts, started, true) if @clock.call >= deadline
          retryable = @policy.retryable?(error)
          unless retryable && attempts < @policy.max_attempts
            fail_with(@policy.code(error), attempts, started, retryable)
          end
          delay = @policy.delay(error, retry_index: attempts - 1)
          now = @clock.call
          fail_with(:provider_timeout, attempts, started, true) if now >= deadline
          fail_with(@policy.code(error), attempts, started, retryable) if delay >= deadline - now
          wait_until(now + delay, attempts, started)
        end
      end
    end

    private

    def wait_until(target, attempts, started)
      while (remaining = target - @clock.call).positive?
        before = @clock.call
        @sleeper.call(remaining)
        # A broken injected sleeper must not create an infinite busy loop.
        fail_with(:provider_timeout, attempts, started, true) if @clock.call <= before
      end
    end

    def elapsed_ms(started)
      ((@clock.call - started) * 1000).round
    end

    def fail_with(code, attempts, started, retryable)
      raise Failure.new(code: code, attempt_count: attempts, latency_ms: elapsed_ms(started), retryable: retryable)
    end
  end
end
