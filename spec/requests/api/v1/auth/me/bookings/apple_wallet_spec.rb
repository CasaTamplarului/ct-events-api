# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/auth/me/bookings/:order_reference/wallet/apple' do
  let(:private_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:user)       { create(:user) }
  let(:token)      { JwtService.encode(user.id) }
  let(:headers)    { auth_headers(token) }
  let(:event)      { create(:event, start_date: 1.week.from_now) }
  let(:order_user) { user }
  let(:order)      { create(:order, user: order_user) }
  let!(:attendee)  { create(:attendee, order: order, event: event, user: user, payment_status: :paid) }
  let(:certificate_pem) do
    cert = OpenSSL::X509::Certificate.new
    cert.subject = OpenSSL::X509::Name.parse('CN=test')
    cert.issuer = OpenSSL::X509::Name.parse('CN=test')
    cert.not_before = Time.now
    cert.not_after = Time.now + (365 * 24 * 60 * 60)
    cert.serial = 1
    cert.public_key = private_key.public_key
    cert.sign(private_key, OpenSSL::Digest.new('SHA256'))
    cert.to_pem
  end

  before do
    Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }

    @orig_pass_type = ENV['APPLE_WALLET_PASS_TYPE_ID']
    @orig_team      = ENV['APPLE_WALLET_TEAM_ID']
    @orig_cert      = ENV['APPLE_WALLET_CERTIFICATE']
    @orig_key       = ENV['APPLE_WALLET_PRIVATE_KEY']

    ENV['APPLE_WALLET_PASS_TYPE_ID']   = 'pass.com.example.event'
    ENV['APPLE_WALLET_TEAM_ID']        = 'ABC123XYZ'
    ENV['APPLE_WALLET_CERTIFICATE']    = Base64.strict_encode64(certificate_pem)
    ENV['APPLE_WALLET_PRIVATE_KEY']    = Base64.strict_encode64(private_key.to_pem)

    allow_any_instance_of(AppleWalletService).to receive(:pass_data).and_return('FAKE_PKPASS_DATA')
  end

  after do
    ENV['APPLE_WALLET_PASS_TYPE_ID']   = @orig_pass_type
    ENV['APPLE_WALLET_TEAM_ID']        = @orig_team
    ENV['APPLE_WALLET_CERTIFICATE']    = @orig_cert
    ENV['APPLE_WALLET_PRIVATE_KEY']    = @orig_key
  end

  context 'when the user owns the order' do
    it 'returns 200 with application/vnd.apple.pkpass content type' do
      get "/api/v1/auth/me/bookings/#{order.order_reference}/wallet/apple", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('application/vnd.apple.pkpass')
      expect(response.body).to eq('FAKE_PKPASS_DATA')
    end
  end

  context 'when the user is an attendee but not the order owner' do
    let(:order_user) { create(:user) }

    it 'returns 200 with pkpass content type' do
      get "/api/v1/auth/me/bookings/#{order.order_reference}/wallet/apple", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('application/vnd.apple.pkpass')
    end
  end

  context 'when no authentication token is provided' do
    it 'returns 401' do
      get "/api/v1/auth/me/bookings/#{order.order_reference}/wallet/apple"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'when the order reference does not exist' do
    it 'returns 404' do
      get '/api/v1/auth/me/bookings/CT-2026-XXXXXX/wallet/apple', headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when the user has no access to the order' do
    it 'returns 404' do
      other_user  = create(:user)
      other_order = create(:order, user: other_user)
      create(:attendee, order: other_order, event: event, user: other_user, payment_status: :paid)
      get "/api/v1/auth/me/bookings/#{other_order.order_reference}/wallet/apple", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end

RSpec.describe 'GET /api/v1/auth/me/bookings/:order_reference/attendees/:id/wallet/apple' do
  let(:private_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:user)      { create(:user) }
  let(:token)     { JwtService.encode(user.id) }
  let(:headers)   { auth_headers(token) }
  let(:event)     { create(:event, start_date: 1.week.from_now) }
  let(:order)     { create(:order) }
  let!(:attendee) { create(:attendee, order: order, event: event, user: user, payment_status: :paid) }
  let(:certificate_pem) do
    cert = OpenSSL::X509::Certificate.new
    cert.subject = OpenSSL::X509::Name.parse('CN=test')
    cert.issuer = OpenSSL::X509::Name.parse('CN=test')
    cert.not_before = Time.now
    cert.not_after = Time.now + (365 * 24 * 60 * 60)
    cert.serial = 1
    cert.public_key = private_key.public_key
    cert.sign(private_key, OpenSSL::Digest.new('SHA256'))
    cert.to_pem
  end

  before do
    Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }

    @orig_pass_type = ENV['APPLE_WALLET_PASS_TYPE_ID']
    @orig_team      = ENV['APPLE_WALLET_TEAM_ID']
    @orig_cert      = ENV['APPLE_WALLET_CERTIFICATE']
    @orig_key       = ENV['APPLE_WALLET_PRIVATE_KEY']

    ENV['APPLE_WALLET_PASS_TYPE_ID']   = 'pass.com.example.event'
    ENV['APPLE_WALLET_TEAM_ID']        = 'ABC123XYZ'
    ENV['APPLE_WALLET_CERTIFICATE']    = Base64.strict_encode64(certificate_pem)
    ENV['APPLE_WALLET_PRIVATE_KEY']    = Base64.strict_encode64(private_key.to_pem)

    allow_any_instance_of(AppleWalletService).to receive(:pass_data).and_return('FAKE_PKPASS_DATA')
  end

  after do
    ENV['APPLE_WALLET_PASS_TYPE_ID']   = @orig_pass_type
    ENV['APPLE_WALLET_TEAM_ID']        = @orig_team
    ENV['APPLE_WALLET_CERTIFICATE']    = @orig_cert
    ENV['APPLE_WALLET_PRIVATE_KEY']    = @orig_key
  end

  def path
    "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{attendee.id}/wallet/apple"
  end

  context 'when the attendee belongs to the current user' do
    it 'returns 200 with pkpass content type' do
      get path, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('application/vnd.apple.pkpass')
      expect(response.body).to eq('FAKE_PKPASS_DATA')
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
      get "/api/v1/auth/me/bookings/CT-2026-XXXXXX/attendees/#{attendee.id}/wallet/apple",
          headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when the attendee does not belong to the current user' do
    it 'returns 404' do
      other_user     = create(:user)
      other_attendee = create(:attendee, order: order, event: event, user: other_user, payment_status: :paid)
      get "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{other_attendee.id}/wallet/apple",
          headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when the attendee id does not exist in this order' do
    it 'returns 404' do
      get "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/0/wallet/apple",
          headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
