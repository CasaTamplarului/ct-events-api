# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoogleAuthService do
  let(:valid_payload) do
    {
      'sub' => 'google-uid-123',
      'email' => 'ion@example.com',
      'given_name' => 'Ion',
      'family_name' => 'Popescu',
      'picture' => 'https://lh3.googleusercontent.com/photo.jpg'
    }
  end

  describe '.call' do
    context 'with a valid Google ID token' do
      before do
        allow_any_instance_of(GoogleIDToken::Validator)
          .to receive(:check)
          .and_return(valid_payload)
      end

      it 'returns the extracted user claims' do
        result = described_class.call('valid.id.token')

        expect(result).to eq(
          uid: 'google-uid-123',
          email: 'ion@example.com',
          first_name: 'Ion',
          last_name: 'Popescu',
          avatar_url: 'https://lh3.googleusercontent.com/photo.jpg'
        )
      end
    end

    context 'with an invalid or expired Google ID token' do
      before do
        allow_any_instance_of(GoogleIDToken::Validator)
          .to receive(:check)
          .and_raise(GoogleIDToken::ValidationError, 'token expired')
      end

      it 'raises InvalidTokenError' do
        expect { described_class.call('bad.token') }
          .to raise_error(GoogleAuthService::InvalidTokenError, 'token expired')
      end
    end
  end
end
