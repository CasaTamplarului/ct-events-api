# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PasskeyChallengeService do
  let(:challenge) { 'test-challenge-base64url' }

  describe '.encode + .decode round-trip' do
    it 'returns the correct challenge' do
      token = described_class.encode(
        challenge: challenge,
        purpose: described_class::PURPOSE_REGISTER,
        user_id: 42
      )
      payload = described_class.decode(token, expected_purpose: described_class::PURPOSE_REGISTER)
      expect(payload['challenge']).to eq(challenge)
    end

    it 'returns the correct user_id' do
      token = described_class.encode(
        challenge: challenge,
        purpose: described_class::PURPOSE_REGISTER,
        user_id: 42
      )
      payload = described_class.decode(token, expected_purpose: described_class::PURPOSE_REGISTER)
      expect(payload['user_id']).to eq(42)
    end

    it 'returns nil user_id for authenticate purpose' do
      token = described_class.encode(
        challenge: challenge,
        purpose: described_class::PURPOSE_AUTHENTICATE
      )
      payload = described_class.decode(token, expected_purpose: described_class::PURPOSE_AUTHENTICATE)
      expect(payload['user_id']).to be_nil
    end
  end

  describe '.decode' do
    it 'raises InvalidTokenError when purpose does not match' do
      token = described_class.encode(
        challenge: challenge,
        purpose: described_class::PURPOSE_REGISTER,
        user_id: 1
      )
      expect do
        described_class.decode(token, expected_purpose: described_class::PURPOSE_AUTHENTICATE)
      end.to raise_error(described_class::InvalidTokenError)
    end

    it 'raises InvalidTokenError when token is expired' do
      payload = {
        'challenge' => challenge,
        'purpose' => described_class::PURPOSE_REGISTER,
        'user_id' => 1,
        'exp' => 1.minute.ago.to_i
      }
      secret = Rails.application.credentials.dig(:auth, :jwt_secret)
      token = JWT.encode(payload, secret, 'HS256')
      expect do
        described_class.decode(token, expected_purpose: described_class::PURPOSE_REGISTER)
      end.to raise_error(described_class::InvalidTokenError)
    end

    it 'raises InvalidTokenError when token signature is tampered' do
      token = described_class.encode(
        challenge: challenge,
        purpose: described_class::PURPOSE_REGISTER,
        user_id: 1
      )
      tampered = "#{token[0..-5]}XXXX"
      expect do
        described_class.decode(tampered, expected_purpose: described_class::PURPOSE_REGISTER)
      end.to raise_error(described_class::InvalidTokenError)
    end
  end
end
