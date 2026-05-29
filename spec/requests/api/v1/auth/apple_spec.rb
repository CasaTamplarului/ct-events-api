# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/apple' do
  let(:apple_data) do
    {
      uid: 'apple-uid-123',
      email: 'ion@icloud.com',
      first_name: 'ion',
      last_name: nil,
      avatar_url: nil
    }
  end

  def post_apple(params = { id_token: 'valid.apple.token' })
    post '/api/v1/auth/apple',
         params: params.to_json,
         headers: { 'Content-Type' => 'application/json' }
  end

  context 'with a valid token — new user' do
    before { allow(AppleAuthService).to receive(:call).and_return(apple_data) }

    it 'returns 200 with a JWT and user data' do
      post_apple
      expect(response).to have_http_status(:ok)
      expect(json['jwt']).to be_present
      expect(json['user']['email']).to eq('ion@icloud.com')
      expect(json['user']['first_name']).to eq('ion')
    end

    it 'creates a new User record' do
      expect { post_apple }.to change(User, :count).by(1)
    end

    it 'creates a UserIdentity with provider apple' do
      post_apple
      expect(UserIdentity.where(provider: 'apple', uid: 'apple-uid-123')).to exist
    end

    it 'returns nil avatar_url' do
      post_apple
      expect(json['user']['avatar_url']).to be_nil
    end

    it 'returns can_change_email: false' do
      post_apple
      expect(json['user']['can_change_email']).to be false
    end
  end

  context 'with a valid token — existing UserIdentity (idempotent)' do
    before do
      allow(AppleAuthService).to receive(:call).and_return(apple_data)
      post_apple
    end

    it 'does not create a second user on repeated sign-in' do
      expect { post_apple }.not_to change(User, :count)
      expect(response).to have_http_status(:ok)
    end
  end

  context 'with a valid token — existing User matched by email' do
    let!(:existing_user) { create(:user, email: 'ion@icloud.com') }

    before { allow(AppleAuthService).to receive(:call).and_return(apple_data) }

    it 'does not create a new user' do
      expect { post_apple }.not_to change(User, :count)
    end

    it 'links a new Apple identity to the existing user' do
      post_apple
      expect(UserIdentity.find_by(provider: 'apple', uid: 'apple-uid-123').user).to eq(existing_user)
    end
  end

  context 'when backfilling attendees on new user' do
    before { allow(AppleAuthService).to receive(:call).and_return(apple_data) }

    it 'links existing attendees with matching email to the new user' do
      event    = create(:event)
      attendee = create(:attendee, event: event, email_address: 'ion@icloud.com')
      post_apple
      user = User.find_by(email: 'ion@icloud.com')
      expect(attendee.reload.user).to eq(user)
    end
  end

  context 'when backfilling attendees on email-matched existing user' do
    let!(:existing_user) { create(:user, email: 'ion@icloud.com') }

    before { allow(AppleAuthService).to receive(:call).and_return(apple_data) }

    it 'links existing attendees to the matched user' do
      event    = create(:event)
      attendee = create(:attendee, event: event, email_address: 'ion@icloud.com')
      post_apple
      expect(attendee.reload.user).to eq(existing_user)
    end
  end

  context 'with a missing id_token param' do
    it 'returns 422' do
      post_apple({})
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to eq('id_token is required')
    end
  end

  context 'with an invalid token' do
    before do
      allow(AppleAuthService).to receive(:call)
        .and_raise(AppleAuthService::InvalidTokenError, 'invalid')
    end

    it 'returns 401' do
      post_apple
      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Invalid Apple token')
    end
  end
end
