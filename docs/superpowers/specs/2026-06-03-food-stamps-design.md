# Food Stamp Tracking — Design

**Date:** 2026-06-03
**Status:** Approved

## Overview

Opt-in meal tracking for multi-day events. Kitchen staff scan attendee QR codes to stamp individual meal entitlements. Seconds are tracked by count. Events without meal slots use the existing `food_included` boolean on tickets — behaviour unchanged.

---

## Data Model

### `ticket_meal_slots`

One row per meal entitlement on a ticket. Defined in Directus when creating a ticket.

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint PK | |
| `ticket_id` | bigint FK | → `tickets` |
| `occurs_on` | date | Actual calendar date of the meal |
| `meal_type` | string | Enum: `breakfast \| lunch \| dinner \| snack` — fixed in code, FE translates |
| `sort` | integer | Display order within a day |
| `created_at` | datetime | |
| `updated_at` | datetime | |

### `meal_stamps`

Immutable log — one row per stamp event. Multiple rows per attendee + slot allowed (count = servings).

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint PK | |
| `attendee_id` | bigint FK | → `attendees` |
| `ticket_meal_slot_id` | bigint FK | → `ticket_meal_slots` |
| `stamped_by_user_id` | bigint FK | → `users` (the volunteer/admin who scanned) |
| `created_at` | datetime | Serves as `stamped_at` — no `updated_at` |

### Relationship with existing `food_included`

| State | Behaviour |
|-------|-----------|
| `food_included: false` | No food |
| `food_included: true`, no meal slots | Simple event — food included, no tracking |
| `food_included: true`, has meal slots | Full tracking via stamps |

---

## Models

### `TicketMealSlot`

```ruby
class TicketMealSlot < ApplicationRecord
  MEAL_TYPES = %w[breakfast lunch dinner snack].freeze

  belongs_to :ticket
  has_many :meal_stamps, dependent: :destroy

  validates :occurs_on, :meal_type, presence: true
  validates :meal_type, inclusion: { in: MEAL_TYPES }
end
```

### `MealStamp`

```ruby
class MealStamp < ApplicationRecord
  belongs_to :attendee
  belongs_to :ticket_meal_slot
  belongs_to :stamped_by, class_name: 'User', foreign_key: :stamped_by_user_id

  validates :attendee_id, :ticket_meal_slot_id, :stamped_by_user_id, presence: true
end
```

### `Ticket` additions

```ruby
has_many :ticket_meal_slots, dependent: :destroy
```

### `Attendee` additions

```ruby
has_many :meal_stamps, dependent: :destroy
```

---

## API Endpoints

All endpoints require JWT with `admin` or `volunteer` role (same as existing scan endpoints).

### GET /api/v1/scan/meal_slots

Returns all meal slots for an event on a given date. Deduplicated across tickets (same date + meal_type from different tickets = one entry). Used by kitchen to select the current meal before scanning.

**Query params:** `event_slug` (required), `date` (required, `YYYY-MM-DD`)

**Response 200:**

```json
[
  { "id": 1, "meal_type": "lunch",  "occurs_on": "2026-07-15", "sort": 1 },
  { "id": 2, "meal_type": "dinner", "occurs_on": "2026-07-15", "sort": 2 }
]
```

Returns `[]` when no slots exist for that date. Deduplication: when multiple tickets have a slot for the same date + meal_type, returns the one with the lowest `id`.

### POST /api/v1/scan/meal_stamps

Stamps an attendee for a meal slot. Takes `meal_type` + `occurs_on` (not a slot ID) so the backend can resolve the correct `ticket_meal_slot` for that attendee's specific ticket — avoids ambiguity when multiple tickets share the same date + meal type. Always creates a stamp if the attendee is entitled — returns a warning flag if already stamped (seconds tracking).

**Request body:**

```json
{ "qr_code": "CT-2026-ABC123-42", "meal_type": "lunch", "occurs_on": "2026-07-15" }
```

**Response 200:**

```json
{
  "stamp": {
    "id": 99,
    "stamped_at": "2026-07-15T12:34:00Z",
    "stamped_by": "Ana Ionescu"
  },
  "already_stamped": true,
  "total_stamps": 2,
  "attendee": { "id": 42, "first_name": "Ion", "last_name": "Popescu" }
}
```

**Error responses:**

| Scenario | Status | Body |
|----------|--------|------|
| QR code not found | 404 | `{ "error": "Not found" }` |
| Attendee's ticket has no slot for this meal_type + date | 422 | `{ "error": "Not entitled" }` |
| Missing or invalid params | 422 | `{ "error": "..." }` |
| Unauthenticated | 401 | |
| Insufficient role | 403 | |

---

## Changes to Existing Endpoints

### GET /api/v1/scan/orders/:order_reference

Each attendee in the response gains a `meal_slots` array showing entitlements and stamp counts:

```json
{
  "order_reference": "CT-2026-ABC123",
  "attendees": [
    {
      "id": 42,
      "first_name": "Ion",
      "last_name": "Popescu",
      "meal_slots": [
        { "id": 1, "meal_type": "lunch",  "occurs_on": "2026-07-15", "sort": 1, "stamp_count": 1 },
        { "id": 2, "meal_type": "dinner", "occurs_on": "2026-07-15", "sort": 2, "stamp_count": 0 }
      ]
    }
  ]
}
```

- `stamp_count: 0` — not yet received
- `stamp_count: 1` — received once
- `stamp_count: 2+` — had seconds
- Attendees on tickets with no meal slots receive `meal_slots: []`

### GET /api/v1/scan/events

Each event gains a `has_meal_tracking` boolean — `true` if any ticket on the event has at least one meal slot. Used by the FE to decide whether to show the food stamp UI.

```json
[
  { "name": "Tabăra 2026", "slug": "tabara-2026", "has_meal_tracking": true },
  { "name": "Concert 2026", "slug": "concert-2026", "has_meal_tracking": false }
]
```

---

## Testing

### Models
- `TicketMealSlot` validates `occurs_on` and `meal_type` presence; rejects unknown meal types
- `MealStamp` validates all FK presence; allows duplicate attendee + slot (no uniqueness constraint)

### POST /api/v1/scan/meal_stamps
- First stamp (qr_code + meal_type + occurs_on) → `already_stamped: false`, `total_stamps: 1`
- Second stamp same params → `already_stamped: true`, `total_stamps: 2`
- Attendee's ticket has no slot for that meal_type + date → `422`
- Unknown QR code → `404`
- Unauthenticated → `401`

### GET /api/v1/scan/meal_slots
- Returns deduplicated slots for the event on that date
- Returns `[]` for a date with no slots
- Excludes slots from other events

### GET /api/v1/scan/orders/:order_reference (integration)
- `meal_slots` includes correct `stamp_count` per attendee
- Attendee with no meal slots → `meal_slots: []`

---

## Directus Setup

`ticket_meal_slots` needs to be exposed in Directus as a related collection on `tickets` so admins can add/edit meal slots when configuring a ticket. No Directus changes needed for `meal_stamps` — those are written by the Rails API only.
