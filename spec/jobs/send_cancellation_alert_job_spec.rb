# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SendCancellationAlertJob, type: :job do
  let(:event) { create(:event) }
  let!(:ro_translation) do
    Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }
    create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Fara Regrete')
  end
  let(:order)    { create(:order) }
  let(:user)     { create(:user, first_name: 'Ion', last_name: 'Pop', email: 'ion@example.com') }
  let!(:attendee) do
    create(:attendee, event: event, order: order, user: user,
                      first_name: 'Ion', last_name: 'Pop',
                      payment_status: :attendee_cancelled,
                      cancellation_reason: 'health')
  end
  let!(:admin) { create(:user, role: 'admin', email: 'admin@example.com') }

  before { allow(FcmService).to receive(:send_to_user) }

  def perform(id = attendee.id)
    described_class.new.perform(attendee_id: id)
  end

  it 'calls FcmService.send_to_user for each admin user' do
    perform
    expect(FcmService).to have_received(:send_to_user).with(hash_including(user: admin))
  end

  it 'includes the event name in the push title' do
    perform
    expect(FcmService).to have_received(:send_to_user).with(
      hash_including(title: 'Anulare bilet — Fara Regrete')
    )
  end

  it 'includes the attendee name and Romanian reason label in the body' do
    perform
    expect(FcmService).to have_received(:send_to_user).with(
      hash_including(body: 'Ion Pop și-a anulat locul. Motiv: Motive de sănătate')
    )
  end

  it 'uses "Nespecificat" when cancellation_reason is nil' do
    attendee.update_columns(cancellation_reason: nil)
    perform
    expect(FcmService).to have_received(:send_to_user).with(
      hash_including(body: include('Nespecificat'))
    )
  end

  it 'sends with preference: nil so admin push preferences are not checked' do
    perform
    expect(FcmService).to have_received(:send_to_user).with(
      hash_including(preference: nil)
    )
  end

  it 'does not call FcmService for non-admin users' do
    perform
    expect(FcmService).not_to have_received(:send_to_user).with(
      hash_including(user: user)
    )
  end

  it 'does nothing when the attendee is not found' do
    expect { perform(0) }.not_to raise_error
    expect(FcmService).not_to have_received(:send_to_user)
  end
end
