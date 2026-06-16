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
    it 'defaults all preference columns to true' do
      user = create(:user)
      expect(user.marketing_emails).to be true
      expect(user.payment_reminder_emails).to be true
      expect(user.event_reminder_emails).to be true
      expect(user.event_update_emails).to be true
    end
  end

  describe 'push preferences' do
    it 'defaults all push preference columns to true' do
      user = create(:user)
      expect(user.marketing_push).to be true
      expect(user.payment_reminder_push).to be true
      expect(user.event_reminder_push).to be true
      expect(user.event_update_push).to be true
    end
  end

  describe 'role' do
    describe 'default' do
      it 'defaults to attendee' do
        user = create(:user)
        expect(user.reload.role).to eq('attendee')
      end
    end

    describe 'validation' do
      it 'is valid with attendee role' do
        expect(build(:user, role: 'attendee')).to be_valid
      end

      it 'is valid with volunteer role' do
        expect(build(:user, role: 'volunteer')).to be_valid
      end

      it 'is valid with admin role' do
        expect(build(:user, role: 'admin')).to be_valid
      end

      it 'is invalid with an unknown role' do
        user = build(:user, role: 'superuser')
        expect(user).not_to be_valid
        expect(user.errors[:role]).to be_present
      end
    end

    describe '#can?' do
      context 'admin role' do
        let(:user) { build(:user, role: 'admin') }

        it { expect(user.can?(:can_check_in_attendees)).to be true }
        it { expect(user.can?(:can_scan_food_stamp)).to be true }
      end

      context 'volunteer role' do
        let(:user) { build(:user, role: 'volunteer') }

        it { expect(user.can?(:can_check_in_attendees)).to be true }
        it { expect(user.can?(:can_scan_food_stamp)).to be true }
      end

      context 'attendee role' do
        let(:user) { build(:user, role: 'attendee') }

        it { expect(user.can?(:can_check_in_attendees)).to be false }
        it { expect(user.can?(:can_scan_food_stamp)).to be false }
      end

      it 'returns false for an unknown permission' do
        expect(build(:user, role: 'admin').can?(:fly_to_moon)).to be false
      end
    end
  end
end
