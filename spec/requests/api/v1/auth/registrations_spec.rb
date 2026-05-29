# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/registration' do
  def post_registration(params)
    post '/api/v1/auth/registration',
         params: params.to_json,
         headers: { 'Content-Type' => 'application/json' }
  end

  let(:valid_params) do
    {
      first_name: 'Ion',
      last_name: 'Popescu',
      email: 'ion@example.com',
      password: 'SecurePass1!'
    }
  end

  context 'with valid required params' do
    it 'returns 201 with a JWT and user data' do
      post_registration(valid_params)

      expect(response).to have_http_status(:created)
      expect(json['jwt']).to be_present
      expect(json['user']['email']).to eq('ion@example.com')
      expect(json['user']['first_name']).to eq('Ion')
    end

    it 'creates a User record' do
      expect { post_registration(valid_params) }.to change(User, :count).by(1)
    end

    it 'creates a UserIdentity with provider email' do
      post_registration(valid_params)
      expect(UserIdentity.where(provider: 'email', uid: 'ion@example.com')).to exist
    end

    it 'returns a JWT that decodes to the created user' do
      post_registration(valid_params)
      user_id = JwtService.decode(json['jwt'])
      expect(user_id).to eq(User.find_by(email: 'ion@example.com').id)
    end

    it 'normalizes email to lowercase' do
      post_registration(valid_params.merge(email: 'Ion@EXAMPLE.COM'))
      expect(User.find_by(email: 'ion@example.com')).to be_present
    end

    it 'includes all user profile fields in the response' do
      post_registration(valid_params.merge(phone_number: '+40700000000', church_name: 'Betel', city: 'Cluj'))

      expect(json['user']['phone_number']).to eq('+40700000000')
      expect(json['user']['church_name']).to eq('Betel')
      expect(json['user']['city']).to eq('Cluj')
      expect(json['user'].key?('avatar_url')).to be true
    end

    it 'is valid without optional fields (last_name, phone_number, church_name, city)' do
      post_registration({ first_name: 'Ion', email: 'ion@example.com', password: 'SecurePass1!' })
      expect(response).to have_http_status(:created)
      expect(json['user']['last_name']).to be_nil
    end

    it 'stores the language from params' do
      post_registration(valid_params.merge(language: 'ro-RO'))

      expect(User.find_by(email: 'ion@example.com').language).to eq('ro-RO')
    end
  end

  context 'with an existing attendee matching the registration email' do
    it 'links existing attendees with matching email to the new user' do
      event = create(:event)
      attendee = create(:attendee, event: event, email_address: 'ion@example.com')

      post_registration(valid_params)

      user = User.find_by(email: 'ion@example.com')
      expect(attendee.reload.user).to eq(user)
    end
  end

  context 'with missing required params' do
    it 'returns 422 when first_name is missing' do
      post_registration(valid_params.except(:first_name))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to be_present
    end

    it 'returns 422 when email is missing' do
      post_registration(valid_params.except(:email))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to be_present
    end

    it 'returns 422 when password is missing' do
      post_registration(valid_params.except(:password))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to be_present
    end
  end

  context 'with an invalid password' do
    it 'returns 422 when password is shorter than 8 characters' do
      post_registration(valid_params.merge(password: 'short'))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to match(/password/i)
    end
  end

  context 'with a duplicate email (email/password account)' do
    before { create(:user, email: 'ion@example.com') }

    it 'returns 409 with generic message' do
      post_registration(valid_params)
      expect(response).to have_http_status(:conflict)
      expect(json['error']).to eq('Email is already registered')
    end
  end

  context 'with a duplicate email (Google-only account)' do
    before do
      user = create(:user, email: 'ion@example.com', password: nil, password_digest: nil)
      user.user_identities.create!(provider: 'google', uid: 'google-uid-123')
    end

    it 'returns 409 with Google-specific message' do
      post_registration(valid_params)
      expect(response).to have_http_status(:conflict)
      expect(json['error']).to eq('This email is linked to a Google account. Please sign in with Google.')
    end
  end
end
