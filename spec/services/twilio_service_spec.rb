# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TwilioService do
  # rubocop:disable RSpec/VerifiedDoubles
  let(:twilio_messages) { double('twilio_messages') }
  let(:twilio_client)   { double('twilio_client', messages: twilio_messages) }
  # rubocop:enable RSpec/VerifiedDoubles

  before do
    allow(Twilio::REST::Client).to receive(:new)
      .with('ACtest', 'authtest')
      .and_return(twilio_client)
    allow(twilio_messages).to receive(:create)
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:twilio, :account_sid).and_return('ACtest')
    allow(Rails.application.credentials).to receive(:dig).with(:twilio, :auth_token).and_return('authtest')
    allow(Rails.application.credentials).to receive(:dig).with(:twilio, :whatsapp_from).and_return('whatsapp:+14155238886')
  end

  describe '.send_whatsapp' do
    subject(:call) do
      described_class.send_whatsapp(
        to: '+40700123456',
        content_sid: 'HXabc123',
        content_variables: { '1' => 'Ion', '2' => 'Fara Regrete' }
      )
    end

    it 'creates a Twilio message with the correct parameters' do
      call
      expect(twilio_messages).to have_received(:create).with(
        from: 'whatsapp:+14155238886',
        to: 'whatsapp:+40700123456',
        content_sid: 'HXabc123',
        content_variables: '{"1":"Ion","2":"Fara Regrete"}'
      )
    end

    context 'when DISABLE_EMAILS is true' do
      it 'does not call Twilio' do
        with_env('DISABLE_EMAILS', 'true') { call }
        expect(twilio_messages).not_to have_received(:create)
      end
    end

    context 'when Twilio raises a REST error' do
      before do
        allow(twilio_messages).to receive(:create).and_raise(
          Twilio::REST::RestError.new('test error', double(status_code: 400, body: {}))
        )
      end

      it 'logs the error and does not re-raise' do
        allow(Rails.logger).to receive(:error)
        expect { call }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(/TwilioService WhatsApp error/)
      end
    end
  end

  describe '.whatsapp_enabled?' do
    it 'returns true when DISABLE_EMAILS is unset' do
      expect(described_class.whatsapp_enabled?).to be true
    end

    it 'returns false when DISABLE_EMAILS=true' do
      with_env('DISABLE_EMAILS', 'true') do
        expect(described_class.whatsapp_enabled?).to be false
      end
    end
  end
end
