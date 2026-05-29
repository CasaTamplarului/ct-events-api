# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FacebookAuthService do
  let(:access_token) { 'test_access_token' }
  let(:app_id) { 'test_app_id' }
  let(:app_secret) { 'test_app_secret' }

  let(:debug_token_url) do
    "https://graph.facebook.com/debug_token?input_token=#{access_token}&access_token=#{app_id}%7C#{app_secret}"
  end

  let(:me_url) do
    "https://graph.facebook.com/me?fields=id%2Cemail%2Cfirst_name%2Clast_name%2Cpicture.type%28large%29&access_token=#{access_token}"
  end

  before do
    allow(Rails.application.credentials).to receive(:dig)
      .with(:auth, :facebook_app_id).and_return(app_id)
    allow(Rails.application.credentials).to receive(:dig)
      .with(:auth, :facebook_app_secret).and_return(app_secret)
  end

  describe '.call' do
    context 'with a valid token' do
      before do
        stub_request(:get, debug_token_url)
          .to_return(
            status: 200,
            body: { data: { is_valid: true, app_id: app_id } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
        stub_request(:get, me_url)
          .to_return(
            status: 200,
            body: {
              id: 'fb-uid-123',
              email: 'ion@example.com',
              first_name: 'Ion',
              last_name: 'Popescu',
              picture: { data: { url: 'https://fb.com/photo.jpg' } }
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns the correct uid' do
        expect(described_class.call(access_token)[:uid]).to eq('fb-uid-123')
      end

      it 'returns the correct email' do
        expect(described_class.call(access_token)[:email]).to eq('ion@example.com')
      end

      it 'returns the correct first_name' do
        expect(described_class.call(access_token)[:first_name]).to eq('Ion')
      end

      it 'returns the correct last_name' do
        expect(described_class.call(access_token)[:last_name]).to eq('Popescu')
      end

      it 'returns the correct avatar_url' do
        expect(described_class.call(access_token)[:avatar_url]).to eq('https://fb.com/photo.jpg')
      end
    end

    context 'with a nil email (phone-only Facebook account)' do
      before do
        stub_request(:get, debug_token_url)
          .to_return(
            status: 200,
            body: { data: { is_valid: true, app_id: app_id } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
        stub_request(:get, me_url)
          .to_return(
            status: 200,
            body: { id: 'fb-uid-456', first_name: 'Ion', last_name: 'Popescu',
                    picture: { data: { url: nil } } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns nil email without raising' do
        result = described_class.call(access_token)
        expect(result[:email]).to be_nil
      end
    end

    context 'when debug_token returns is_valid: false' do
      before do
        stub_request(:get, debug_token_url)
          .to_return(
            status: 200,
            body: { data: { is_valid: false, app_id: app_id } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'raises InvalidTokenError' do
        expect { described_class.call(access_token) }
          .to raise_error(FacebookAuthService::InvalidTokenError)
      end
    end

    context 'when debug_token returns wrong app_id' do
      before do
        stub_request(:get, debug_token_url)
          .to_return(
            status: 200,
            body: { data: { is_valid: true, app_id: 'other_app' } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'raises InvalidTokenError' do
        expect { described_class.call(access_token) }
          .to raise_error(FacebookAuthService::InvalidTokenError)
      end
    end

    context 'when Graph API returns non-2xx' do
      before do
        stub_request(:get, debug_token_url)
          .to_return(status: 400, body: '{}',
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'raises InvalidTokenError' do
        expect { described_class.call(access_token) }
          .to raise_error(FacebookAuthService::InvalidTokenError)
      end
    end

    context 'when /me returns non-2xx (after valid debug_token)' do
      before do
        stub_request(:get, debug_token_url)
          .to_return(
            status: 200,
            body: { data: { is_valid: true, app_id: app_id } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
        stub_request(:get, me_url)
          .to_return(status: 500, body: 'Internal Server Error',
                     headers: { 'Content-Type' => 'text/plain' })
      end

      it 'raises InvalidTokenError' do
        expect { described_class.call(access_token) }
          .to raise_error(FacebookAuthService::InvalidTokenError)
      end
    end

    context 'with no profile picture' do
      before do
        stub_request(:get, debug_token_url)
          .to_return(
            status: 200,
            body: { data: { is_valid: true, app_id: app_id } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
        stub_request(:get, me_url)
          .to_return(
            status: 200,
            body: { id: 'fb-uid-999', first_name: 'Ion', last_name: 'Popescu',
                    email: 'ion@example.com' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns nil avatar_url' do
        result = described_class.call(access_token)
        expect(result[:avatar_url]).to be_nil
      end
    end
  end
end
