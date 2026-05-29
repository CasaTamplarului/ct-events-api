# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Auth::Passwords' do
  before do
    allow(SendgridService).to receive(:send_password_reset)
  end

  describe 'POST /api/v1/auth/password/forgot' do
    def post_forgot(params)
      post '/api/v1/auth/password/forgot',
           params: params.to_json,
           headers: { 'Content-Type' => 'application/json' }
    end

    context 'with an existing user' do
      let!(:user) { create(:user, email: 'ion@example.com') }

      it 'returns 200' do
        post_forgot(email: 'ion@example.com')

        expect(response).to have_http_status(:ok)
      end

      it 'returns the generic success message' do
        post_forgot(email: 'ion@example.com')

        expect(json['message']).to eq('If that email is registered, a reset link has been sent.')
      end

      it 'sets a password_reset_token on the user' do
        post_forgot(email: 'ion@example.com')

        expect(user.reload.password_reset_token).to be_present
      end

      it 'sets password_reset_token_expires_at to ~1 hour from now' do
        post_forgot(email: 'ion@example.com')

        expect(user.reload.password_reset_token_expires_at).to be_within(5.seconds).of(1.hour.from_now)
      end

      it 'calls SendgridService.send_password_reset with the user' do
        post_forgot(email: 'ion@example.com')

        expect(SendgridService).to have_received(:send_password_reset)
          .with(user: user, reset_url: anything)
      end

      it 'builds reset_url from FRONTEND_URL env var' do
        stub_const('ENV', ENV.to_h.merge('FRONTEND_URL' => 'https://app.example.com'))
        post_forgot(email: 'ion@example.com')

        expect(SendgridService).to have_received(:send_password_reset)
          .with(user: anything, reset_url: start_with('https://app.example.com/reset-password?token='))
      end
    end

    context 'with a non-existent email' do
      it 'returns 200 (no user enumeration)' do
        post_forgot(email: 'nobody@example.com')

        expect(response).to have_http_status(:ok)
      end

      it 'does not call SendgridService' do
        post_forgot(email: 'nobody@example.com')

        expect(SendgridService).not_to have_received(:send_password_reset)
      end
    end

    context 'with a missing email param' do
      it 'returns 422' do
        post_forgot({})

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json['error']).to be_present
      end
    end
  end

  describe 'POST /api/v1/auth/password/reset' do
    def post_reset(params)
      post '/api/v1/auth/password/reset',
           params: params.to_json,
           headers: { 'Content-Type' => 'application/json' }
    end

    let(:user) { create(:user) }
    let(:valid_token) { 'valid_token_abc123xyz' }

    before do
      user.update_columns(
        password_reset_token: valid_token,
        password_reset_token_expires_at: 1.hour.from_now
      )
    end

    context 'with a valid token' do
      it 'returns 200 with a JWT and user data' do
        post_reset(token: valid_token, password: 'NewPassword1!')

        expect(response).to have_http_status(:ok)
        expect(json['jwt']).to be_present
        expect(json['user']['email']).to eq(user.email)
      end

      it 'updates the user password' do
        post_reset(token: valid_token, password: 'NewPassword1!')

        expect(user.reload.authenticate('NewPassword1!')).to be_truthy
      end

      it 'clears the reset token after use' do
        post_reset(token: valid_token, password: 'NewPassword1!')

        expect(user.reload.password_reset_token).to be_nil
        expect(user.reload.password_reset_token_expires_at).to be_nil
      end

      it 'returns a JWT that decodes to the correct user_id' do
        post_reset(token: valid_token, password: 'NewPassword1!')

        expect(JwtService.decode(json['jwt'])).to eq(user.id)
      end

      it 'includes all user profile fields in the response' do
        post_reset(token: valid_token, password: 'NewPassword1!')

        expect(json['user']).to include('id', 'first_name', 'last_name', 'email',
                                        'avatar_url', 'phone_number', 'church_name', 'city')
      end
    end

    context 'with an invalid token' do
      it 'returns 422' do
        post_reset(token: 'bad_token', password: 'NewPassword1!')

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json['error']).to eq('Invalid or expired reset token')
      end
    end

    context 'with an expired token' do
      before { user.update_columns(password_reset_token_expires_at: 1.minute.ago) }

      it 'returns 422' do
        post_reset(token: valid_token, password: 'NewPassword1!')

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json['error']).to eq('Invalid or expired reset token')
      end
    end

    context 'with a password shorter than 8 characters' do
      it 'returns 422' do
        post_reset(token: valid_token, password: 'short')

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json['error']).to match(/password/i)
      end
    end

    context 'with missing params' do
      it 'returns 422 when token is missing' do
        post_reset(password: 'NewPassword1!')

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns 422 when password is missing' do
        post_reset(token: valid_token)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
