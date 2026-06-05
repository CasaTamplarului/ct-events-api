# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Push Subscriptions' do
  let(:user) { create(:user) }
  let(:token) { JwtService.encode(user.id) }
  let(:headers) { { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{token}" } }

  describe 'POST /api/v1/auth/me/push_subscriptions' do
    context 'with a valid JWT' do
      it 'creates a push subscription and returns 201' do
        post '/api/v1/auth/me/push_subscriptions',
             params: { token: 'fcm-token-abc', platform: 'ios', device_name: 'My iPhone' }.to_json,
             headers: headers

        expect(response).to have_http_status(:created)
        expect(json['push_subscription']['id']).to be_present
        expect(json['push_subscription']['token']).to eq('fcm-token-abc')
        expect(json['push_subscription']['platform']).to eq('ios')
        expect(json['push_subscription']['device_name']).to eq('My iPhone')
      end

      it 'associates the subscription with the current user' do
        post '/api/v1/auth/me/push_subscriptions',
             params: { token: 'fcm-token-xyz', platform: 'android' }.to_json,
             headers: headers

        expect(user.push_subscriptions.find_by(token: 'fcm-token-xyz')).to be_present
      end

      it 'returns 200 and updates device_name if token already exists for this user' do
        user.push_subscriptions.create!(token: 'existing-token', platform: 'ios', device_name: 'Old Name')

        post '/api/v1/auth/me/push_subscriptions',
             params: { token: 'existing-token', platform: 'ios', device_name: 'New Name' }.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)
        expect(user.push_subscriptions.find_by(token: 'existing-token').device_name).to eq('New Name')
      end

      it 'returns 422 when token is missing' do
        post '/api/v1/auth/me/push_subscriptions',
             params: { platform: 'web' }.to_json,
             headers: headers

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns 422 when platform is missing' do
        post '/api/v1/auth/me/push_subscriptions',
             params: { token: 'some-token' }.to_json,
             headers: headers

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns 422 when platform is invalid' do
        post '/api/v1/auth/me/push_subscriptions',
             params: { token: 'some-token', platform: 'fax' }.to_json,
             headers: headers

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without a JWT' do
      it 'returns 401' do
        post '/api/v1/auth/me/push_subscriptions',
             params: { token: 'fcm-token', platform: 'ios' }.to_json,
             headers: { 'Content-Type' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'DELETE /api/v1/auth/me/push_subscriptions/:id' do
    context 'with a valid JWT' do
      it 'destroys the subscription and returns 204' do
        sub = user.push_subscriptions.create!(token: 'to-delete', platform: 'web')

        delete "/api/v1/auth/me/push_subscriptions/#{sub.id}", headers: headers

        expect(response).to have_http_status(:no_content)
        expect(user.push_subscriptions.find_by(id: sub.id)).to be_nil
      end

      it 'returns 404 when subscription does not belong to current user' do
        other_user = create(:user)
        other_sub  = other_user.push_subscriptions.create!(token: 'other-token', platform: 'ios')

        delete "/api/v1/auth/me/push_subscriptions/#{other_sub.id}", headers: headers

        expect(response).to have_http_status(:not_found)
      end

      it 'returns 404 when id does not exist' do
        delete '/api/v1/auth/me/push_subscriptions/999999', headers: headers

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without a JWT' do
      it 'returns 401' do
        delete '/api/v1/auth/me/push_subscriptions/1',
               headers: { 'Content-Type' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
