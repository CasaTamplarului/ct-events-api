# frozen_string_literal: true

require 'google-id-token'

class GoogleAuthService
  InvalidTokenError = Class.new(StandardError)

  def self.call(id_token)
    client_id = Rails.application.credentials.dig(:auth, :google_client_id)
    validator = GoogleIDToken::Validator.new
    payload = validator.check(id_token, client_id)

    {
      uid: payload['sub'],
      email: payload['email'],
      first_name: payload['given_name'].to_s,
      last_name: payload['family_name'].to_s,
      avatar_url: payload['picture']
    }
  rescue GoogleIDToken::ValidationError => e
    raise InvalidTokenError, e.message
  end
end
