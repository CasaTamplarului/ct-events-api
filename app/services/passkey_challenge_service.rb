# frozen_string_literal: true

class PasskeyChallengeService
  class InvalidTokenError < StandardError; end

  PURPOSE_REGISTER     = 'passkey_registration'
  PURPOSE_AUTHENTICATE = 'passkey_authentication'
  EXPIRY = 5.minutes

  def self.encode(challenge:, purpose:, user_id: nil)
    payload = {
      'challenge' => challenge,
      'purpose' => purpose,
      'user_id' => user_id,
      'exp' => EXPIRY.from_now.to_i
    }
    JWT.encode(payload, secret, 'HS256')
  end

  def self.decode(token, expected_purpose:)
    payload = JWT.decode(token, secret, true, { algorithm: 'HS256' }).first
    raise InvalidTokenError, 'Wrong purpose' unless payload['purpose'] == expected_purpose

    payload
  rescue JWT::DecodeError => e
    raise InvalidTokenError, e.message
  end

  class << self
    private

      def secret
        Rails.application.credentials.dig(:auth, :jwt_secret)
      end
  end
end
