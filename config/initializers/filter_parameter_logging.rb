Rails.application.config.filter_parameters += [
  :passw, :secret, :token, :api_key, :authorization, :http_authorization,
  :prompt, :ticket_text, :completion, :summary
]
