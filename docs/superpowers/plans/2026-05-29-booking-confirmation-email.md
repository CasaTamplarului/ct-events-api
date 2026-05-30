# Booking Confirmation Email Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Send a booking confirmation email with a QR code to each unique attendee email address immediately after an order is created, grouping multiple attendees sharing the same email into one email.

**Architecture:** `SendgridService.send_booking_confirmation(order:, language:)` mirrors `send_password_reset` — builds a SendGrid dynamic template mail per unique email address, attaches the QR code (generated with `rqrcode`) as an inline CID image, and swallows exceptions internally so email failures never break order creation. `OrdersController#create` calls it after `persist_order` and before `render`.

**Tech Stack:** Rails 8.1, `sendgrid-ruby` (already present), `rqrcode` gem (to add), RSpec.

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `Gemfile` | Modify | Add `gem 'rqrcode'` |
| `app/services/sendgrid_service.rb` | Modify | Add `BOOKING_CONFIRMATION_TEMPLATE_ID` constant and `send_booking_confirmation` class method |
| `spec/services/sendgrid_service_spec.rb` | Modify | Add unit tests for `send_booking_confirmation` |
| `app/controllers/api/v1/orders_controller.rb` | Modify | Call `send_booking_confirmation` after `persist_order` |
| `spec/requests/api/v1/orders_spec.rb` | Modify | Add test that email is sent on successful order creation |

---

### Task 1: rqrcode gem + SendgridService.send_booking_confirmation + unit tests

**Files:**
- Modify: `Gemfile`
- Modify: `app/services/sendgrid_service.rb`
- Modify: `spec/services/sendgrid_service_spec.rb`

- [ ] **Step 1: Add `rqrcode` to `Gemfile`**

Add after the `sendgrid-ruby` line:

```ruby
gem 'rqrcode'
```

- [ ] **Step 2: Install the gem**

```bash
bundle install
```

Expected: `rqrcode` and its dependency `chunky_png` installed.

- [ ] **Step 3: Add tests to `spec/services/sendgrid_service_spec.rb`**

Append a new `describe '.send_booking_confirmation'` block at the end of the file, before the final `end`:

```ruby
  describe '.send_booking_confirmation' do
    let(:language_code) { 'ro-RO' }
    let!(:language)     { Language.find_or_create_by!(code: language_code) { |l| l.name = 'Romanian' } }

    let(:event) do
      create(:event,
             slug: 'conf-2026',
             start_date: Time.zone.parse('2026-06-18 10:00:00'),
             end_date:   Time.zone.parse('2026-06-20 18:00:00'),
             location_name: 'Casa Tâmplarului')
    end
    let!(:event_translation) do
      create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Conferința 2026')
    end
    let(:ticket)             { create(:ticket, event: event) }
    let!(:ticket_translation) { create(:tickets_translation, tickets_id: ticket.id, languages_code: 'ro-RO', name: 'Adult') }
    let(:order)              { create(:order) }

    before do
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
        dtd = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.last.body)
                  .dig('personalizations', 0, 'dynamic_template_data')
        expect(dtd['order_reference']).to eq(order.order_reference)
      end

      it 'includes event_name in template data' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        dtd = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.last.body)
                  .dig('personalizations', 0, 'dynamic_template_data')
        expect(dtd['event_name']).to eq('Conferința 2026')
      end

      it 'includes event_start_date formatted as day month year' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        dtd = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.last.body)
                  .dig('personalizations', 0, 'dynamic_template_data')
        expect(dtd['event_start_date']).to eq('18 June 2026')
      end

      it 'includes event_location in template data' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        dtd = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.last.body)
                  .dig('personalizations', 0, 'dynamic_template_data')
        expect(dtd['event_location']).to eq('Casa Tâmplarului')
      end

      it 'includes attendee first_name, last_name, and ticket_name' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        attendees_data = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.last.body)
                             .dig('personalizations', 0, 'dynamic_template_data', 'attendees')
        expect(attendees_data.first).to include(
          'first_name' => 'Ion',
          'last_name'  => 'Popescu',
          'ticket_name' => 'Adult'
        )
      end

      it 'attaches the QR code as an inline image with content_id qr_code' do
        described_class.send_booking_confirmation(order: order, language: language_code)
        attachments = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.last.body)['attachments']
        expect(attachments).to be_present
        qr_attachment = attachments.find { |a| a['content_id'] == 'qr_code' }
        expect(qr_attachment).to include(
          'type'        => 'image/png',
          'disposition' => 'inline',
          'filename'    => 'booking-qr.png'
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
        attendees_data = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.last.body)
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
        create(:attendee, event: event, order: order, email_address: nil,              first_name: 'Ion')
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
        expect(Rails.logger).to receive(:error).with(/SendGrid/)
        expect { described_class.send_booking_confirmation(order: order, language: language_code) }.not_to raise_error
      end
    end

    context 'when a network error occurs' do
      before do
        stub_request(:post, 'https://api.sendgrid.com/v3/mail/send').to_raise(SocketError)
        create(:attendee, event: event, order: order, email_address: 'ion@example.com')
      end

      it 'logs the error and does not raise' do
        expect(Rails.logger).to receive(:error).with(/SendGrid/)
        expect { described_class.send_booking_confirmation(order: order, language: language_code) }.not_to raise_error
      end
    end
  end
```

