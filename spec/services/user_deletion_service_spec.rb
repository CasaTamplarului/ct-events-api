# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserDeletionService do
  let(:user) do
    create(:user,
           first_name: 'Ion',
           last_name: 'Popescu',
           email: 'ion@example.com',
           phone_number: '+40721000001',
           church_name: 'Betania',
           city: 'Cluj-Napoca',
           language: 'ro')
  end

  describe '.call' do
    context 'when anonymising PII fields on the user row' do
      before { described_class.call(user) }

      it 'stamps deleted_at' do
        expect(user.reload.deleted_at).to be_present
      end

      it 'sets first_name to "Deleted"' do
        expect(user.reload.first_name).to eq('Deleted')
      end

      it 'clears email' do
        expect(user.reload.email).to be_nil
      end

      it 'clears last_name' do
        expect(user.reload.last_name).to be_nil
      end

      it 'clears avatar_url' do
        expect(user.reload.avatar_url).to be_nil
      end

      it 'clears phone_number' do
        expect(user.reload.phone_number).to be_nil
      end

      it 'clears church_name' do
        expect(user.reload.church_name).to be_nil
      end

      it 'clears city' do
        expect(user.reload.city).to be_nil
      end

      it 'clears language' do
        expect(user.reload.language).to be_nil
      end

      it 'clears password_digest' do
        expect(user.reload.password_digest).to be_nil
      end

      it 'clears password_reset_token' do
        expect(user.reload.password_reset_token).to be_nil
      end

      it 'clears password_reset_token_expires_at' do
        expect(user.reload.password_reset_token_expires_at).to be_nil
      end
    end

    context 'when destroying associated identity/passkey records' do
      before do
        user.user_identities.create!(provider: 'google', uid: 'google-uid-123')
        create(:passkey, user: user)
        described_class.call(user)
      end

      it 'destroys all user_identities' do
        expect(UserIdentity.where(user_id: user.id)).to be_empty
      end

      it 'destroys all passkeys' do
        expect(Passkey.where(user_id: user.id)).to be_empty
      end
    end

    context 'when attendee records exist for the user' do
      let!(:event)    { create(:event) }
      let!(:attendee) { create(:attendee, event: event, user: user, email_address: 'ion@example.com', first_name: 'Ion') }

      before { described_class.call(user) }

      it 'leaves attendee user_id pointing to the anonymised user' do
        expect(attendee.reload.user_id).to eq(user.id)
      end

      it 'leaves attendee email_address unchanged' do
        expect(attendee.reload.email_address).to eq('ion@example.com')
      end

      it 'leaves attendee first_name unchanged' do
        expect(attendee.reload.first_name).to eq('Ion')
      end
    end
  end
end
