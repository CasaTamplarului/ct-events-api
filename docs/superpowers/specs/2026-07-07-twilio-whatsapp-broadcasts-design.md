# Twilio WhatsApp Broadcasts Design

## Goal

Admin-only endpoint to send custom WhatsApp utility messages (via Twilio content templates) to registered users and/or event attendees, with per-recipient variable substitution and full broadcast tracking.

## Architecture

Mirrors the existing email broadcast system. Three new DB tables (`whatsapp_templates`, `whatsapp_broadcasts`, `whatsapp_broadcast_recipients`), a `TwilioService` wrapper, a `SendWhatsappJob` background job, and two new admin controllers. The `twilio-ruby` gem handles the API calls.

**Tech stack:** Rails 7.1, Solid Queue, twilio-ruby gem, PostgreSQL.

---

## Database Schema

### `whatsapp_templates`

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint PK | |
| `name` | string, not null | Human label, e.g. "Event Reminder" |
| `content_sid` | string, not null | Twilio content SID (HXxxx) |
| `variables` | jsonb, default `[]` | Ordered variable definitions — see below |
| `created_at` | datetime | |
| `updated_at` | datetime | |

`variables` format — positional, matching Twilio's `{{1}}` `{{2}}` placeholder numbering:
```json
[
  {"position": 1, "name": "first_name"},
  {"position": 2, "name": "event_name"},
  {"position": 3, "name": "order_reference"}
]
```

`name` must be a key from the recipient variable pool (see below).

### `whatsapp_broadcasts`

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint PK | |
| `whatsapp_template_id` | bigint FK, not null | |
| `event_id` | bigint FK, nullable | Scopes recipients to one event |
| `sent_by_user_id` | bigint FK, not null | Admin who triggered the send |
| `recipient_count` | integer, default 0 | Updated after job completes |
| `created_at` | datetime | |
| `updated_at` | datetime | |

### `whatsapp_broadcast_recipients`

| Column | Type | Notes |
|--------|------|-------|
| `whatsapp_broadcast_id` | bigint FK, not null | |
| `user_id` | bigint FK, nullable | Null for unregistered attendees |
| `phone_number` | string, not null | Normalised E.164 |

Unique index: `(whatsapp_broadcast_id, LOWER(phone_number))` — prevents duplicate sends per broadcast.
No surrogate PK (composite only).

---

## Recipient Variable Pool

Same as email, plus `phone_number`:

| Key | Source |
|-----|--------|
| `first_name` | `user.first_name` / `attendee.first_name` |
| `last_name` | `user.last_name` / `attendee.last_name` |
| `email` | `user.email` / `attendee.email_address` |
| `phone_number` | `user.phone_number` / `attendee.phone_number` |
| `event_name` | `event.events_translations` where `languages_code = 'ro-RO'` |
| `order_reference` | first non-cancelled attendee order for the event |

---

## Recipient Targeting

Identical logic to `SendEmailsJob`:

1. **Registered users** — `User.active.where.not(phone_number: [nil, ''])`. Optionally filtered to attendees of `event_id`. Skips users in `exclude_broadcast_ids` recipient sets.
2. **Unregistered attendees** — only when `event_id` present. `Attendee` rows where `user_id IS NULL`, `phone_number` present, not cancelled. Deduped by `DISTINCT ON (LOWER(phone_number))`.
3. **Deduplication** — a `Set` of already-sent phone numbers is maintained in-memory across both passes to prevent duplicates within one broadcast.
4. **Test send** — if `to:` is present in the request, send to that single number with static variable values provided in the request. No tracking, no job.

No WhatsApp notification preference column — utility messages are sent to anyone with a phone number on file. (A preference toggle can be added later if needed.)

---

## Service: `TwilioService`

`app/services/twilio_service.rb`

```ruby
WHATSAPP_PREFIX = 'whatsapp:'

def self.send_whatsapp(to:, content_sid:, content_variables:)
  # Guard: DISABLE_EMAILS (reuse existing flag) or missing credentials
  # Build Twilio message with content_sid + content_variables (hash {"1"=>"value", ...})
  # Log errors on non-2xx; do not raise (job continues to next recipient)
end
```

