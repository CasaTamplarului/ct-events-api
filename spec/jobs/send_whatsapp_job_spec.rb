# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SendWhatsappJob, type: :job do
  let(:event) { create(:event) }
  let!(:trans) do
    Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }
    create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Fara Regrete')
  end
  let(:order)    { create(:order) }
  let(:user)     { create(:user, first_name: 'Ion', last_name: 'Pop', phone_number: '+40700111222') }
  let!(:attendee) do
    create(:attendee, event: event, user: user, order: order,
                      first_name: 'Ion', last_name: 'Pop',
                      email_address: user.email, phone_number: user.phone_number,
                      payment_status: :paid)
  end

  let(:template) do
    create(:whatsapp_template,
           content_sid: 'HXtest',
           variables: [{ 'position' => 1, 'name' => 'first_name' },
                       { 'position' => 2, 'name' => 'event_name' }])
  end

  let(:broadcast) { create(:whatsapp_broadcast, whatsapp_template: template, event: event) }

  before { allow(TwilioService).to receive(:send_whatsapp) }

  def perform(extra = {})
    described_class.new.perform(
      template_id: template.id, user_ids: [user.id], broadcast_id: broadcast.id,
      event_id: event.id, **extra
    )
  end

  it 'calls TwilioService with correct content_variables' do
    perform
    expect(TwilioService).to have_received(:send_whatsapp).with(
      to: user.phone_number,
      content_sid: 'HXtest',
      content_variables: { '1' => 'Ion', '2' => 'Fara Regrete' }
    )
  end

  it 'records recipients in whatsapp_broadcast_recipients' do
    expect { perform }.to change(WhatsappBroadcastRecipient, :count).by(1)
  end

  it 'updates recipient_count on the broadcast' do
    perform
    expect(broadcast.reload.recipient_count).to eq(1)
  end

  context 'when exclude_broadcast_ids is given' do
    let!(:prior_broadcast) { create(:whatsapp_broadcast, whatsapp_template: template) }

    before do
      WhatsappBroadcastRecipient.insert_all(
        [{ whatsapp_broadcast_id: prior_broadcast.id, user_id: user.id, phone_number: user.phone_number.downcase }]
      )
    end

    it 'skips users whose phone was already sent' do
      perform(exclude_broadcast_ids: [prior_broadcast.id])
      expect(TwilioService).not_to have_received(:send_whatsapp)
    end
  end

  context 'with unregistered attendees (no user account)' do
    let(:unregistered) do
      create(:attendee, event: event, user: nil, order: order,
                        first_name: 'Ana', last_name: 'Ionescu',
                        email_address: 'ana@example.com',
                        phone_number: '+40700999888',
                        payment_status: :paid)
    end

    before { unregistered }

    it 'sends to unregistered attendees' do
      perform(user_ids: [])
      expect(TwilioService).to have_received(:send_whatsapp).with(
        hash_including(to: '+40700999888')
      )
    end
  end

  context 'when user has no phone_number' do
    before { user.update!(phone_number: nil) }

    it 'skips that user' do
      perform
      expect(TwilioService).not_to have_received(:send_whatsapp)
    end
  end
end
