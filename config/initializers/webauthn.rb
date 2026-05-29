# frozen_string_literal: true

WebAuthn.configure do |config|
  origin                 = Rails.application.credentials.dig(:webauthn, :origin) || 'http://localhost:5173'
  config.allowed_origins = [origin]
  config.rp_id           = URI.parse(origin).host
  config.rp_name         = 'Casa Tâmplarului'
end
