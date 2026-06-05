# frozen_string_literal: true

WebAuthn.configure do |config|
  origin                 = (ENV['WEBAUTHN_ORIGIN'] || 'http://localhost:3003').chomp('/')
  config.allowed_origins = [origin]
  config.rp_id           = URI.parse(origin).host
  config.rp_name         = 'Casa Tâmplarului'
end
