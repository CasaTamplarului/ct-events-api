# frozen_string_literal: true

WebAuthn.configure do |config|
  origin = (ENV['WEBAUTHN_ORIGIN'] || 'http://localhost:3003').chomp('/')

  # Native Android passkeys sign with an apk-key-hash origin instead of the
  # web origin (iOS uses the web origin). Comma-separated env override for
  # extra signing certs (e.g. the release keystore); the default is the
  # Android debug keystore used for development builds.
  android_origins = ENV.fetch(
    'WEBAUTHN_ANDROID_ORIGINS',
    'android:apk-key-hash:GuoWiZMydUPUGYUrATRZpd2k7kYUtWW7Cc7_ZrLyKcM'
  ).split(',').map(&:strip).reject(&:empty?)

  config.allowed_origins = [origin] + android_origins
  config.rp_id           = URI.parse(origin).host
  config.rp_name         = 'Casa Tâmplarului'
end
