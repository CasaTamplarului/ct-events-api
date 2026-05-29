# frozen_string_literal: true

require 'net/http'
require 'json'

class FacebookAuthService
  class InvalidTokenError < StandardError; end

  GRAPH_BASE = 'https://graph.facebook.com'

  def self.call(access_token)
    app_id     = Rails.application.credentials.dig(:auth, :facebook_app_id)
    app_secret = Rails.application.credentials.dig(:auth, :facebook_app_secret)
    raise ArgumentError, 'Facebook credentials not configured' if app_id.blank? || app_secret.blank?

    validate_token!(access_token, app_id, app_secret)
    fetch_user_data(access_token)
  end

  class << self
    private

      def validate_token!(access_token, app_id, app_secret)
        url = URI("#{GRAPH_BASE}/debug_token")
        url.query = URI.encode_www_form(
          input_token: access_token,
          access_token: "#{app_id}|#{app_secret}"
        )
        body = get_json!(url)
        data = body['data'] || {}
        raise InvalidTokenError, 'Token is invalid' unless data['is_valid'] && data['app_id'].to_s == app_id.to_s
      end

      def fetch_user_data(access_token)
        url = URI("#{GRAPH_BASE}/me")
        url.query = URI.encode_www_form(
          fields: 'id,email,first_name,last_name,picture.type(large)',
          access_token: access_token
        )
        payload = get_json!(url)

        {
          uid: payload['id'],
          email: payload['email'],
          first_name: payload['first_name'].to_s,
          last_name: payload['last_name'].to_s,
          avatar_url: payload.dig('picture', 'data', 'url')
        }
      end

      def get_json!(url)
        response = Net::HTTP.get_response(url)
        raise InvalidTokenError, "Graph API error: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise InvalidTokenError, "Invalid JSON from Graph API: #{e.message}"
      end
  end
end
