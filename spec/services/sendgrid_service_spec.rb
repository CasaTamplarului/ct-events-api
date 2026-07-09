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

    context 'when DISABLE_EMAILS is set' do
      around do |ex|
        ENV['DISABLE_EMAILS'] = 'true'
        ex.run
        ENV.delete('DISABLE_EMAILS')
      end

      it 'does not send any email' do
        described_class.send_password_reset(user: romanian_user, reset_url: reset_url)
        expect(WebMock).not_to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
      end
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
    let(:ticket) { create(:ticket, event: event, price: 150, food_included: true) }
    let(:order) { create(:order) }

    before do
      Language.find_or_create_by!(code: language_code) { |l| l.name = 'Romanian' }
      create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Conferința 2026')
      create(:tickets_translation, tickets_id: ticket.id, languages_code: 'ro-RO', name: 'Adult',
                                   description: 'Includes all meals')
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

      it 'includes total_price as the sum of ticket prices' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        dtd = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
                  .dig('personalizations', 0, 'dynamic_template_data')
        expect(dtd['total_price']).to eq('150.0')
      end

      it 'sets is_pending: true when payment is pending' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        dtd = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
                  .dig('personalizations', 0, 'dynamic_template_data')
        expect(dtd['is_pending']).to be(true)
      end

      it 'sets is_pending: false when payment is paid' do
        paid_order = create(:order)
        create(:attendee, event: event, order: paid_order, ticket: ticket,
                          email_address: 'paid@example.com', payment_status: :paid)
        described_class.send_booking_confirmation(order: paid_order, language: language_code)
        dtd = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
                  .dig('personalizations', 0, 'dynamic_template_data')
        expect(dtd['is_pending']).to be(false)
      end

      it 'includes attendee fields and qr_content_id in template data' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        attendee = order.attendees.first
        attendees_data = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
                             .dig('personalizations', 0, 'dynamic_template_data', 'attendees')
        expect(attendees_data.first).to include(
          'first_name' => 'Ion',
          'last_name' => 'Popescu',
          'ticket_name' => 'Adult',
          'ticket_description' => 'Includes all meals',
          'ticket_price' => '150.0',
          'food_included' => true,
          'qr_content_id' => "qr_code_#{attendee.id}"
        )
      end

      it 'attaches a per-attendee QR code as an inline image' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        attendee    = order.attendees.first
        attachments = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)['attachments']
        qr_attachment = attachments&.find { |a| a['content_id'] == "qr_code_#{attendee.id}" }
        expect(qr_attachment).to include(
          'type' => 'image/png',
          'disposition' => 'inline',
          'filename' => "qr-#{attendee.id}.png"
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

    context 'when DISABLE_EMAILS is set' do
      around do |ex|
        ENV['DISABLE_EMAILS'] = 'true'
        ex.run
        ENV.delete('DISABLE_EMAILS')
      end

      before { create(:attendee, event: event, order: order, email_address: 'ion@example.com') }

      it 'does not send any email' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        expect(WebMock).not_to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
      end
    end
  end

  describe '.send_broadcast' do
    before do
      stub_request(:post, 'https://api.sendgrid.com/v3/mail/send')
        .to_return(status: 202, body: '', headers: {})
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig)
        .with(:sendgrid, :api_key).and_return('SG.testkey')
      allow(Rails.application.credentials).to receive(:dig)
        .with(:sendgrid, :from_email).and_return('noreply@test.com')
    end

    it 'posts to the SendGrid mail/send endpoint' do
      described_class.send_broadcast(to: 'ion@example.com', subject: 'Test', body_html: '<p>Hi</p>')
      expect(WebMock).to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
    end

    context 'when attachments are provided' do
      let(:encoded_content) { Base64.strict_encode64('PDF content') }
      let(:attachments) do
        [{ content: encoded_content, type: 'application/pdf', filename: 'programme.pdf' }]
      end

      it 'includes the attachment in the request body' do
        described_class.send_broadcast(
          to: 'ion@example.com', subject: 'Test', body_html: '<p>Hi</p>',
          attachments: attachments
        )
        body = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
        att  = body['attachments']&.first
        expect(att).to include(
          'content' => encoded_content,
          'type' => 'application/pdf',
          'filename' => 'programme.pdf',
          'disposition' => 'attachment'
        )
      end
    end

    context 'when attachment_urls are provided' do
      let(:attachment_urls) { [{ 'name' => 'programme.pdf', 'url' => 'https://directus.example.com/assets/abc' }] }

      it 'appends a download links block to body_html' do
        described_class.send_broadcast(
          to: 'ion@example.com', subject: 'Test', body_html: '<p>Hi</p>',
          attachment_urls: attachment_urls
        )
        body = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
        body_html = body.dig('personalizations', 0, 'dynamic_template_data', 'body_html')
        expect(body_html).to include('<p>Hi</p>')
        expect(body_html).to include('https://directus.example.com/assets/abc')
        expect(body_html).to include('programme.pdf')
      end
    end

    context 'when attachment_urls is empty' do
      it 'does not append a download links block' do
        described_class.send_broadcast(
          to: 'ion@example.com', subject: 'Test', body_html: '<p>Hi</p>',
          attachment_urls: []
        )
        body      = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
        body_html = body.dig('personalizations', 0, 'dynamic_template_data', 'body_html')
        expect(body_html).to eq('<p>Hi</p>')
      end
    end
  end
end
