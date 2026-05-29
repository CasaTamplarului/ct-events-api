# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JwtService do
  let(:user_id) { 42 }

  describe '.encode and .decode' do
    it 'encodes a user_id into a JWT and decodes it back' do
      token = described_class.encode(user_id)
      expect(described_class.decode(token)).to eq(user_id)
    end
  end

  describe '.decode' do
    it 'raises JWT::DecodeError for a malformed token' do
      expect { described_class.decode('not.a.token') }.to raise_error(JWT::DecodeError)
    end

    it 'raises JWT::ExpiredSignature for an expired token' do
      secret = Rails.application.credentials.dig(:auth, :jwt_secret)
      expired_token = JWT.encode({ user_id: user_id, exp: 1.second.ago.to_i }, secret, 'HS256')
      expect { described_class.decode(expired_token) }.to raise_error(JWT::ExpiredSignature)
    end
  end
end
