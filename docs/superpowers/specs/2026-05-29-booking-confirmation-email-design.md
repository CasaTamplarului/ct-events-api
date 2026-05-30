# Booking Confirmation Email Design

**Goal:** Send a booking confirmation email with a QR code to each unique email address in an order, immediately after the order is successfully created.

**Architecture:** `SendgridService.send_booking_confirmation` follows the same pattern as `send_password_reset` — builds a SendGrid dynamic template mail, adds a QR code as an inline CID attachment, and sends it. `OrdersController#create` calls it after `persist_order`, wrapped in `rescue` so email failures never break order creation. Attendees are grouped by `email_address`; one email per unique address, containing only that address's attendees. The `rqrcode` gem generates the QR code PNG.

**Tech Stack:** Rails 8.1, `sendgrid-ruby` gem (already present), `rqrcode` gem (to add), PostgreSQL.

---

## New Gem

Add to `Gemfile`:

```ruby
gem 'rqrcode'
```

`rqrcode` v2+ includes PNG export via its dependency on `chunky_png`. No additional gem needed.

---

## Trigger

In `app/controllers/api/v1/orders_controller.rb`, after `persist_order` succeeds:

```ruby
order = persist_order(resolved)

SendgridService.send_booking_confirmation(
  order:    order,
  language: params[:languages_code]
)

render json: { order_reference: order.order_reference }, status: :created
rescue StandardError
  render json: { error: t('orders.errors.internal_error') }, status: :internal_server_error
```

The `rescue StandardError` already wraps the entire `create` action — email failures are caught here without needing an additional rescue. To prevent an email failure from swallowing the order, the email call is placed before `render` but the rescue handles it gracefully: if `SendgridService` raises, the response becomes a 500. To truly isolate email failures from the response, `send_booking_confirmation` itself rescues internally and logs (see below).

---

## SendgridService

**File:** `app/services/sendgrid_service.rb` (modify — add method and constant)

```ruby
BOOKING_CONFIRMATION_TEMPLATE_ID = 'd-PLACEHOLDER'
```

Replace `d-PLACEHOLDER` with the real template ID once created.

### `send_booking_confirmation(order:, language:)`

1. Load `order.attendees` with ticket translations eager-loaded
2. Skip attendees with blank `email_address`
3. Group remaining attendees by `email_address`
4. Generate one QR code PNG for the order reference (shared across all emails)
5. For each unique email address, build and send a personalised email

**QR code generation:**
```ruby
qr       = RQRCode::QRCode.new(order.order_reference)
png      = qr.as_png(size: 300, border_modules: 4)
qr_b64   = Base64.strict_encode64(png.to_s)
```

**Per-email send:**
```ruby
mail = SendGrid::Mail.new
mail.from        = SendGrid::Email.new(email: from_email)
mail.template_id = BOOKING_CONFIRMATION_TEMPLATE_ID

personalization = SendGrid::Personalization.new
personalization.add_to(SendGrid::Email.new(email: email_address))
event      = attendees_for_email.first.event
lang_code  = language.to_s.split('-').first
event_name = event.translations(language)&.name || event.translations('ro-RO')&.name

personalization.add_dynamic_template_data(
  'is_romanian'      => language.to_s.start_with?('ro'),
  'first_name'       => attendees_for_email.first.first_name,
  'order_reference'  => order.order_reference,
  'event_name'       => event_name,
  'event_start_date' => event.start_date.strftime('%-d %B %Y'),
  'event_location'   => event.location_name,
  'attendees'        => attendees_for_email.map { |a| attendee_data(a, language) },
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
```

**`attendee_data(attendee, language)` returns:**
```ruby
{
  'first_name'  => attendee.first_name,
  'last_name'   => attendee.last_name,
  'ticket_name' => attendee.ticket&.translations(lang_code(language))&.name ||
                   attendee.ticket&.translations('ro-RO')&.name
}
```

**`lang_code(language)`** extracts `"ro"` from `"ro-RO"`.

**Error handling inside the method:**
```ruby
rescue StandardError => e
  Rails.logger.error("SendGrid booking confirmation error: #{e.message}")
```

So an email failure logs but does not propagate to the controller.

---

## Template Data Reference

| Key | Value | Notes |
|-----|-------|-------|
| `is_romanian` | boolean | `true` if `language` starts with `"ro"` |
| `first_name` | string | First attendee's first name for that email address |
| `order_reference` | string | e.g. `"CT-2026-00042"` |
| `attendees` | array | All attendees sharing this email address |
| `attendees[].first_name` | string | |
| `attendees[].last_name` | string | |
| `attendees[].ticket_name` | string or null | Translated ticket name |
| `event_name` | string | Translated event name |
| `event_start_date` | string | Formatted date e.g. `"18 June 2026"` |
| `event_location` | string or null | `location_name` if present |
| `year` | string | Current year, for footer |
| QR code | inline PNG | CID `qr_code` — reference in template as `<img src="cid:qr_code">` |

---

## Skipping Logic

- Attendees with blank `email_address` → skipped entirely (no email sent for them)
- Multiple attendees with the same email → one email, listing all their attendees
- If `order.attendees` is empty → `send_booking_confirmation` is a no-op

---

## Testing

### `spec/services/sendgrid_service_spec.rb` — add `describe '.send_booking_confirmation'`

Stub `https://api.sendgrid.com/v3/mail/send` → 202.

- Posts to the SendGrid endpoint
- Uses the booking confirmation template ID
- Sends one email per unique email address (not one per attendee)
- Two attendees with the same email → one POST
- Two attendees with different emails → two POSTs
- `is_romanian: true` for `ro-RO` language
- `is_romanian: false` for `en-US` language
- `order_reference` in template data
- Attendee with blank email → skipped (no send for that attendee)
- Sends QR code as inline attachment with `content_id: 'qr_code'`
- A SendGrid error → logs the error, does not raise

### `spec/requests/api/v1/orders_spec.rb` (if it exists) or integration note

- Successful order creation → email sent (stub SendGrid)
- Email error → order still created, 201 returned

---

## Notes

- `d-PLACEHOLDER` must be replaced with the real SendGrid template ID before deploying. This is the only change needed once the template is created.
- The QR code encodes `order_reference` (e.g. `"CT-2026-00042"`) — the same value the FE uses for client-side QR rendering.
- The inline CID attachment approach (`cid:qr_code`) is the most email-client-compatible way to embed images in HTML email.
- `rqrcode` v2 generates QR codes at error correction level M by default — suitable for scanning even if partially obscured.
