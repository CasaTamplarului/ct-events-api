# frozen_string_literal: true

require 'net/http'
require 'json'

class MicrosoftAuthService
  class InvalidTokenError < StandardError; end

  JWKS_URI = 'https://login.microsoftonline.com/consumers/discovery/v2.0/keys'
  ISSUER   = 'https://login.microsoftonline.com/9188040d-6c67-4c5b-b112-36a304b66dad/v2.0'
  JWKS_TTL = 1.hour

  @jwks_cache      = nil
  @jwks_fetched_at = nil

  def self.call(id_token)
    client_id = Rails.application.credentials.dig(:auth, :microsoft_client_id)
    raise InvalidTokenError, 'Microsoft credentials not configured' if client_id.blank?

    payload = decode_token(id_token, client_id)
    email = payload['email']
    raise InvalidTokenError, 'Email claim missing from Microsoft token' if email.blank?

    {
      uid: payload['sub'],
      email: email,
      first_name: payload['given_name'].to_s,
      last_name: payload['family_name'].to_s,
      avatar_url: nil
    }
  rescue JWT::DecodeError => e
    raise InvalidTokenError, e.message
  end

  class << self
    private

      def decode_token(id_token, client_id, retry_on_stale_key: true)
        JWT.decode(id_token, nil, true, {
                     algorithms: ['RS256'],
                     jwks: fetch_jwks,
                     iss: ISSUER,
                     verify_iss: true,
                     aud: client_id,
                     verify_aud: true
                   }).first
      rescue JWT::DecodeError => e
        if retry_on_stale_key && e.message.include?('Could not find public key')
          @jwks_fetched_at = nil
          decode_token(id_token, client_id, retry_on_stale_key: false)
        else
          raise
        end
      end

      def fetch_jwks
        if @jwks_cache.nil? || @jwks_fetched_at.nil? ||
           Time.current - @jwks_fetched_at > JWKS_TTL
          refresh_jwks!
        end
        @jwks_cache
      end

      def refresh_jwks!
        response = Net::HTTP.get_response(URI(JWKS_URI))
        raise InvalidTokenError, "JWKS fetch failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        @jwks_cache = JWT::JWK::Set.new(JSON.parse(response.body))
        @jwks_fetched_at = Time.current
        @jwks_cache
      rescue JSON::ParserError, ArgumentError => e
        raise InvalidTokenError, "Invalid JWKS response: #{e.message}"
      rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT,
             Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
        raise InvalidTokenError, "Network error fetching JWKS: #{e.message}"
      end
  end
end
