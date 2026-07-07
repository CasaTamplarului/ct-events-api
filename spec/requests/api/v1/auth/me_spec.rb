# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Auth::Me endpoints' do
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

  def patch_me(params, headers: {})
    patch '/api/v1/auth/me',
          params: params.to_json,
          headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{token}" }.merge(headers)
  end

  def patch_password(params)
    patch '/api/v1/auth/me/password',
          params: params.to_json,
          headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{token}" }
  end

  # ── GET /api/v1/auth/me ──────────────────────────────────────────────────────

  describe 'GET /api/v1/auth/me' do
    context 'with a valid JWT' do
      it 'returns 200 with correct user data' do
        get_me(headers: { 'Authorization' => "Bearer #{token}" })
        expect(response).to have_http_status(:ok)
      end

      it 'includes all user profile fields in response' do
        get_me(headers: { 'Authorization' => "Bearer #{token}" })

        expected = { 'id' => user.id, 'email' => 'ion@example.com', 'first_name' => 'Ion',
                     'last_name' => 'Popescu', 'avatar_url' => nil, 'phone_number' => '+40721000001',
                     'church_name' => 'Betania', 'city' => 'Cluj-Napoca' }
        expect(json).to include(expected)
      end

      it 'returns can_change_email false for a user with no email identity' do
        get_me(headers: { 'Authorization' => "Bearer #{token}" })
        expect(json['can_change_email']).to be false
      end

      it 'returns can_change_email true for a user with an email identity' do
        user.user_identities.create!(provider: 'email', uid: user.email)
        get_me(headers: { 'Authorization' => "Bearer #{token}" })
        expect(json['can_change_email']).to be true
      end

      it 'includes email_preferences with all four fields' do
        get_me(headers: { 'Authorization' => "Bearer #{token}" })

        expect(json['email_preferences']).to eq({
                                                  'marketing_emails' => true,
                                                  'payment_reminder_emails' => true,
                                                  'event_reminder_emails' => true,
                                                  'event_update_emails' => true
                                                })
      end

      it 'includes push_preferences with all four fields defaulting to true' do
        get_me(headers: { 'Authorization' => "Bearer #{token}" })

        expect(json['push_preferences']).to eq({
                                                 'marketing_push' => true,
                                                 'payment_reminder_push' => true,
                                                 'event_reminder_push' => true,
                                                 'event_update_push' => true
                                               })
      end

      it 'includes push_subscriptions as empty array when none registered' do
        get_me(headers: { 'Authorization' => "Bearer #{token}" })

        expect(json['push_subscriptions']).to eq([])
      end

      it 'includes push_subscriptions with id, platform and device_name but not token' do
        sub1 = user.push_subscriptions.create!(token: 'tok-1', platform: 'android', device_name: 'My Phone')
        sub2 = user.push_subscriptions.create!(token: 'tok-2', platform: 'web',     device_name: nil)

        get_me(headers: { 'Authorization' => "Bearer #{token}" })

        expect(json['push_subscriptions']).to contain_exactly({ 'id' => sub1.id, 'platform' => 'android', 'device_name' => 'My Phone' }, { 'id' => sub2.id, 'platform' => 'web', 'device_name' => nil })
        expect(json['push_subscriptions'].map(&:keys).flatten).not_to include('token')
      end

      it 'includes role in response' do
        get_me(headers: { 'Authorization' => "Bearer #{token}" })
        expect(json['role']).to eq('attendee')
      end

      it 'includes permissions hash in response' do
        get_me(headers: { 'Authorization' => "Bearer #{token}" })
        expect(json['permissions']).to eq({
                                            'can_check_in_attendees' => false,
                                            'can_scan_food_stamp' => false,
                                            'can_send_push_notifications' => false,
                                            'can_manage_bracelets' => false,
                                            'can_send_emails' => false,
                                            'can_send_whatsapp' => false
                                          })
      end

      it 'returns updated permissions for a volunteer' do
        user.update!(role: 'volunteer')
        get_me(headers: { 'Authorization' => "Bearer #{token}" })
        expect(json['role']).to eq('volunteer')
        expect(json['permissions']).to eq({
                                            'can_check_in_attendees' => true,
                                            'can_scan_food_stamp' => true,
                                            'can_send_push_notifications' => false,
                                            'can_manage_bracelets' => false,
                                            'can_send_emails' => false,
                                            'can_send_whatsapp' => false
                                          })
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

  # ── PATCH /api/v1/auth/me ────────────────────────────────────────────────────

  describe 'PATCH /api/v1/auth/me' do
    context 'with valid profile fields' do
      it 'returns 200 with updated fields' do
        patch_me({ first_name: 'Vasile', city: 'Oradea', language: 'ro-RO' })

        expect(response).to have_http_status(:ok)
        expect(json).to include('first_name' => 'Vasile', 'city' => 'Oradea', 'language' => 'ro-RO')
      end

      it 'persists all updatable fields' do
        patch_me({ phone_number: '+40700000000', church_name: 'Betel', last_name: 'Ionescu' })

        expect(json).to include('phone_number' => '+40700000000',
                                'church_name' => 'Betel', 'last_name' => 'Ionescu')
      end
    end

    context 'when updating email as an email/password user' do
      before { user.user_identities.create!(provider: 'email', uid: user.email) }

      it 'updates the email' do
        patch_me({ email: 'new@example.com' })

        expect(response).to have_http_status(:ok)
        expect(json['email']).to eq('new@example.com')
      end
    end

    context 'when updating email as a Google-only user' do
      before { user.user_identities.create!(provider: 'google', uid: 'google-uid') }

      it 'returns 422' do
        patch_me({ email: 'new@example.com' })

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json['error']).to eq('Email cannot be changed on Google accounts')
      end
    end

    context 'with a blank first_name' do
      it 'returns 422' do
        patch_me({ first_name: '' })

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json['error']).to be_present
      end
    end

    context 'without a JWT' do
      it 'returns 401' do
        patch '/api/v1/auth/me',
              params: { first_name: 'x' }.to_json,
              headers: { 'Content-Type' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # ── DELETE /api/v1/auth/me ───────────────────────────────────────────────────

  describe 'DELETE /api/v1/auth/me' do
    def delete_me(headers: { 'Authorization' => "Bearer #{token}" })
      delete '/api/v1/auth/me',
             headers: { 'Content-Type' => 'application/json' }.merge(headers)
    end

    context 'with a valid JWT' do
      it 'returns 204' do
        delete_me
        expect(response).to have_http_status(:no_content)
      end

      it 'stamps deleted_at on the user' do
        delete_me
        expect(user.reload.deleted_at).to be_present
      end

      it 'sets first_name to "Deleted"' do
        delete_me
        expect(user.reload.first_name).to eq('Deleted')
      end

      it 'clears the email' do
        delete_me
        expect(user.reload.email).to be_nil
      end
    end

    context 'when reusing the same JWT after deletion' do
      before { delete_me }

      it 'returns 401 on GET /api/v1/auth/me' do
        get_me(headers: { 'Authorization' => "Bearer #{token}" })
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns 401 on a second DELETE /api/v1/auth/me' do
        delete_me
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with no Authorization header' do
      it 'returns 401' do
        delete_me(headers: {})
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # ── PATCH /api/v1/auth/me/password ───────────────────────────────────────────

  describe 'PATCH /api/v1/auth/me/password' do
    context 'with an email/password account' do
      before { user.user_identities.create!(provider: 'email', uid: user.email) }

      it 'returns 200 with JWT and user on success' do
        patch_password(current_password: 'Password1!', password: 'NewPassword1!')

        expect(response).to have_http_status(:ok)
        expect(json['jwt']).to be_present
        expect(json['user']['email']).to eq(user.email)
      end

      it 'updates the password' do
        patch_password(current_password: 'Password1!', password: 'NewPassword1!')

        expect(user.reload.authenticate('NewPassword1!')).to be_truthy
      end

      it 'returns 401 when current_password is wrong' do
        patch_password(current_password: 'wrongpassword', password: 'NewPassword1!')

        expect(response).to have_http_status(:unauthorized)
        expect(json['error']).to eq('Current password is incorrect')
      end

      it 'returns 422 when new password is too short' do
        patch_password(current_password: 'Password1!', password: 'short')

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns 422 when params are missing' do
        patch_password({})

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json['error']).to eq('current_password and password are required')
      end
    end

    context 'with a Google-only account' do
      before { user.user_identities.create!(provider: 'google', uid: 'google-uid') }

      it 'returns 422' do
        patch_password(current_password: 'Password1!', password: 'NewPassword1!')

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json['error']).to eq('Password cannot be changed on Google accounts')
      end
    end
  end
end
