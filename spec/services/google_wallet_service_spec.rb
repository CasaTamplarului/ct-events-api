# frozen_string_literal: true

require 'rails_helper'
require 'cgi'

RSpec.describe GoogleWalletService do
  let(:private_key) { OpenSSL::PKey::RSA.generate(1024) }
  let(:sa_json) do
    {
      type: 'service_account',
      client_email: 'wallet@test.iam.gserviceaccount.com',
      private_key: private_key.to_pem,
      private_key_id: 'key-id-123',
      token_uri: 'https://oauth2.googleapis.com/token'
    }.to_json
  end
  let(:issuer_id) { '1234567890' }

  let!(:language) { Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' } }

  let(:event) do
    create(:event,
           slug: 'midsummer-gala',
           location_name: 'Casa Tâmplarului',
           start_date: 2.weeks.from_now,
           end_date: 2.weeks.from_now + 4.hours)
  end
  let!(:translation) { create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Gala de Vară') }
  let(:order)        { create(:order) }
  let!(:attendee)    { create(:attendee, order: order, event: event, payment_status: :paid) }

  let(:class_id)         { "#{issuer_id}.#{event.slug.gsub(/[^a-zA-Z0-9_]/, '_')}" }
  let(:ticket_object_id) { "#{issuer_id}.#{order.order_reference.gsub(/[^a-zA-Z0-9_]/, '_')}" }

  around do |example|
    orig_issuer = ENV['GOOGLE_WALLET_ISSUER_ID']
    orig_sa     = ENV['GOOGLE_WALLET_SERVICE_ACCOUNT_JSON']
    ENV['GOOGLE_WALLET_ISSUER_ID']            = issuer_id
    ENV['GOOGLE_WALLET_SERVICE_ACCOUNT_JSON'] = sa_json
    example.run
  ensure
    ENV['GOOGLE_WALLET_ISSUER_ID']            = orig_issuer
    ENV['GOOGLE_WALLET_SERVICE_ACCOUNT_JSON'] = orig_sa
  end

  before do
    stub_request(:post, 'https://oauth2.googleapis.com/token')
      .to_return(
        status: 200,
        body: { access_token: 'fake-token', token_type: 'Bearer', expires_in: 3600 }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    stub_request(:post, 'https://www.googleapis.com/oauth2/v4/token')
      .to_return(
        status: 200,
        body: { access_token: 'fake-token', token_type: 'Bearer', expires_in: 3600 }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  subject(:service) { described_class.new(order: order, language: 'ro-RO') }

  # ── Initialization ──────────────────────────────────────────────────────────

  describe 'initialization' do
    context 'when GOOGLE_WALLET_ISSUER_ID is not set' do
      around do |example|
        ENV.delete('GOOGLE_WALLET_ISSUER_ID')
        example.run
      ensure
        ENV['GOOGLE_WALLET_ISSUER_ID'] = issuer_id
      end

      it 'raises ArgumentError' do
        expect { described_class.new(order: order, language: 'ro-RO') }
          .to raise_error(ArgumentError, /GOOGLE_WALLET_ISSUER_ID/)
      end
    end

    context 'when GOOGLE_WALLET_SERVICE_ACCOUNT_JSON is not set' do
      around do |example|
        ENV.delete('GOOGLE_WALLET_SERVICE_ACCOUNT_JSON')
        example.run
      ensure
        ENV['GOOGLE_WALLET_SERVICE_ACCOUNT_JSON'] = sa_json
      end

      it 'raises ArgumentError' do
        expect { described_class.new(order: order, language: 'ro-RO') }
          .to raise_error(ArgumentError, /GOOGLE_WALLET_SERVICE_ACCOUNT_JSON/)
      end
    end
  end

  # ── #save_url ────────────────────────────────────────────────────────────────

  describe '#save_url' do
    before do
      stub_request(:post, 'https://walletobjects.googleapis.com/walletobjects/v1/eventTicketClass')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, 'https://walletobjects.googleapis.com/walletobjects/v1/eventTicketObject')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
    end

    it 'returns a Google Wallet save URL' do
      expect(service.save_url).to start_with('https://pay.google.com/gp/v/save/')
    end

    it 'sends the class request with the correct event data' do
      expected_class_id = class_id
      service.save_url
      expect(WebMock).to have_requested(:post,
                                        'https://walletobjects.googleapis.com/walletobjects/v1/eventTicketClass')
        .with { |req|
          body = JSON.parse(req.body)
          body['id'] == expected_class_id &&
            body.dig('eventName', 'defaultValue', 'value') == 'Gala de Vară' &&
            body.dig('venue', 'name', 'defaultValue', 'value') == 'Casa Tâmplarului' &&
            body.dig('dateTime', 'start').is_a?(String) &&
            !body.dig('dateTime', 'start').nil? &&
            body.dig('dateTime', 'end').is_a?(String) &&
            !body.dig('dateTime', 'end').nil?
        }
    end

    it 'sends the object request with the correct order data' do
      expected_class_id    = class_id
      expected_object_id   = ticket_object_id
      expected_order_ref   = order.order_reference
      service.save_url
      expect(WebMock).to have_requested(:post,
                                        'https://walletobjects.googleapis.com/walletobjects/v1/eventTicketObject')
        .with { |req|
          body = JSON.parse(req.body)
          body['id'] == expected_object_id &&
            body['classId'] == expected_class_id &&
            body['state'] == 'ACTIVE' &&
            body.dig('barcode', 'type') == 'QR_CODE' &&
            body.dig('barcode', 'value') == expected_order_ref
        }
    end

    context 'when the class already exists (409)' do
      before do
        stub_request(:post, 'https://walletobjects.googleapis.com/walletobjects/v1/eventTicketClass')
          .to_return(status: 409, body: '{}', headers: { 'Content-Type' => 'application/json' })
        stub_request(:put, "https://walletobjects.googleapis.com/walletobjects/v1/eventTicketClass/#{class_id}")
          .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
      end

      it 'falls back to PUT and still returns a URL' do
        expected_class_id = class_id
        expect(service.save_url).to start_with('https://pay.google.com/gp/v/save/')
        expect(WebMock).to have_requested(:put,
                                          "https://walletobjects.googleapis.com/walletobjects/v1/eventTicketClass/#{expected_class_id}")
      end
    end

    context 'when the object already exists (409)' do
      before do
        stub_request(:post, 'https://walletobjects.googleapis.com/walletobjects/v1/eventTicketObject')
          .to_return(status: 409, body: '{}', headers: { 'Content-Type' => 'application/json' })
        stub_request(:put, "https://walletobjects.googleapis.com/walletobjects/v1/eventTicketObject/#{ticket_object_id}")
          .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
      end

      it 'falls back to PUT and still returns a URL' do
        expected_object_id = ticket_object_id
        expect(service.save_url).to start_with('https://pay.google.com/gp/v/save/')
        expect(WebMock).to have_requested(:put,
                                          "https://walletobjects.googleapis.com/walletobjects/v1/eventTicketObject/#{expected_object_id}")
      end
    end

    context 'when the wallet API returns a server error' do
      before do
        stub_request(:post, 'https://walletobjects.googleapis.com/walletobjects/v1/eventTicketClass')
          .to_return(status: 500, body: '{"error":"internal"}')
      end

      it 'raises ApiError' do
        expect { service.save_url }.to raise_error(GoogleWalletService::ApiError)
      end
    end

    it 'returns a JWT with the correct payload' do
      url = service.save_url
      token = url.split('/').last
      # Decode without verification first to get the header
      header = JWT.decode(token, nil, false).last
      expect(header['alg']).to eq('RS256')
      # Decode with public key verification
      decoded = JWT.decode(token, private_key.public_key, true, algorithms: ['RS256']).first
      expect(decoded['aud']).to eq('google')
      expect(decoded['typ']).to eq('savetowallet')
      expect(decoded.dig('payload', 'eventTicketObjects', 0, 'id')).to eq(ticket_object_id)
    end
  end
end
