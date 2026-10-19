module AnthropicResponse
  def anthropic_response(**overrides)
    {
      id: "msg_synthetic", type: "message", role: "assistant", model: model,
      stop_reason: "end_turn", stop_sequence: nil,
      content: [ { type: "text", text: JSON.generate(classification) } ],
      usage: { input_tokens: 120, output_tokens: 45 }
    }.merge(overrides)
  end

  def classification
    { category: "billing", priority: "high", summary: "Synthetic billing request.", requires_human_review: true }
  end

  def stub_anthropic(body = anthropic_response, status: 200, headers: {})
    stub_request(:post, "https://api.anthropic.com/v1/messages").to_return(
      status: status, body: JSON.generate(body), headers: { "content-type" => "application/json", "request-id" => "req_synthetic" }.merge(headers)
    )
  end
end
