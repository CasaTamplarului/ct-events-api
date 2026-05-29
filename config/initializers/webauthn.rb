# frozen_string_literal: true

WebAuthn.configure do |config|
  config.allowed_origins = [Rails.application.credentials.dig(:webauthn, :origin) || 'http://localhost:5173']
  config.rp_name = 'Casa Tâmplarului'
end
