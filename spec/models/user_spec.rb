# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User do
  it 'has a valid factory' do
    expect(build(:user)).to be_valid
  end

  describe 'OAuth user (no password)' do
    it 'is valid without a password' do
      user = build(:user, password: nil, password_digest: nil)
      expect(user).to be_valid
    end
  end

  describe 'associations' do
    it { is_expected.to have_many(:user_identities).dependent(:destroy) }
    it { is_expected.to have_many(:attendees).dependent(:nullify) }
  end

  describe 'email normalization' do
    it 'strips and downcases email on save' do
      user = create(:user, email: '  Test@EXAMPLE.COM  ')
      expect(user.reload.email).to eq('test@example.com')
    end
  end
end
