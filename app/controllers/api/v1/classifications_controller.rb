module Api
  module V1
    class ClassificationsController < ActionController::API
      include ActionController::HttpAuthentication::Basic::ControllerMethods
      include LabAuthentication

      wrap_parameters false

      MAX_BODY_BYTES = 16_384
      ERRORS = {
        invalid_input: [ 422, "Invalid classification request." ],
        unauthorized: [ 401, "Authentication required." ],
        unsupported_media_type: [ 415, "Content-Type must be application/json." ],
        invalid_provider_output: [ 502, "The provider returned an invalid classification." ],
        provider_disabled: [ 503, "The configured provider is disabled." ],
        provider_auth_error: [ 502, "The upstream provider rejected authentication." ],
        rate_limited: [ 429, "The upstream provider is temporarily rate limited." ],
        provider_unavailable: [ 503, "The upstream provider could not complete the request." ],
        provider_timeout: [ 504, "The provider request exceeded its time budget." ],
        internal_error: [ 500, "The classification request could not be completed." ]
      }.freeze

      def create
        return render_error(:unsupported_media_type) unless request.media_type == "application/json"

        payload = read_payload
        return render_error(:invalid_input) unless payload.is_a?(Hash) && (payload.keys - %w[ticket_text scenario]).empty?

        outcome = TicketClassifier.new.call(ticket_text: payload["ticket_text"], **payload.slice("scenario").symbolize_keys)
        render json: { request_id: @classification_request_id, **outcome }
      rescue TicketClassifier::Error => error
        classification_error(error)
      rescue StandardError => error
        # Rails 8.1 rescue_from instrumentation logs exception messages before
        # handlers run. Catch within the action to keep SDK payloads private.
        unexpected_error(error)
      end

      private

      # Keep Rails instrumentation from parsing/logging untrusted bodies before
      # the bounded parser below, including malformed JSON and unknown fields.
      def process_action(*)
        @classification_request_id = SecureRandom.uuid
        request.set_header("action_dispatch.request.request_parameters", {})
        super
      end

      def read_payload
        body = (request.body.read(MAX_BODY_BYTES + 1) || "").force_encoding(Encoding::UTF_8)
        return unless body.bytesize <= MAX_BODY_BYTES && body.valid_encoding?

        JSON.parse(body)
      rescue JSON::ParserError
        nil
      end

      def authentication_required
        super
        response.content_type = "application/json"
        self.response_body = JSON.generate(error_payload(:unauthorized, 0))
      end

      def classification_error(error)
        render_error(error.code, error.attempt_count, retryable: error.retryable)
      end

      def unexpected_error(error)
        Rails.logger.error("Classification failure #{error.class.name} request_id=#{@classification_request_id}")
        render_error(:internal_error)
      end

      def render_error(code, attempts = 0, retryable: false)
        render json: error_payload(code, attempts, retryable: retryable), status: ERRORS.fetch(code).first
      end

      def public_provider
        configuration = Rails.application.config.x.llm
        return "fake" if configuration[:provider] == "fake"
        LlmConfiguration.anthropic_enabled?(configuration) ? "anthropic" : "disabled"
      end

      def error_payload(code, attempts, retryable: false)
        {
          request_id: @classification_request_id,
          error: { code: code, message: ERRORS.fetch(code).last, retryable: retryable },
          meta: { provider: public_provider, attempt_count: code == :internal_error ? nil : attempts }
        }
      end
    end
  end
end