Credentials path: `Rails.application.credentials.dig(:twilio, :account_sid / :auth_token / :whatsapp_from)`.

`whatsapp_from` is the Twilio-registered sender number, prefixed with `whatsapp:` (e.g. `whatsapp:+14155238886`).

Recipient `to` is prefixed: `"whatsapp:#{phone_number}"`.

---

## Job: `SendWhatsappJob`

`app/jobs/send_whatsapp_job.rb`

Parameters: `template_id:`, `user_ids:`, `broadcast_id:`, `event_id: nil`, `exclude_broadcast_ids: nil`

Steps:
1. Load template + variables definition.
2. Build `order_refs` map (same as email job).
3. Build `excluded_phones` Set from `exclude_broadcast_ids`.
4. Iterate `User.where(id: user_ids).where.not(phone_number: [nil, ''])` — substitute variables, call `TwilioService.send_whatsapp`, record to `sent_recipients`.
5. If `event_id` present, iterate unregistered attendees — same dedup logic as email.
6. `insert_all` recipients into `whatsapp_broadcast_recipients`, update `recipient_count`.

---

## Controllers

### `Api::V1::Admin::WhatsappTemplatesController`

Requires `can_send_whatsapp` permission.

| Action | Route | Notes |
|--------|-------|-------|
| `index` | `GET /api/v1/admin/whatsapp_templates` | Returns all templates (id, name, content_sid, variables) |
| `create` | `POST /api/v1/admin/whatsapp_templates` | Params: name, content_sid, variables (array) |

### `Api::V1::Admin::WhatsappBroadcastsController`

Requires `can_send_whatsapp` permission.

| Action | Route | Notes |
|--------|-------|-------|
| `index` | `GET /api/v1/admin/whatsapp_broadcasts` | Last 50 broadcasts, includes template name + event name |
| `create` | `POST /api/v1/admin/whatsapp_broadcasts` | Send or test-send — see params below |

**`create` params:**

| Param | Required | Notes |
|-------|----------|-------|
| `template_id` | yes | ID of a saved `WhatsappTemplate` |
| `event_id` | no | Scope to event attendees |
| `to` | no | If present → test send (single number, static `variables` hash) |
| `variables` | only for test | `{first_name: "Ion", event_name: "Fara Regrete"}` |
| `exclude_broadcast_ids` | no | Array of broadcast IDs to exclude prior recipients |

**Response (bulk send):**
```json
{"broadcast_id": 3, "queued_for": 47}
```

**Response (test send):**
```json
{"sent_to": 1}
```

---

## Permissions

`user.rb` — add to `ROLE_PERMISSIONS`:
```ruby
can_send_whatsapp: true   # admin
can_send_whatsapp: false  # volunteer, attendee, leader, staff
```

---

## Credentials (Rails encrypted)

```yaml
twilio:
  account_sid: ACxxx
  auth_token: xxx
  whatsapp_from: "whatsapp:+40xxxxxxxxx"
```

---

## Files Created / Modified

| File | Action |
|------|--------|
| `Gemfile` | Add `gem 'twilio-ruby'` |
| `db/migrate/YYYYMMDDHHMMSS_create_whatsapp_tables.rb` | Creates all 3 tables + indexes |
| `app/models/whatsapp_template.rb` | New model |
| `app/models/whatsapp_broadcast.rb` | New model |
| `app/models/whatsapp_broadcast_recipient.rb` | New model (no PK) |
| `app/services/twilio_service.rb` | New service |
| `app/jobs/send_whatsapp_job.rb` | New job |
| `app/controllers/api/v1/admin/whatsapp_templates_controller.rb` | New controller |
| `app/controllers/api/v1/admin/whatsapp_broadcasts_controller.rb` | New controller |
| `app/models/user.rb` | Add `can_send_whatsapp` to `ROLE_PERMISSIONS` |
| `config/routes.rb` | Add `resources :whatsapp_templates` + `resources :whatsapp_broadcasts` under `admin` namespace |

---

## Error Handling

- Missing template → 404
- Twilio send failure for one recipient → log error, continue to next recipient (do not abort job)
- Invalid phone number format → skip silently (Twilio will reject malformed numbers)
- Test send with blank `to` → 400 bad request
