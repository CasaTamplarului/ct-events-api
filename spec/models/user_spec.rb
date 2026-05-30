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

  describe 'profile fields' do
    it 'accepts church_name and city' do
      user = build(:user, church_name: 'Betel', city: 'Cluj')
      expect(user).to be_valid
      expect(user.church_name).to eq('Betel')
      expect(user.city).to eq('Cluj')
    end

    it 'is valid without last_name' do
      user = build(:user, last_name: nil)
      expect(user).to be_valid
    end
  end

  describe 'email normalization' do
    it 'strips and downcases email on save' do
      user = create(:user, email: '  Test@EXAMPLE.COM  ')
      expect(user.reload.email).to eq('test@example.com')
    end
  end

  describe 'Facebook phone-only accounts' do
    it 'is valid with a nil email (Facebook user with phone-only account)' do
      user = build(:user, email: nil, password: nil, password_digest: nil)
      expect(user).to be_valid
    end

    it 'allows multiple users with nil email (Facebook phone-only accounts)' do
      create(:user, email: nil, password: nil, password_digest: nil)
      user2 = build(:user, email: nil, password: nil, password_digest: nil)
      expect(user2).to be_valid
    end
  end

  describe 'email preferences' do
    it 'defaults all preference columns to false' do
      user = create(:user)
      expect(user.marketing_emails).to be false
      expect(user.payment_reminder_emails).to be false
      expect(user.payment_receipt_emails).to be false
      expect(user.event_reminder_emails).to be false
      expect(user.event_update_emails).to be false
    end
  end
end
