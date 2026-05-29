# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/session' do
  def post_session(params)
    post '/api/v1/auth/session',
         params: params.to_json,
         headers: { 'Content-Type' => 'application/json' }
  end

  let!(:user) do
    create(:user,
           email: 'ion@example.com',
           password: 'SecurePass1!',
           first_name: 'Ion',
           last_name: 'Popescu',
           phone_number: '+40700000000',
           church_name: 'Betel',
           city: 'Cluj')
  end

  context 'with valid credentials' do
    it 'returns 200 with a JWT and user data' do
      post_session({ email: 'ion@example.com', password: 'SecurePass1!' })

      expect(response).to have_http_status(:ok)
      expect(json['jwt']).to be_present
      expect(json['user']['email']).to eq('ion@example.com')
      expect(json['user']['first_name']).to eq('Ion')
    end

    it 'returns a JWT that decodes to the correct user_id' do
      post_session({ email: 'ion@example.com', password: 'SecurePass1!' })
      user_id = JwtService.decode(json['jwt'])
      expect(user_id).to eq(user.id)
    end

    it 'returns all user profile fields in the response' do
      post_session({ email: 'ion@example.com', password: 'SecurePass1!' })

      expect(json['user']['phone_number']).to eq('+40700000000')
      expect(json['user']['church_name']).to eq('Betel')
      expect(json['user']['city']).to eq('Cluj')
      expect(json['user'].key?('avatar_url')).to be true
    end

    it 'is case-insensitive for email' do
      post_session({ email: 'ION@EXAMPLE.COM', password: 'SecurePass1!' })
      expect(response).to have_http_status(:ok)
    end
  end

  context 'with a wrong password' do
    it 'returns 401 with a generic error' do
      post_session({ email: 'ion@example.com', password: 'WrongPassword' })
      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Invalid email or password')
    end
  end

  context 'with an unknown email' do
    it 'returns 401 with a generic error' do
      post_session({ email: 'nobody@example.com', password: 'SecurePass1!' })
      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Invalid email or password')
    end
  end

  context 'with missing params' do
    it 'returns 422 when email is missing' do
      post_session({ password: 'SecurePass1!' })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to eq('email and password are required')
    end

    it 'returns 422 when password is missing' do
      post_session({ email: 'ion@example.com' })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to eq('email and password are required')
    end
  end
end
