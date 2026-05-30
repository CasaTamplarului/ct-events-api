# Booking Check Design

**Goal:** A single authenticated endpoint that tells the FE whether the current user already has a booking for one or more events, so a warning can be shown at checkout before they accidentally double-book.

**Architecture:** `POST /api/v1/auth/me/bookings/check` accepts an array of event slugs and returns a map of slug → `{ has_booking, order_reference }`. A single DB query joins events → attendees filtered by user and payment status. New `check` action added to the existing `Api::V1::Auth::Me::BookingsController`.

**Tech Stack:** Rails 8.1, PostgreSQL.

---

## Endpoint

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| `POST` | `/api/v1/auth/me/bookings/check` | JWT | Check if user has bookings for given event slugs |

---

## Request

```json
{ "slugs": ["conferinta-2026", "tabara-copii", "concert-worship"] }
```

| Field | Type | Required |
|-------|------|----------|
| `slugs` | array of strings | Yes — event slugs to check |

---

## Response — 200 OK

A map keyed by slug. Every slug in the request appears in the response.

```json
{
  "conferinta-2026": { "has_booking": true,  "order_reference": "CT-2026-00042" },
  "tabara-copii":    { "has_booking": false, "order_reference": null },
  "concert-worship": { "has_booking": false, "order_reference": null }
}
```

| Field | Notes |
|-------|-------|
| `has_booking` | `true` if user has an attendee on that event with `paid` or `payment_pending` status |
| `order_reference` | The order reference string when `has_booking` is `true`; `null` otherwise. Use to deep-link to the existing booking. |

Slugs that don't match any event in the DB return `has_booking: false, order_reference: null` — not an error.

---

## Error Responses

| Status | Body | When |
|--------|------|------|
| `401` | `{ "error": "Unauthorized" }` | No JWT or invalid JWT |
| `422` | `{ "error": "slugs is required" }` | `slugs` param missing or blank |

---

## Query

Single query — no N+1:

```ruby
Attendee
  .joins(:event, :order)
  .where(user_id: current_user.id)
  .where(payment_status: %i[paid payment_pending])
  .where(events: { slug: slugs })
  .select('attendees.*, events.slug AS event_slug, orders.order_reference')
```

Build the result map in Ruby: start with all slugs defaulted to `{ has_booking: false, order_reference: nil }`, then overwrite with matches from the query.

---

## Route

Add to the existing `scope '/me/bookings'` in `config/routes.rb`:

```ruby
post :check, to: 'me/bookings#check'
```

Produces: `POST /api/v1/auth/me/bookings/check`

---

## Controller

New `check` action in `app/controllers/api/v1/auth/me/bookings_controller.rb`:

```ruby
def check
  slugs = params[:slugs]
  if slugs.blank?
    render json: { error: I18n.t('auth.errors.slugs_required') }, status: :unprocessable_content
    return
  end

  result = slugs.index_with { { has_booking: false, order_reference: nil } }

  Attendee
    .joins(:event, :order)
    .where(user_id: current_user.id)
    .where(payment_status: %i[paid payment_pending])
    .where(events: { slug: slugs })
    .select('attendees.id, events.slug AS event_slug, orders.order_reference')
    .each do |row|
      result[row.event_slug] = { has_booking: true, order_reference: row.order_reference }
    end

  render json: result
end
```

---

## i18n

Add to `en.yml` under `auth.errors:`:
```yaml
slugs_required: "slugs is required"
```

Add to `ro.yml` under `auth.errors:`:
```yaml
slugs_required: "slugs este obligatoriu"
```

---

## Testing

`spec/requests/api/v1/auth/me/bookings_spec.rb` — new `describe 'POST /api/v1/auth/me/bookings/check'` block:

- Returns map with `has_booking: true` + `order_reference` for a `paid` attendee
- Returns map with `has_booking: true` + `order_reference` for a `payment_pending` attendee
- Returns `has_booking: false` for a `refunded` attendee
- Returns `has_booking: false` for an event the user has no booking for
- Unknown slug → `has_booking: false, order_reference: null`
- Multiple slugs in one call — correct result for each
- Missing `slugs` param → 422
- No JWT → 401

---

## Notes

- If a user has multiple attendees on the same event (unusual but possible), only one result row is returned — the first match. This is acceptable since the `order_reference` is what the FE needs to deep-link.
- The endpoint does not check event status (live/draft/cancelled) — if the user booked it and the status changed, they should still be warned.
