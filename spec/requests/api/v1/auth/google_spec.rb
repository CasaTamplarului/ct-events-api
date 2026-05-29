# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/google' do
  let(:google_payload) do
    {
      'sub' => 'google-uid-123',
      'email' => 'ion@example.com',
      'given_name' => 'Ion',
      'family_name' => 'Popescu',
      'picture' => 'https://lh3.googleusercontent.com/photo.jpg'
    }
  end

  def post_google(id_token: 'valid.token')
    post '/api/v1/auth/google',
         params: { id_token: id_token }.to_json,
         headers: { 'Content-Type' => 'application/json' }
  end

  context 'with a valid Google token' do
    before do
      allow_any_instance_of(GoogleIDToken::Validator)
        .to receive(:check)
        .and_return(google_payload)
    end

    it 'returns 200 with a JWT and user data' do
      post_google

      expect(response).to have_http_status(:ok)
      expect(json['jwt']).to be_present
      expect(json['user']['email']).to eq('ion@example.com')
      expect(json['user']['first_name']).to eq('Ion')
      expect(json['user']['last_name']).to eq('Popescu')
      expect(json['user'].key?('phone_number')).to be true
      expect(json['user'].key?('city')).to be true
      expect(json['user'].key?('church_name')).to be true
    end

    it 'creates a new user on first sign-in' do
      expect { post_google }.to change(User, :count).by(1)
    end

    it 'creates a UserIdentity for the new user' do
      post_google
      expect(UserIdentity.where(provider: 'google', uid: 'google-uid-123')).to exist
    end

    it 'returns the same user on subsequent sign-ins (idempotent)' do
      post_google
      expect { post_google }.not_to change(User, :count)
      expect(response).to have_http_status(:ok)
    end

    it 'links an existing user account that has the same email' do
      existing_user = create(:user, email: 'ion@example.com')
      post_google

      expect(User.count).to eq(1)
      expect(UserIdentity.find_by(provider: 'google', uid: 'google-uid-123').user).to eq(existing_user)
    end

    it 'backfills attendees when linking an existing user account by email' do
      existing_user = create(:user, email: 'ion@example.com')
      event = create(:event)
      attendee = create(:attendee, event: event, email_address: 'ion@example.com')

      post_google

      expect(attendee.reload.user).to eq(existing_user)
    end

    it 'backfills user_id on attendees matching the email' do
      event = create(:event)
      attendee = create(:attendee, event: event, email_address: 'ion@example.com')

      post_google

      user = User.find_by(email: 'ion@example.com')
      expect(attendee.reload.user).to eq(user)
    end

    it 'returns a JWT that decodes to the correct user_id' do
      post_google

      user_id = JwtService.decode(json['jwt'])
      expect(user_id).to eq(User.find_by(email: 'ion@example.com').id)
    end
  end

  context 'with a missing id_token param' do
    it 'returns 422' do
      post '/api/v1/auth/google',
           params: {}.to_json,
           headers: { 'Content-Type' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to be_present
    end
  end

  context 'with an invalid Google token' do
    before do
      allow_any_instance_of(GoogleIDToken::Validator)
        .to receive(:check)
        .and_raise(GoogleIDToken::ValidationError, 'invalid token')
    end

    it 'returns 401' do
      post_google(id_token: 'bad.token')

      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Invalid Google token')
    end
  end
end