- [ ] **Step 4: Run the spec to confirm it fails**

```bash
bundle exec rspec spec/services/sendgrid_service_spec.rb --format documentation 2>&1 | grep -A 2 "booking_confirmation\|send_booking"
```

Expected: `NoMethodError` — `undefined method 'send_booking_confirmation'`

- [ ] **Step 5: Implement `send_booking_confirmation` in `app/services/sendgrid_service.rb`**

Replace the entire file with:

```ruby
# frozen_string_literal: true

require 'rqrcode'

class SendgridService
  RESET_PASSWORD_TEMPLATE_ID       = 'd-952a77f57d9f410597cfa1cf84260cef'
  BOOKING_CONFIRMATION_TEMPLATE_ID = 'd-PLACEHOLDER'

  def self.send_password_reset(user:, reset_url:)
    mail = SendGrid::Mail.new
    from_email = Rails.application.credentials.dig(:sendgrid, :from_email) || 'noreply@example.com'
    mail.from = SendGrid::Email.new(email: from_email)
    mail.template_id = RESET_PASSWORD_TEMPLATE_ID

    personalization = SendGrid::Personalization.new
    personalization.add_to(SendGrid::Email.new(email: user.email))
    personalization.add_dynamic_template_data(
      'is_romanian' => user.language&.start_with?('ro') || false,
      'first_name' => user.first_name,
      'reset_url' => reset_url,
      'year' => Time.current.year.to_s
    )
    mail.add_personalization(personalization)

    client = SendGrid::API.new(api_key: Rails.application.credentials.dig(:sendgrid, :api_key))
    response = client.client.mail._('send').post(request_body: mail.to_json)
    unless response.status_code.to_i.between?(200, 299)
      Rails.logger.error("SendGrid error: #{response.status_code} #{response.body}")
    end
  end

  def self.send_booking_confirmation(order:, language:)
    attendees = order.attendees
                     .includes({ ticket: :tickets_translations }, { event: :events_translations })
                     .reject { |a| a.email_address.blank? }

    return if attendees.empty?

    qr     = RQRCode::QRCode.new(order.order_reference)
    png    = qr.as_png(size: 300, border_modules: 4)
    qr_b64 = Base64.strict_encode64(png.to_s)

    from_email = Rails.application.credentials.dig(:sendgrid, :from_email) || 'noreply@example.com'
    client     = SendGrid::API.new(api_key: Rails.application.credentials.dig(:sendgrid, :api_key))

    attendees.group_by(&:email_address).each do |email_address, group|
      send_confirmation_to(
        email_address: email_address,
        group:         group,
        order:         order,
        language:      language.to_s,
        qr_b64:        qr_b64,
        from_email:    from_email,
        client:        client
      )
    end
  rescue StandardError => e
    Rails.logger.error("SendGrid booking confirmation error: #{e.message}")
  end

  class << self
    private

      def send_confirmation_to(email_address:, group:, order:, language:, qr_b64:, from_email:, client:) # rubocop:disable Metrics/ParameterLists
        event      = group.first.event
        event_name = event.events_translations.find { |t| t.languages_code == language }&.name ||
                     event.events_translations.find { |t| t.languages_code == 'ro-RO' }&.name

        mail = SendGrid::Mail.new
        mail.from        = SendGrid::Email.new(email: from_email)
        mail.template_id = BOOKING_CONFIRMATION_TEMPLATE_ID

        personalization = SendGrid::Personalization.new
        personalization.add_to(SendGrid::Email.new(email: email_address))
        personalization.add_dynamic_template_data(
          'is_romanian'      => language.start_with?('ro'),
          'first_name'       => group.first.first_name,
          'order_reference'  => order.order_reference,
          'event_name'       => event_name,
          'event_start_date' => event.start_date.strftime('%-d %B %Y'),
          'event_location'   => event.location_name,
          'attendees'        => group.map { |a| attendee_data(a, language) },
          'year'             => Time.current.year.to_s
        )
        mail.add_personalization(personalization)

        attachment = SendGrid::Attachment.new
        attachment.content     = qr_b64
        attachment.type        = 'image/png'
        attachment.filename    = 'booking-qr.png'
        attachment.disposition = 'inline'
        attachment.content_id  = 'qr_code'
        mail.add_attachment(attachment)

        response = client.client.mail._('send').post(request_body: mail.to_json)
        return if response.status_code.to_i.between?(200, 299)

        Rails.logger.error("SendGrid booking confirmation error: #{response.status_code} #{response.body}")
      end

      def attendee_data(attendee, lang)
        ticket_name = attendee.ticket&.tickets_translations
                               &.find { |t| t.languages_code == lang }&.name ||
                      attendee.ticket&.tickets_translations
                               &.find { |t| t.languages_code == 'ro-RO' }&.name
        {
          'first_name'  => attendee.first_name,
          'last_name'   => attendee.last_name,
          'ticket_name' => ticket_name
        }
      end
  end
end
```

