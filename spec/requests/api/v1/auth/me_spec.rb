# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/auth/me' do
  let(:user) do
    create(:user,
           first_name: 'Ion',
           last_name: 'Popescu',
           email: 'ion@example.com',
           phone_number: '+40721000001',
           church_name: 'Betania',
           city: 'Cluj-Napoca')
  end
  let(:token) { JwtService.encode(user.id) }

  def get_me(headers: {})
    get '/api/v1/auth/me', headers: { 'Content-Type' => 'application/json' }.merge(headers)
  end

  context 'with a valid JWT' do
    it 'returns 200 with correct user data' do
      get_me(headers: { 'Authorization' => "Bearer #{token}" })
      expect(response).to have_http_status(:ok)
    end

    it 'includes all user profile fields in response' do
      get_me(headers: { 'Authorization' => "Bearer #{token}" })

      expect(json['id']).to eq(user.id)
      expect(json['email']).to eq('ion@example.com')
      expect(json['first_name']).to eq('Ion')
      expect(json['last_name']).to eq('Popescu')
      expect(json.key?('avatar_url')).to be true
      expect(json['phone_number']).to eq('+40721000001')
      expect(json['church_name']).to eq('Betania')
      expect(json['city']).to eq('Cluj-Napoca')
    end
  end

  context 'with no Authorization header' do
    it 'returns 401' do
      get_me

      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Unauthorized')
    end
  end

  context 'with a malformed token' do
    it 'returns 401' do
      get_me(headers: { 'Authorization' => 'Bearer not.a.real.token' })

      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Unauthorized')
    end
  end

  context 'with an expired token' do
    it 'returns 401' do
      secret = Rails.application.credentials.dig(:auth, :jwt_secret)
      expired_token = JWT.encode({ user_id: user.id, exp: 1.second.ago.to_i }, secret, 'HS256')

      get_me(headers: { 'Authorization' => "Bearer #{expired_token}" })

      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Unauthorized')
    end
  end
end
