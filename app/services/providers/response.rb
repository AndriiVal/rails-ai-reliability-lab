module Providers
  Response = Data.define(:body, :model, :input_tokens, :output_tokens, :provider_request_id) do
    def initialize(body:, model:, input_tokens: nil, output_tokens: nil, provider_request_id: nil)
      super(body: body.freeze, model: model.freeze, input_tokens: input_tokens,
        output_tokens: output_tokens, provider_request_id: provider_request_id&.freeze)
    end
  end
end
