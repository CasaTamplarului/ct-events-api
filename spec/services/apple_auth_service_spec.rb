# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppleAuthService do
  let(:bundle_ids) { %w[com.example.app com.example.app.web] }
  let(:rsa_key)    { OpenSSL::PKey::RSA.generate(2048) }
  let(:jwk)        { JWT::JWK.new(rsa_key.public_key) }
  let(:jwks_body)  { { keys: [jwk.export] }.to_json }
  let(:jwks_uri)   { 'https://appleid.apple.com/auth/keys' }

  before do
    allow(Rails.application.credentials).to receive(:dig)
      .with(:auth, :apple_bundle_ids).and_return(bundle_ids)
    stub_request(:get, jwks_uri)
      .to_return(status: 200, body: jwks_body,
                 headers: { 'Content-Type' => 'application/json' })
    described_class.instance_variable_set(:@jwks_cache, nil)
    described_class.instance_variable_set(:@jwks_fetched_at, nil)
  end

  def encode_token(overrides = {})
    payload = {
      sub: 'apple-uid-123',
      email: 'ion@icloud.com',
      email_verified: true,
      iss: AppleAuthService::ISSUER,
      aud: 'com.example.app',
      exp: 1.hour.from_now.to_i,
      iat: Time.current.to_i
    }.merge(overrides)
    JWT.encode(payload, rsa_key, 'RS256', { kid: jwk.kid })
  end

  describe '.call' do
    context 'with a valid token' do
      it 'returns the correct uid' do
        expect(described_class.call(encode_token)[:uid]).to eq('apple-uid-123')
      end

      it 'returns the correct email' do
        expect(described_class.call(encode_token)[:email]).to eq('ion@icloud.com')
      end

      it 'returns nil avatar_url' do
        expect(described_class.call(encode_token)[:avatar_url]).to be_nil
      end

      it 'returns nil last_name' do
        expect(described_class.call(encode_token)[:last_name]).to be_nil
      end
    end

    context 'with a regular email' do
      it 'derives first_name from the email prefix' do
        result = described_class.call(encode_token(email: 'ion@icloud.com'))
        expect(result[:first_name]).to eq('ion')
      end
    end

    context 'with a privaterelay email' do
      it 'sets first_name to "Apple"' do
        relay = 'abc123def@privaterelay.appleid.com'
        expect(described_class.call(encode_token(email: relay))[:first_name]).to eq('Apple')
      end

      it 'sets last_name to nil' do
        relay = 'abc123def@privaterelay.appleid.com'
        expect(described_class.call(encode_token(email: relay))[:last_name]).to be_nil
      end
    end

    context 'when audience matches the second bundle_id' do
      it 'succeeds' do
        token = encode_token(aud: 'com.example.app.web')
        expect { described_class.call(token) }.not_to raise_error
      end
    end

    context 'with email_verified: false' do
      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token(email_verified: false)) }
          .to raise_error(AppleAuthService::InvalidTokenError)
      end
    end

    context 'with email_verified: "true" (string)' do
      it 'succeeds' do
        expect { described_class.call(encode_token(email_verified: 'true')) }.not_to raise_error
      end
    end

    context 'with no email claim in the token' do
      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token(email: nil)) }
          .to raise_error(AppleAuthService::InvalidTokenError)
      end
    end

    context 'with an expired token' do
      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token(exp: 1.hour.ago.to_i)) }
          .to raise_error(AppleAuthService::InvalidTokenError)
      end
    end

    context 'with wrong issuer' do
      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token(iss: 'https://accounts.google.com')) }
          .to raise_error(AppleAuthService::InvalidTokenError)
      end
    end

    context 'with audience not in bundle_ids list' do
      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token(aud: 'com.other.app')) }
          .to raise_error(AppleAuthService::InvalidTokenError)
      end
    end

    context 'with a bad signature (signed with a different key)' do
      it 'raises InvalidTokenError' do
        other_key = OpenSSL::PKey::RSA.generate(2048)
        token = JWT.encode(
          { sub: 'x', aud: 'com.example.app', iss: AppleAuthService::ISSUER,
            email: 'x@icloud.com', email_verified: true,
            exp: 1.hour.from_now.to_i, iat: Time.current.to_i },
          other_key, 'RS256', { kid: jwk.kid }
        )
        expect { described_class.call(token) }
          .to raise_error(AppleAuthService::InvalidTokenError)
      end
    end

    context 'when JWKS fetch returns non-2xx' do
      before { stub_request(:get, jwks_uri).to_return(status: 503, body: 'Service Unavailable') }

      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token) }
          .to raise_error(AppleAuthService::InvalidTokenError)
      end
    end

    context 'when JWKS endpoint times out' do
      before { stub_request(:get, jwks_uri).to_raise(Net::ReadTimeout) }

      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token) }
          .to raise_error(AppleAuthService::InvalidTokenError)
      end
    end

    context 'with missing credentials' do
      before do
        allow(Rails.application.credentials).to receive(:dig)
          .with(:auth, :apple_bundle_ids).and_return(nil)
      end

      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token) }
          .to raise_error(AppleAuthService::InvalidTokenError)
      end
    end

    context 'when JWKS cache is within TTL' do
      it 'only makes one HTTP call for two consecutive sign-ins' do
        described_class.call(encode_token)
        described_class.call(encode_token)
        expect(WebMock).to have_requested(:get, jwks_uri).once
      end

      it 'refetches after TTL expires' do
        described_class.call(encode_token)
        described_class.instance_variable_set(
          :@jwks_fetched_at,
          (AppleAuthService::JWKS_TTL + 1.second).ago
        )
        described_class.call(encode_token)
        expect(WebMock).to have_requested(:get, jwks_uri).twice
      end
    end

    context 'when JWKS key rotation occurs (kid not in cached JWKS)' do
      let(:new_rsa_key) { OpenSSL::PKey::RSA.generate(2048) }
      let(:new_jwk)     { JWT::JWK.new(new_rsa_key.public_key) }

      it 'refreshes JWKS and succeeds on retry' do
        stub_request(:get, jwks_uri)
          .to_return(
            { status: 200, body: { keys: [jwk.export] }.to_json,
              headers: { 'Content-Type' => 'application/json' } },
            { status: 200, body: { keys: [new_jwk.export] }.to_json,
              headers: { 'Content-Type' => 'application/json' } }
          )
        token = JWT.encode(
          { sub: 'apple-uid-new', email: 'ion@icloud.com', email_verified: true,
            iss: AppleAuthService::ISSUER, aud: 'com.example.app',
            exp: 1.hour.from_now.to_i, iat: Time.current.to_i },
          new_rsa_key, 'RS256', { kid: new_jwk.kid }
        )
        expect(described_class.call(token)[:uid]).to eq('apple-uid-new')
      end

      it 'raises InvalidTokenError when kid still not found after refresh' do
        unknown_key = OpenSSL::PKey::RSA.generate(2048)
        token = JWT.encode(
          { sub: 'x', aud: 'com.example.app', iss: AppleAuthService::ISSUER,
            email: 'x@icloud.com', email_verified: true,
            exp: 1.hour.from_now.to_i, iat: Time.current.to_i },
          unknown_key, 'RS256', { kid: 'unknown-kid' }
        )
        expect { described_class.call(token) }
          .to raise_error(AppleAuthService::InvalidTokenError)
      end
    end
  end
end
