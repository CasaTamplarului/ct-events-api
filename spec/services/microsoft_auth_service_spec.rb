# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MicrosoftAuthService do
  let(:client_id)  { 'test-microsoft-client-id' }
  let(:rsa_key)    { OpenSSL::PKey::RSA.generate(2048) }
  let(:jwk)        { JWT::JWK.new(rsa_key.public_key) }
  let(:jwks_body)  { { keys: [jwk.export] }.to_json }
  let(:jwks_uri)   { 'https://login.microsoftonline.com/consumers/discovery/v2.0/keys' }

  before do
    allow(Rails.application.credentials).to receive(:dig)
      .with(:auth, :microsoft_client_id).and_return(client_id)
    stub_request(:get, jwks_uri)
      .to_return(status: 200, body: jwks_body,
                 headers: { 'Content-Type' => 'application/json' })
    # Reset class-level JWKS cache between examples
    described_class.instance_variable_set(:@jwks_cache, nil)
    described_class.instance_variable_set(:@jwks_fetched_at, nil)
  end

  def encode_token(overrides = {})
    payload = {
      sub: 'ms-uid-123',
      email: 'ion@outlook.com',
      given_name: 'Ion',
      family_name: 'Popescu',
      iss: MicrosoftAuthService::ISSUER,
      aud: client_id,
      exp: 1.hour.from_now.to_i,
      iat: Time.current.to_i
    }.merge(overrides)
    JWT.encode(payload, rsa_key, 'RS256', { kid: jwk.kid })
  end

  describe '.call' do
    context 'with a valid token' do
      it 'returns the correct uid' do
        expect(described_class.call(encode_token)[:uid]).to eq('ms-uid-123')
      end

      it 'returns the correct email' do
        expect(described_class.call(encode_token)[:email]).to eq('ion@outlook.com')
      end

      it 'returns the correct first_name' do
        expect(described_class.call(encode_token)[:first_name]).to eq('Ion')
      end

      it 'returns the correct last_name' do
        expect(described_class.call(encode_token)[:last_name]).to eq('Popescu')
      end

      it 'returns nil avatar_url' do
        expect(described_class.call(encode_token)[:avatar_url]).to be_nil
      end
    end

    context 'with a token missing the email claim' do
      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token(email: nil)) }
          .to raise_error(MicrosoftAuthService::InvalidTokenError)
      end
    end

    context 'with an expired token' do
      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token(exp: 1.hour.ago.to_i)) }
          .to raise_error(MicrosoftAuthService::InvalidTokenError)
      end
    end

    context 'with wrong audience' do
      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token(aud: 'other-client-id')) }
          .to raise_error(MicrosoftAuthService::InvalidTokenError)
      end
    end

    context 'with wrong issuer' do
      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token(iss: 'https://accounts.google.com')) }
          .to raise_error(MicrosoftAuthService::InvalidTokenError)
      end
    end

    context 'with a bad signature (signed with a different key)' do
      it 'raises InvalidTokenError' do
        other_key = OpenSSL::PKey::RSA.generate(2048)
        token = JWT.encode(
          { sub: 'x', aud: client_id, iss: MicrosoftAuthService::ISSUER,
            exp: 1.hour.from_now.to_i, iat: Time.current.to_i },
          other_key, 'RS256', { kid: jwk.kid }
        )
        expect { described_class.call(token) }
          .to raise_error(MicrosoftAuthService::InvalidTokenError)
      end
    end

    context 'when JWKS fetch returns non-2xx' do
      before do
        stub_request(:get, jwks_uri).to_return(status: 503, body: 'Service Unavailable')
      end

      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token) }
          .to raise_error(MicrosoftAuthService::InvalidTokenError)
      end
    end

    context 'when JWKS endpoint times out' do
      before do
        stub_request(:get, jwks_uri).to_raise(Net::ReadTimeout)
      end

      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token) }
          .to raise_error(MicrosoftAuthService::InvalidTokenError)
      end
    end

    context 'with missing credentials' do
      before do
        allow(Rails.application.credentials).to receive(:dig)
          .with(:auth, :microsoft_client_id).and_return(nil)
      end

      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token) }
          .to raise_error(MicrosoftAuthService::InvalidTokenError)
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
          (MicrosoftAuthService::JWKS_TTL + 1.second).ago
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
          { sub: 'ms-uid-new', email: 'ion@outlook.com', given_name: 'Ion',
            family_name: 'Popescu', iss: MicrosoftAuthService::ISSUER,
            aud: client_id, exp: 1.hour.from_now.to_i, iat: Time.current.to_i },
          new_rsa_key, 'RS256', { kid: new_jwk.kid }
        )

        result = described_class.call(token)
        expect(result[:uid]).to eq('ms-uid-new')
      end

      it 'raises InvalidTokenError when kid still not found after refresh' do
        unknown_key = OpenSSL::PKey::RSA.generate(2048)
        token = JWT.encode(
          { sub: 'x', aud: client_id, iss: MicrosoftAuthService::ISSUER,
            exp: 1.hour.from_now.to_i, iat: Time.current.to_i },
          unknown_key, 'RS256', { kid: 'unknown-kid' }
        )

        expect { described_class.call(token) }
          .to raise_error(MicrosoftAuthService::InvalidTokenError)
      end
    end
  end
end
