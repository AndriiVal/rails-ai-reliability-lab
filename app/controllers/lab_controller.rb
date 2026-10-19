class LabController < ApplicationController
  include LabAuthentication
  skip_before_action :authenticate
  prepend_before_action :authenticate
  before_action { response.headers["Cache-Control"] = "no-store" }

  DEFAULT_TICKET = "Synthetic ticket: I was charged twice for an invented subscription and cannot sign in.".freeze

  def index
    @ticket_text = DEFAULT_TICKET
    @scenario = "success"
    load_history
  end

  def run
    @request_id = SecureRandom.uuid
    @ticket_text = params[:ticket_text]
    @scenario = params[:scenario]
    unless !@invalid_form && (request.request_parameters.keys - %w[ticket_text scenario authenticity_token commit]).empty?
      raise TicketClassifier::Error.new(:invalid_input)
    end
    # Trusted workflow: never consult global real-provider configuration.
    classifier = TicketClassifier.new(configuration: { provider: "fake", enable_real_llm: false }, provider: Providers::Fake.new)
    @outcome = ClassificationWorkflow.new(classifier: classifier).call(request_id: @request_id,
      ticket_text: @ticket_text, scenario: @scenario)
    @http_status = 200
    load_history
    render :index
  rescue TicketClassifier::Error => error
    @error_code, @attempt_count, @latency_ms = error.code, error.attempt_count, error.latency_ms
    @http_status = Api::V1::ClassificationsController::ERRORS.fetch(error.code).first
    load_history
    render :index, status: @http_status
  rescue StandardError => error
    Rails.logger.error("Lab failure #{error.class.name} request_id=#{@request_id}")
    @error_code, @http_status = :internal_error, 500
    load_history
    render :index, status: :internal_server_error
  end

  private

  def process_action(*)
    # Prevent arbitrary form values from entering Rails request logs. Keep the
    # bounded parsed fields available to the real CSRF verifier and action.
    request.set_header("action_dispatch.parameter_filter", [ /.*/ ])
    if request.post?
      values = bounded_form
      request.set_header("action_dispatch.request.request_parameters", values)
    end
    super
  rescue ActionController::InvalidAuthenticityToken
    render plain: "Invalid authenticity token. Reload the dashboard and try again.", status: :unprocessable_content
  end

  def bounded_form
    request.body.rewind
    body = request.body.read(65_537).to_s
    @invalid_form = body.bytesize > 65_536 || request.media_type != "application/x-www-form-urlencoded"
    @invalid_form ? {} : Rack::Utils.parse_nested_query(body)
  rescue Rack::QueryParser::ParameterTypeError, Rack::QueryParser::InvalidParameterError, Rack::QueryParser::ParamsTooDeepError
    @invalid_form = true
    {}
  end

  def load_history
    @recent_runs = LlmRun.recent_simulated.to_a
  rescue ActiveRecord::ActiveRecordError
    @recent_runs = []
    @history_unavailable = true
  end
end
