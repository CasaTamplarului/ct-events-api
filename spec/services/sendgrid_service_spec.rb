# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SendgridService do
  describe '.send_password_reset' do
    let(:romanian_user) { build(:user, first_name: 'Ion', language: 'ro-RO', email: 'ion@example.com') }
    let(:english_user) { build(:user, first_name: 'John', language: 'en-US', email: 'john@example.com') }
    let(:reset_url) { 'https://app.example.com/reset-password?token=abc123' }

    before do
      stub_request(:post, 'https://api.sendgrid.com/v3/mail/send')
        .to_return(status: 202, body: '', headers: {})
    end

    it 'posts to the SendGrid mail/send endpoint' do
      described_class.send_password_reset(user: romanian_user, reset_url: reset_url)

      expect(WebMock).to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
    end

    it 'sends with the correct template ID' do
      described_class.send_password_reset(user: romanian_user, reset_url: reset_url)

      expect(WebMock).to(have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
        .with { |req| JSON.parse(req.body)['template_id'] == 'd-952a77f57d9f410597cfa1cf84260cef' })
    end

    it 'sets is_romanian to true for a Romanian user' do
      described_class.send_password_reset(user: romanian_user, reset_url: reset_url)

      expect(WebMock).to(have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
        .with { |req| JSON.parse(req.body).dig('personalizations', 0, 'dynamic_template_data', 'is_romanian') == true })
    end

    it 'sets is_romanian to false for a non-Romanian user' do
      described_class.send_password_reset(user: english_user, reset_url: reset_url)

      expect(WebMock).to(have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
        .with { |req| JSON.parse(req.body).dig('personalizations', 0, 'dynamic_template_data', 'is_romanian') == false })
    end

    it 'sends first_name and reset_url in dynamic template data' do
      described_class.send_password_reset(user: romanian_user, reset_url: reset_url)

      dtd = ->(req) { JSON.parse(req.body).dig('personalizations', 0, 'dynamic_template_data') }
      expect(WebMock).to(have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
        .with { |req| dtd.call(req)['first_name'] == 'Ion' && dtd.call(req)['reset_url'] == reset_url })
    end

    it 'includes the current year as a string in dynamic template data' do
      described_class.send_password_reset(user: romanian_user, reset_url: reset_url)

      expect(WebMock).to(have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
        .with { |req| JSON.parse(req.body).dig('personalizations', 0, 'dynamic_template_data', 'year') == Time.current.year.to_s })
    end
  end

  describe '.send_booking_confirmation' do
    let(:language_code) { 'ro-RO' }
    let(:event) do
      create(:event,
             slug: 'conf-2026',
             start_date: Time.zone.parse('2026-06-18 10:00:00'),
             end_date: Time.zone.parse('2026-06-20 18:00:00'),
             location_name: 'Casa Tâmplarului')
    end
    let(:ticket) { create(:ticket, event: event) }
    let(:order) { create(:order) }

    before do
      Language.find_or_create_by!(code: language_code) { |l| l.name = 'Romanian' }
      create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Conferința 2026')
      create(:tickets_translation, tickets_id: ticket.id, languages_code: 'ro-RO', name: 'Adult')
      stub_request(:post, 'https://api.sendgrid.com/v3/mail/send')
        .to_return(status: 202, body: '', headers: {})
    end

    context 'with a single attendee' do
      before do
        create(:attendee, event: event, order: order, ticket: ticket,
                          email_address: 'ion@example.com', first_name: 'Ion', last_name: 'Popescu')
      end

      it 'posts to the SendGrid mail/send endpoint' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        expect(WebMock).to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send').once
      end

      it 'uses the booking confirmation template ID' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        expect(WebMock).to(have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
          .with { |req| JSON.parse(req.body)['template_id'] == SendgridService::BOOKING_CONFIRMATION_TEMPLATE_ID })
      end

      it 'sends to the attendee email address' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        expect(WebMock).to(have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
          .with { |req| JSON.parse(req.body).dig('personalizations', 0, 'to', 0, 'email') == 'ion@example.com' })
      end

      it 'sets is_romanian: true for ro-RO' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        expect(WebMock).to(have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
          .with { |req| JSON.parse(req.body).dig('personalizations', 0, 'dynamic_template_data', 'is_romanian') == true })
      end

      it 'sets is_romanian: false for en-US' do
        described_class.send_booking_confirmation(order: order, language: 'en-US')
        expect(WebMock).to(have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
          .with { |req| JSON.parse(req.body).dig('personalizations', 0, 'dynamic_template_data', 'is_romanian') == false })
      end

      it 'includes order_reference in template data' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        dtd = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
                  .dig('personalizations', 0, 'dynamic_template_data')
        expect(dtd['order_reference']).to eq(order.order_reference)
      end

      it 'includes event_name in template data' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        dtd = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
                  .dig('personalizations', 0, 'dynamic_template_data')
        expect(dtd['event_name']).to eq('Conferința 2026')
      end

      it 'includes event_start_date formatted as day month year' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        dtd = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
                  .dig('personalizations', 0, 'dynamic_template_data')
        expect(dtd['event_start_date']).to eq('18 June 2026')
      end

      it 'includes event_location in template data' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        dtd = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
                  .dig('personalizations', 0, 'dynamic_template_data')
        expect(dtd['event_location']).to eq('Casa Tâmplarului')
      end

      it 'includes attendee first_name, last_name, and ticket_name' do # rubocop:disable RSpec/ExampleLength
        described_class.send_booking_confirmation(order: order, language: language_code)
        attendees_data = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
                             .dig('personalizations', 0, 'dynamic_template_data', 'attendees')
        expect(attendees_data.first).to include(
          'first_name' => 'Ion',
          'last_name' => 'Popescu',
          'ticket_name' => 'Adult'
        )
      end

      it 'attaches the QR code as an inline image with content_id qr_code' do # rubocop:disable RSpec/ExampleLength
        described_class.send_booking_confirmation(order: order, language: language_code)
        attachments = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)['attachments']
        expect(attachments).to be_present
        qr_attachment = attachments.find { |a| a['content_id'] == 'qr_code' }
        expect(qr_attachment).to include(
          'type' => 'image/png',
          'disposition' => 'inline',
          'filename' => 'booking-qr.png'
        )
        expect(qr_attachment['content']).to be_present
      end
    end

    context 'with two attendees sharing the same email' do
      before do
        create(:attendee, event: event, order: order, email_address: 'ion@example.com', first_name: 'Ion')
        create(:attendee, event: event, order: order, email_address: 'ion@example.com', first_name: 'Maria')
      end

      it 'sends only one email' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        expect(WebMock).to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send').once
      end

      it 'includes both attendees in the single email' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        attendees_data = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
                             .dig('personalizations', 0, 'dynamic_template_data', 'attendees')
        expect(attendees_data.length).to eq(2)
      end
    end

    context 'with two attendees having different emails' do
      before do
        create(:attendee, event: event, order: order, email_address: 'ion@example.com',   first_name: 'Ion')
        create(:attendee, event: event, order: order, email_address: 'maria@example.com', first_name: 'Maria')
      end

      it 'sends two separate emails' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        expect(WebMock).to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send').twice
      end
    end

    context 'with an attendee with a blank email' do
      before do
        create(:attendee, event: event, order: order, email_address: nil, first_name: 'Ion')
        create(:attendee, event: event, order: order, email_address: 'maria@example.com', first_name: 'Maria')
      end

      it 'skips the blank-email attendee and sends one email for the other' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        expect(WebMock).to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send').once
      end
    end

    context 'when all attendees have blank emails' do
      before { create(:attendee, event: event, order: order, email_address: nil) }

      it 'sends no emails' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        expect(WebMock).not_to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
      end
    end

    context 'when SendGrid returns an error' do
      before do
        stub_request(:post, 'https://api.sendgrid.com/v3/mail/send')
          .to_return(status: 500, body: 'Internal Server Error', headers: {})
        create(:attendee, event: event, order: order, email_address: 'ion@example.com')
      end

      it 'logs the error and does not raise' do
        allow(Rails.logger).to receive(:error)
        expect { described_class.send_booking_confirmation(order: order, language: language_code) }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(/SendGrid/)
      end
    end

    context 'when a network error occurs' do
      before do
        stub_request(:post, 'https://api.sendgrid.com/v3/mail/send').to_raise(SocketError)
        create(:attendee, event: event, order: order, email_address: 'ion@example.com')
      end

      it 'logs the error and does not raise' do
        allow(Rails.logger).to receive(:error)
        expect { described_class.send_booking_confirmation(order: order, language: language_code) }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(/SendGrid/)
      end
    end
  end
end
