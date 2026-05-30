# Email Preferences Design

**Goal:** Give users control over which emails they receive, with marketing consent captured at signup, per-category toggles in settings, and per-type tokenised unsubscribe links in email footers.

---

## Email Categories

### Transactional — always sent, no user toggle
- Booking confirmation
- Password reset
- Event cancellation / significant changes

### Toggleable — user can enable/disable in settings
- Payment reminders (`payment_reminder_emails`)
- Payment receipts (`payment_receipt_emails`)
- Event reminders (`event_reminder_emails`)
- Event updates (`event_update_emails`)
- Marketing / promotional (`marketing_emails`)

---

## Data Model

Five boolean columns added to the `users` table, all defaulting to `false`:

| Column | Default | Note |
|---|---|---|
| `marketing_emails` | `false` | Set at signup via explicit opt-in checkbox |
| `payment_reminder_emails` | `false` | |
| `payment_receipt_emails` | `false` | |
| `event_reminder_emails` | `false` | |
| `event_update_emails` | `false` | |

Existing users are backfilled to `false` via migration default. Transactional email types have no column — they are always sent regardless of preferences.

---

## API Endpoints

### `PATCH /api/v1/auth/me/email_preferences` — authenticated

Updates any combination of the 5 toggleable preferences. Added as a member action on the existing `me` resource.

**Request body:**
```json
{
  "marketing_emails": true,
  "event_reminder_emails": false
}
```

**Response `200`:**
```json
{
  "email_preferences": {
    "marketing_emails": true,
    "payment_reminder_emails": false,
    "payment_receipt_emails": false,
    "event_reminder_emails": false,
    "event_update_emails": false
  }
}
```

Only the 5 known preference fields are permitted; any extra params are ignored.

---

### `GET /api/v1/unsubscribe?token=xxx` — public, no auth

Processes a per-type unsubscribe link clicked from an email footer. Validates the signed token, sets the matching preference to `false`, then redirects to the frontend.

- **Success:** `302` → `${FRONTEND_URL}/unsubscribed?type=marketing_emails`
- **Invalid token:** `302` → `${FRONTEND_URL}/unsubscribed?error=invalid_token`
- Idempotent — unsubscribing when already `false` is a no-op, same success redirect.

---

### `GET /api/v1/auth/me` — existing, extended

The `email_preferences` object is added to the existing `user_json` response so the settings page can render the current state without an extra request:

```json
{
  "id": 1,
  "first_name": "...",
  "email_preferences": {
    "marketing_emails": false,
    "payment_reminder_emails": false,
    "payment_receipt_emails": false,
    "event_reminder_emails": false,
    "event_update_emails": false
  }
}
```

---

## Signup Behaviour

### Email/password (`RegistrationsController#create`)

Accepts an optional `marketing_emails` boolean param. If `true`, the user is created with `marketing_emails: true`. If absent or `false`, it defaults to `false`. All other preferences default to `false`.

### OAuth signups (Google, Facebook, Apple, Microsoft)

All users created via OAuth start with all preferences `false`. Marketing consent is collected in a post-OAuth onboarding step (separate scope) via `PATCH /api/v1/auth/me/email_preferences`.

---

## Unsubscribe Tokens

Tokens are generated using `Rails.application.message_verifier(:email_unsubscribe)` — a namespaced verifier backed by `secret_key_base`. No expiry is set; tokens remain valid indefinitely.

**Payload:** `{ user_id: 123, type: "marketing_emails" }`

**Generation (in `SendgridService`):**
```ruby
token = Rails.application.message_verifier(:email_unsubscribe)
              .generate({ user_id: user.id, type: "marketing_emails" })
unsubscribe_url = "#{ENV['API_URL']}/api/v1/unsubscribe?token=#{token}"
```

Each email type passes its own `type` string, so each token is scoped to that category. The `unsubscribe_url` is injected into the SendGrid template data and rendered as a footer link in the template.

---

## SendGrid Integration

Every non-transactional email method in `SendgridService` checks the relevant preference before sending:

```ruby
def self.send_payment_reminder(user:, ...)
  return unless user.payment_reminder_emails
  return unless emails_enabled?
  # ... build and send
end
```

Guard clause comes first, then `emails_enabled?`, then send logic. Transactional methods (`send_booking_confirmation`, `send_password_reset`) have no preference guard.

Emails addressed to attendee email addresses rather than a registered `User` (e.g. booking confirmation) are not subject to preference checks — those are always transactional.

---

## New Environment Variable

| Variable | Purpose |
|---|---|
| `API_URL` | Base URL of this API, used to build unsubscribe links (e.g. `https://api.casatamplarului.ro`) |
| `FRONTEND_URL` | Already present — redirect target after unsubscribe |

---

## Testing

### `spec/models/user_spec.rb`
- All 5 preference columns default to `false` on a new user.

### `spec/requests/api/v1/auth/me/email_preferences_spec.rb` (new)
- PATCH with valid JWT updates specified preferences, returns updated `email_preferences`.
- PATCH with missing/invalid JWT returns `401`.
- Only the 5 known fields are accepted; unknown fields are ignored.
- Partial update — only provided fields change, others unchanged.

### `spec/requests/api/v1/unsubscribe_spec.rb` (new)
- Valid token for `marketing_emails` → sets `marketing_emails: false`, redirects with `?type=marketing_emails`.
- Valid token for another type → sets that field, correct redirect.
- Invalid/tampered token → redirects with `?error=invalid_token`.
- Already `false` (idempotent) → same success redirect.

### `spec/requests/api/v1/auth/registrations_spec.rb` (extend)
- `marketing_emails: true` at signup → user created with `marketing_emails: true`.
- `marketing_emails` absent → user created with `marketing_emails: false`.

### `spec/services/sendgrid_service_spec.rb` (extend, per new email method)
- User with preference `false` → method returns without posting to SendGrid.
- User with preference `true` → posts to SendGrid.
- Template data includes `unsubscribe_url` containing a valid signed token of the correct type.
