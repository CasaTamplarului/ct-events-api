# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserIdentity do
  it 'has a valid factory' do
    expect(build(:user_identity)).to be_valid
  end

  describe 'validations' do
    subject { build(:user_identity) }

    it { is_expected.to validate_presence_of(:provider) }
    it { is_expected.to validate_presence_of(:uid) }
  end

  describe 'uniqueness validation' do
    let(:user) { create(:user) }
    let(:user_identity) { create(:user_identity, user:) }

    it 'enforces uniqueness of uid scoped to provider' do
      duplicate = build(:user_identity, user:, provider: user_identity.provider, uid: user_identity.uid)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:uid]).to be_present
    end
  end

  describe 'associations' do
    subject { build(:user_identity) }

    it { is_expected.to belong_to(:user) }
  end
end
