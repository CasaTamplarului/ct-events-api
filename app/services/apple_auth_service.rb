# frozen_string_literal: true

require 'net/http'
require 'json'

class AppleAuthService
  class InvalidTokenError < StandardError; end

  JWKS_URI = 'https://appleid.apple.com/auth/keys'
  ISSUER   = 'https://appleid.apple.com'
  JWKS_TTL = 1.hour

  @jwks_cache      = nil
  @jwks_fetched_at = nil

  def self.call(id_token)
    bundle_ids = Rails.application.credentials.dig(:auth, :apple_bundle_ids)
    raise InvalidTokenError, 'Apple credentials not configured' if bundle_ids.blank?

    payload = decode_token(id_token, bundle_ids)
    email = payload['email']
    raise InvalidTokenError, 'Email claim missing from Apple token' if email.blank?
    raise InvalidTokenError, 'Email not verified' unless [true, 'true'].include?(payload['email_verified'])

    {
      uid: payload['sub'],
      email: email,
      first_name: derive_first_name(email),
      last_name: nil,
      avatar_url: nil
    }
  rescue JWT::DecodeError => e
    raise InvalidTokenError, e.message
  end

  class << self
    private

      def decode_token(id_token, bundle_ids, retry_on_stale_key: true)
        JWT.decode(id_token, nil, true, {
                     algorithms: ['RS256'],
                     jwks: fetch_jwks,
                     iss: ISSUER,
                     verify_iss: true,
                     aud: bundle_ids,
                     verify_aud: true
                   }).first
      rescue JWT::DecodeError => e
        if retry_on_stale_key && e.message.include?('Could not find public key')
          @jwks_fetched_at = nil
          decode_token(id_token, bundle_ids, retry_on_stale_key: false)
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

      def derive_first_name(email)
        return 'Apple' if email.end_with?('@privaterelay.appleid.com')

        email.split('@').first.to_s
      end
  end
end
