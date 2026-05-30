# User Bookings Design

**Goal:** Two authenticated endpoints that return a signed-in user's bookings split into upcoming and past, each booking containing the order reference (used by the FE to render a QR code for check-in).

**Architecture:** A new `Api::V1::Auth::Me::BookingsController` with `upcoming` and `past` actions, nested under the existing `resource :me` route. Queries join `orders → attendees → events` filtered by `attendee.user_id`. Event name and ticket name are translated using the user's language preference. No new gems, no QR generation on the backend — the FE receives `order_reference` and renders the QR code client-side.

**Tech Stack:** Rails 8.1, PostgreSQL, existing `Authenticatable` concern.

---

## Endpoints

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| `GET` | `/api/v1/auth/me/bookings/upcoming` | JWT | Orders where the event hasn't started yet, ASC by start_date |
| `GET` | `/api/v1/auth/me/bookings/past` | JWT | Orders where the event has ended, DESC by start_date |

All payment statuses (`paid`, `payment_pending`, `refunded`) are included in both lists.

---

## Routes

```ruby
resource :me, only: %i[show update destroy], controller: 'me' do
  patch :password, on: :member
  scope '/bookings' do
    get :upcoming, to: 'me/bookings#upcoming'
    get :past,     to: 'me/bookings#past'
  end
end
```

---

## Controller

**File:** `app/controllers/api/v1/auth/me/bookings_controller.rb`

```ruby
module Api::V1::Auth::Me
  class BookingsController < ActionController::API
    include Authenticatable
    include LocaleSetter

    before_action :authenticate_user!
    before_action :set_locale

    def upcoming
      render json: bookings_for(scope: :upcoming)
    end

    def past
      render json: bookings_for(scope: :past)
    end
  end
end
```

`bookings_for` is a private method that queries orders, then serialises each into the response shape.

---

## Data Query

### Finding orders

```ruby
# upcoming
Order.joins(attendees: :event)
     .where(attendees: { user_id: current_user.id })
     .where("events.start_date > ?", Time.current)
     .distinct
     .order("events.start_date ASC")

# past
Order.joins(attendees: :event)
     .where(attendees: { user_id: current_user.id })
     .where("events.end_date <= ?", Time.current)
     .distinct
     .order("events.start_date DESC")
```

### Per-order data

For each order, fetch only the attendees belonging to the current user:

```ruby
attendees = order.attendees.where(user_id: current_user.id).includes(:ticket)
event     = attendees.first.event
```

`payment_status` is taken from the first attendee (all attendees in an order share the same status in practice).

---

## Response Shape

```json
[
  {
    "order_reference": "CT-2026-00042",
    "payment_status": "paid",
    "event": {
      "name": "Conferința 2026",
      "slug": "conferinta-2026",
      "start_date": "2026-06-15T10:00:00.000Z",
      "end_date": "2026-06-17T18:00:00.000Z",
      "location_name": "Casa Tâmplarului",
      "address": "Str. Example 1"
    },
    "attendees": [
      {
        "first_name": "Ion",
        "last_name": "Popescu",
        "ticket_name": "Adult",
        "dietary_preference": "no_preference"
      }
    ]
  }
]
```

### Field notes

| Field | Source | Notes |
|-------|--------|-------|
| `order_reference` | `order.order_reference` | FE uses this as QR code value |
| `payment_status` | `attendee.payment_status` | One of `paid`, `payment_pending`, `refunded` |
| `event.name` | `events_translations` filtered by user language | Falls back to `ro-RO` if user has no language set |
| `event.slug` | `events.slug` | Use to deep-link to the event detail page |
| `event.start_date` / `end_date` | `events.start_date` / `end_date` | ISO 8601 UTC |
| `event.location_name` | `events.location_name` | May be nil |
| `event.address` | `events.address` | May be nil |
| `attendees[].ticket_name` | `tickets_translations` filtered by user language | nil if attendee has no ticket assigned |
| `attendees[].dietary_preference` | `attendee.dietary_preference` | Enum string: `no_preference`, `vegetarian`, `vegan` |

### QR Code (FE responsibility)

The `order_reference` string is the QR code payload. The FE renders the QR code client-side using any QR library (e.g. `vue-qrcode`, `qrcode.js`). No image or data URL is returned by the API.

---

## Language Resolution

The user's `language` field (e.g. `"ro-RO"`) is used to look up translations:

```ruby
lang_code = current_user.language || 'ro-RO'
event.translations(lang_code)&.name || event.translations('ro-RO')&.name
```

Same fallback pattern for ticket name.

---

## Error Responses

| Status | When |
|--------|------|
| `401` | No JWT or invalid JWT |

An empty array `[]` is returned (not 404) when the user has no bookings in that category.

---

## Testing

**File:** `spec/requests/api/v1/auth/me/bookings_spec.rb`

### `GET /api/v1/auth/me/bookings/upcoming`

- Returns orders where `events.start_date > now`, ordered ASC by start_date
- Returns empty array when user has no upcoming bookings
- Includes all three payment statuses (`paid`, `payment_pending`, `refunded`)
- Response contains `order_reference`, `payment_status`, `event` fields, `attendees` array
- `event.name` is translated in the user's language
- `attendees` contains only the current user's attendees (not other users' on same order)
- No JWT → 401

### `GET /api/v1/auth/me/bookings/past`

- Returns orders where `events.end_date <= now`, ordered DESC by start_date
- Returns empty array when user has no past bookings
- No JWT → 401

---

## Notes

- The `order_reference` format is `CT-YYYY-NNNNN` (e.g. `CT-2026-00042`), generated automatically on order creation.
- If a user booked before having an account, their attendee records are backfilled with `user_id` at sign-in — bookings made before account creation will appear here automatically.
- No pagination for now — users are unlikely to have enough bookings to need it.
- The check-in scanning flow (staff scanning QR codes to mark attendance) is out of scope and will be a separate spec.
