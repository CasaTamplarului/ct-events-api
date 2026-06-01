# frozen_string_literal: true

require 'googleauth'
require 'net/http'

class GoogleWalletService
  class ApiError < StandardError; end

  WALLET_API_BASE = 'https://walletobjects.googleapis.com/walletobjects/v1'
  SCOPES = ['https://www.googleapis.com/auth/wallet_object.issuer'].freeze

  def initialize(order:, language:)
    @order     = order
    @language  = language
    @issuer_id = ENV.fetch('GOOGLE_WALLET_ISSUER_ID') { raise ArgumentError, 'GOOGLE_WALLET_ISSUER_ID is not set' }
    sa_json = ENV.fetch('GOOGLE_WALLET_SERVICE_ACCOUNT_JSON') do
      raise ArgumentError, 'GOOGLE_WALLET_SERVICE_ACCOUNT_JSON is not set'
    end
    parsed = JSON.parse(sa_json)
    @service_account_email = parsed['client_email']
    @private_key = OpenSSL::PKey::RSA.new(parsed['private_key'])
    @credentials = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(sa_json),
      scope: SCOPES
    )
  end

  def save_url
    upsert_class
    upsert_object
    "https://pay.google.com/gp/v/save/#{signed_jwt}"
  end

  private

    def event
      @event ||= begin
        att = @order.attendees.includes(event: :events_translations).first
        raise ApiError, 'Order has no attendees' unless att

        att.event
      end
    end

    def event_name
      translations = event.events_translations
      (translations.find { |t| t.languages_code == @language } ||
       translations.find { |t| t.languages_code == 'ro-RO' })&.name.to_s
    end

    def class_id
      "#{@issuer_id}.#{sanitize_id(event.slug)}"
    end

    def wallet_object_id
      "#{@issuer_id}.#{sanitize_id(@order.order_reference)}"
    end

    def sanitize_id(str)
      str.gsub(/[^a-zA-Z0-9_]/, '_')
    end

    def access_token
      @access_token ||= @credentials.fetch_access_token!['access_token']
    end

    def upsert_class
      body = {
        id: class_id,
        issuerName: 'Casa Tâmplarului',
        reviewStatus: 'UNDER_REVIEW',
        eventName: { defaultValue: { language: 'ro', value: event_name } },
        venue: {
          name: { defaultValue: { language: 'ro', value: event.location_name.to_s } },
          address: { defaultValue: { language: 'ro', value: event.address.to_s } }
        },
        dateTime: { start: event.start_date.iso8601 }
      }
      body[:dateTime][:end] = event.end_date.iso8601 if event.end_date
      upsert_resource('eventTicketClass', class_id, body)
    end

    def upsert_object
      body = {
        id: wallet_object_id,
        classId: class_id,
        state: 'ACTIVE',
        barcode: { type: 'QR_CODE', value: @order.order_reference }
      }
      upsert_resource('eventTicketObject', wallet_object_id, body)
    end

    def upsert_resource(collection, id, body)
      token = access_token
      post_response = wallet_request(:post, collection, body, token)
      return if post_response.code.to_i.between?(200, 299)

      if post_response.code == '409'
        put_response = wallet_request(:put, "#{collection}/#{id}", body, token)
        unless put_response.code.to_i.between?(200, 299)
          raise ApiError, "PUT to #{collection}/#{id} failed with status #{put_response.code}"
        end

        return
      end

      raise ApiError, "POST to #{collection} failed with status #{post_response.code}"
    end

    def wallet_request(method, path, body, token)
      uri = URI("#{WALLET_API_BASE}/#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Put.new(uri)
      request['Authorization'] = "Bearer #{token}"
      request['Content-Type']  = 'application/json'
      request.body = body.to_json
      http.request(request)
    end

    def signed_jwt
      payload = {
        iss: @service_account_email,
        aud: 'google',
        typ: 'savetowallet',
        iat: Time.now.to_i,
        payload: { eventTicketObjects: [{ id: wallet_object_id }] }
      }
      JWT.encode(payload, @private_key, 'RS256')
    end
end