- [ ] **Step 6: Run the spec to confirm it passes**

```bash
bundle exec rspec spec/services/sendgrid_service_spec.rb --format documentation
```

Expected: all examples pass.

- [ ] **Step 7: Run the full suite**

```bash
bundle exec rspec
```

Expected: 0 failures.

- [ ] **Step 8: Run RuboCop**

```bash
bundle exec rubocop app/services/sendgrid_service.rb spec/services/sendgrid_service_spec.rb
```

Fix any offenses.

- [ ] **Step 9: Commit**

```bash
git add Gemfile Gemfile.lock \
        app/services/sendgrid_service.rb \
        spec/services/sendgrid_service_spec.rb
git commit -m "Add SendgridService.send_booking_confirmation with QR code"
```

---

### Task 2: Wire into OrdersController + test + push

**Files:**
- Modify: `app/controllers/api/v1/orders_controller.rb`
- Modify: `spec/requests/api/v1/orders_spec.rb`

- [ ] **Step 1: Add email-sent test to `spec/requests/api/v1/orders_spec.rb`**

Read the existing spec to find the right place. Add this context inside the main `describe` block, alongside the existing success test:

```ruby
  context 'when order is created successfully — email' do
    before do
      stub_request(:post, 'https://api.sendgrid.com/v3/mail/send')
        .to_return(status: 202, body: '', headers: {})
    end

    it 'sends a booking confirmation email' do
      post "/api/v1/#{language_code}/orders",
           params: { items: [valid_item] }.to_json,
           headers: { 'Content-Type' => 'application/json' }

      expect(WebMock).to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send').once
    end

    it 'still creates the order if email fails' do
      stub_request(:post, 'https://api.sendgrid.com/v3/mail/send').to_raise(SocketError)

      expect do
        post "/api/v1/#{language_code}/orders",
             params: { items: [valid_item] }.to_json,
             headers: { 'Content-Type' => 'application/json' }
      end.to change(Order, :count).by(1)

      expect(response).to have_http_status(:created)
    end
  end
```

- [ ] **Step 2: Run the new tests to confirm they fail**

```bash
bundle exec rspec spec/requests/api/v1/orders_spec.rb --format documentation 2>&1 | grep -A 2 "email"
```

Expected: `WebMock::NetConnectNotAllowedError` or the assertion fails because no email is sent yet.

- [ ] **Step 3: Update `app/controllers/api/v1/orders_controller.rb`**

Find the `create` action. Change:

```ruby
        order = persist_order(resolved)

        render json: { order_reference: order.order_reference }, status: :created
```

To:

```ruby
        order = persist_order(resolved)
        SendgridService.send_booking_confirmation(order: order, language: params[:languages_code])
        render json: { order_reference: order.order_reference }, status: :created
```

- [ ] **Step 4: Run the orders spec to confirm it passes**

```bash
bundle exec rspec spec/requests/api/v1/orders_spec.rb --format documentation
```

Expected: all examples pass (including the new email tests).

- [ ] **Step 5: Run the full suite**

```bash
bundle exec rspec
```

Expected: 0 failures.

- [ ] **Step 6: Run RuboCop**

```bash
bundle exec rubocop app/controllers/api/v1/orders_controller.rb \
                    spec/requests/api/v1/orders_spec.rb
```

Fix any offenses.

- [ ] **Step 7: Commit and push**

```bash
git add app/controllers/api/v1/orders_controller.rb \
        spec/requests/api/v1/orders_spec.rb
git commit -m "Send booking confirmation email after order creation"
git push origin main
```
