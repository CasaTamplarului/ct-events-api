# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/microsoft' do
  let(:ms_data) do
    {
      uid:        'ms-uid-123',
      email:      'ion@outlook.com',
      first_name: 'Ion',
      last_name:  'Popescu',
      avatar_url: nil
    }
  end

  def post_microsoft(params = { id_token: 'valid.ms.token' })
    post '/api/v1/auth/microsoft',
         params: params.to_json,
         headers: { 'Content-Type' => 'application/json' }
  end

  context 'with a valid token — new user' do
    before { allow(MicrosoftAuthService).to receive(:call).and_return(ms_data) }

    it 'returns 200 with a JWT and user data' do
      post_microsoft
      expect(response).to have_http_status(:ok)
      expect(json['jwt']).to be_present
      expect(json['user']['email']).to eq('ion@outlook.com')
      expect(json['user']['first_name']).to eq('Ion')
    end

    it 'creates a new User record' do
      expect { post_microsoft }.to change(User, :count).by(1)
    end

    it 'creates a UserIdentity with provider microsoft' do
      post_microsoft
      expect(UserIdentity.where(provider: 'microsoft', uid: 'ms-uid-123')).to exist
    end

    it 'returns a JWT that decodes to the correct user_id' do
      post_microsoft
      user_id = JwtService.decode(json['jwt'])
      expect(user_id).to eq(User.find_by(email: 'ion@outlook.com').id)
    end

    it 'returns nil avatar_url' do
      post_microsoft
      expect(json['user']['avatar_url']).to be_nil
    end

    it 'returns can_change_email: false' do
      post_microsoft
      expect(json['user']['can_change_email']).to be false
    end

    it 'includes language in the user response' do
      post_microsoft
      expect(json['user'].key?('language')).to be true
    end
  end

  context 'with a valid token — existing UserIdentity (idempotent)' do
    before do
      allow(MicrosoftAuthService).to receive(:call).and_return(ms_data)
      post_microsoft
    end

    it 'does not create a second user on repeated sign-in' do
      expect { post_microsoft }.not_to change(User, :count)
      expect(response).to have_http_status(:ok)
    end
  end

  context 'with a valid token — existing User matched by email' do
    let!(:existing_user) { create(:user, email: 'ion@outlook.com') }

    before { allow(MicrosoftAuthService).to receive(:call).and_return(ms_data) }

    it 'does not create a new user' do
      expect { post_microsoft }.not_to change(User, :count)
    end

    it 'links a new Microsoft identity to the existing user' do
      post_microsoft
      expect(UserIdentity.find_by(provider: 'microsoft', uid: 'ms-uid-123').user).to eq(existing_user)
    end
  end

  context 'attendee backfill on new user' do
    before { allow(MicrosoftAuthService).to receive(:call).and_return(ms_data) }

    it 'links existing attendees with matching email to the new user' do
      event    = create(:event)
      attendee = create(:attendee, event: event, email_address: 'ion@outlook.com')

      post_microsoft

      user = User.find_by(email: 'ion@outlook.com')
      expect(attendee.reload.user).to eq(user)
    end
  end

  context 'attendee backfill on email-matched existing user' do
    let!(:existing_user) { create(:user, email: 'ion@outlook.com') }

    before { allow(MicrosoftAuthService).to receive(:call).and_return(ms_data) }

    it 'links existing attendees to the matched user' do
      event    = create(:event)
      attendee = create(:attendee, event: event, email_address: 'ion@outlook.com')

      post_microsoft

      expect(attendee.reload.user).to eq(existing_user)
    end
  end

  context 'with a missing id_token param' do
    it 'returns 422' do
      post_microsoft({})
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to eq('id_token is required')
    end
  end

  context 'with an invalid token' do
    before do
      allow(MicrosoftAuthService).to receive(:call)
        .and_raise(MicrosoftAuthService::InvalidTokenError, 'invalid')
    end

    it 'returns 401' do
      post_microsoft
      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Invalid Microsoft token')
    end
  end
end
