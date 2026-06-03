# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/auth/me/bookings/:order_reference/wallet/google' do
  before do
    Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }
    stub_request(:post, 'https://www.googleapis.com/oauth2/v4/token')
      .to_return(
        status: 200,
        body: { access_token: 'fake-token', token_type: 'Bearer', expires_in: 3600 }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    stub_request(:post, /walletobjects\.googleapis\.com/)
      .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
  end

  let(:user)       { create(:user) }
  let(:token)      { JwtService.encode(user.id) }
  let(:headers)    { auth_headers(token) }
  let(:event)      { create(:event, slug: 'test-event', start_date: 1.week.from_now, end_date: 1.week.from_now + 3.hours) }
  let(:order_user) { user }
  let(:order)      { create(:order, user: order_user) }
  let!(:attendee)  { create(:attendee, order: order, event: event, user: user, payment_status: :paid) }

  let(:private_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:sa_json) do
    {
      type: 'service_account',
      client_email: 'wallet@test.iam.gserviceaccount.com',
      private_key: private_key.to_pem,
      private_key_id: 'key-id-123',
      token_uri: 'https://oauth2.googleapis.com/token'
    }.to_json
  end

  around do |example|
    orig_issuer = ENV['GOOGLE_WALLET_ISSUER_ID']
    orig_sa     = ENV['GOOGLE_WALLET_SERVICE_ACCOUNT_JSON']
    ENV['GOOGLE_WALLET_ISSUER_ID']            = '1234567890'
    ENV['GOOGLE_WALLET_SERVICE_ACCOUNT_JSON'] = sa_json
    example.run
  ensure
    ENV['GOOGLE_WALLET_ISSUER_ID']            = orig_issuer
    ENV['GOOGLE_WALLET_SERVICE_ACCOUNT_JSON'] = orig_sa
  end

  context 'when the user owns the order' do
    it 'returns 200 with a Google Wallet URL' do
      get "/api/v1/auth/me/bookings/#{order.order_reference}/wallet/google", headers: headers
      expect(response).to have_http_status(:ok)
      expect(json['url']).to start_with('https://pay.google.com/gp/v/save/')
    end
  end

  context 'when the user is an attendee but not the order owner' do
    let(:order_user) { create(:user) }

    it 'returns 200 with a Google Wallet URL' do
      get "/api/v1/auth/me/bookings/#{order.order_reference}/wallet/google", headers: headers
      expect(response).to have_http_status(:ok)
      expect(json['url']).to start_with('https://pay.google.com/gp/v/save/')
    end
  end

  context 'when no authentication token is provided' do
    it 'returns 401' do
      get "/api/v1/auth/me/bookings/#{order.order_reference}/wallet/google"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'when the order reference does not exist' do
    it 'returns 404' do
      get '/api/v1/auth/me/bookings/CT-2026-XXXXXX/wallet/google', headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when the user has no access to the order' do
    it 'returns 404' do
      other_user  = create(:user)
      other_order = create(:order, user: other_user)
      create(:attendee, order: other_order, event: event, user: other_user, payment_status: :paid)
      get "/api/v1/auth/me/bookings/#{other_order.order_reference}/wallet/google", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end

RSpec.describe 'GET /api/v1/auth/me/bookings/:order_reference/attendees/:id/wallet/google' do
  before do
    Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }
    stub_request(:post, 'https://www.googleapis.com/oauth2/v4/token')
      .to_return(
        status: 200,
        body: { access_token: 'fake-token', token_type: 'Bearer', expires_in: 3600 }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    stub_request(:post, /walletobjects\.googleapis\.com/)
      .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
  end

  let(:user)      { create(:user) }
  let(:token)     { JwtService.encode(user.id) }
  let(:headers)   { auth_headers(token) }
  let(:event)     { create(:event, slug: 'test-event', start_date: 1.week.from_now, end_date: 1.week.from_now + 3.hours) }
  let(:order)     { create(:order) }
  let!(:attendee) { create(:attendee, order: order, event: event, user: user, payment_status: :paid) }

  let(:private_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:sa_json) do
    {
      type: 'service_account',
      client_email: 'wallet@test.iam.gserviceaccount.com',
      private_key: private_key.to_pem,
      private_key_id: 'key-id-123',
      token_uri: 'https://oauth2.googleapis.com/token'
    }.to_json
  end

  around do |example|
    orig_issuer = ENV['GOOGLE_WALLET_ISSUER_ID']
    orig_sa     = ENV['GOOGLE_WALLET_SERVICE_ACCOUNT_JSON']
    ENV['GOOGLE_WALLET_ISSUER_ID']            = '1234567890'
    ENV['GOOGLE_WALLET_SERVICE_ACCOUNT_JSON'] = sa_json
    example.run
  ensure
    ENV['GOOGLE_WALLET_ISSUER_ID']            = orig_issuer
    ENV['GOOGLE_WALLET_SERVICE_ACCOUNT_JSON'] = orig_sa
  end

  def path
    "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{attendee.id}/wallet/google"
  end

  context 'when the attendee belongs to the current user' do
    it 'returns 200 with a Google Wallet URL' do
      get path, headers: headers
      expect(response).to have_http_status(:ok)
      expect(json['url']).to start_with('https://pay.google.com/gp/v/save/')
    end
  end

  context 'when no authentication token is provided' do
    it 'returns 401' do
      get path
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'when the order reference does not exist' do
    it 'returns 404' do
      get "/api/v1/auth/me/bookings/CT-2026-XXXXXX/attendees/#{attendee.id}/wallet/google",
          headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when the attendee does not belong to the current user' do
    it 'returns 404' do
      other_user     = create(:user)
      other_attendee = create(:attendee, order: order, event: event, user: other_user, payment_status: :paid)
      get "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{other_attendee.id}/wallet/google",
          headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when the attendee id does not exist in this order' do
    it 'returns 404' do
      get "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/0/wallet/google",
          headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
