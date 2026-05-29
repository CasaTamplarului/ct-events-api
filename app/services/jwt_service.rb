# frozen_string_literal: true

class JwtService
  ALGORITHM = 'HS256'
  EXPIRY = 30.days

  def self.encode(user_id)
    payload = { user_id: user_id, typ: 'session', exp: EXPIRY.from_now.to_i }
    JWT.encode(payload, secret, ALGORITHM)
  end

  def self.decode(token)
    decoded = JWT.decode(token, secret, true, { algorithm: ALGORITHM }).first
    raise JWT::DecodeError, 'Invalid token type' unless decoded['typ'] == 'session'

    decoded['user_id']
  end

  def self.secret
    Rails.application.credentials.dig(:auth, :jwt_secret)
  end
  private_class_method :secret
end
