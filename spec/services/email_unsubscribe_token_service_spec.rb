# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailUnsubscribeTokenService do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  describe '.generate' do
    it 'returns a non-empty string token for a known type' do
      token = described_class.generate(user: user, type: 'marketing_emails')
      expect(token).to be_a(String).and be_present
    end

    it 'raises ArgumentError for an unknown type' do
      expect { described_class.generate(user: user, type: 'bad_type') }
        .to raise_error(ArgumentError, /Unknown preference type/)
    end
  end

  describe '.verify' do
    described_class::PREFERENCE_COLUMNS.each do |col|
      it "returns user_id and type for a valid #{col} token" do
        token = described_class.generate(user: user, type: col)
        result = described_class.verify(token)
        expect(result[:user_id]).to eq(user.id)
        expect(result[:type]).to eq(col)
      end
    end

    it 'returns nil for a tampered token' do
      expect(described_class.verify('not-a-real-token')).to be_nil
    end

    it 'returns nil for an empty string' do
      expect(described_class.verify('')).to be_nil
    end

    it 'returns nil for an expired token' do
      token = nil
      travel_to(91.days.ago) { token = described_class.generate(user: user, type: 'marketing_emails') }
      expect(described_class.verify(token)).to be_nil
    end
  end
end
