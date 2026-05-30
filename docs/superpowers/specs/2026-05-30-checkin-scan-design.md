# Check-in Scan Feature Design

**Date:** 2026-05-30  
**Status:** Approved

## Overview

Add a scan/check-in API for volunteers and admins at event venues. An operator scans a QR code (which encodes an order reference), looks up the order, and checks in one or all attendees. Payment status can be recorded at check-in time. All operations are reversible (uncheck-in, unpay).

## Database Changes

### Migration 1 — Move payment_status to orders

- Add `payment_status` (integer, default 0 = `payment_pending`, not null) to `orders`
- Data migration: copy each order's payment status from its first attendee's `payment_status`
- Remove `payment_status` column from `attendees`

Enum values (same as current attendee enum):
- `0` = `payment_pending`
- `1` = `paid`
- `2` = `refunded`

### Migration 2 — Add check-in tracking to attendees

- Add `checked_in` (boolean, default false, not null) to `attendees`
- Add `checked_in_at` (datetime, nullable) to `attendees`
- Add `checked_in_by_user_id` (bigint, nullable, FK → users) to `attendees`

## API Endpoints

All endpoints require:
- `Authorization: Bearer <jwt>` header
- User role must have `can_check_in_attendees: true` (admin or volunteer) — returns 403 otherwise

### GET `/api/v1/scan/orders/:order_reference`

Look up an order and return its payment status and all attendees with their check-in state.

**Response 200:**
```json
{
  "order_reference": "CT-2026-00042",
  "payment_status": "payment_pending",
  "attendees": [
    {
      "id": 1,
      "first_name": "Ion",
      "last_name": "Popescu",
      "email_address": "ion@example.com",
      "ticket_name": "General",
      "checked_in": false,
      "checked_in_at": null,
      "checked_in_by": null
    }
  ]
}
```

`checked_in_by` is the full name of the user who performed the check-in, or null.

`ticket_name` is resolved from `tickets_translations` defaulting to `ro-RO` (scan endpoints are not language-scoped).

**Response 404:** `{ "error": "Not found" }` — order reference does not exist.

### PATCH `/api/v1/scan/orders/:order_reference`

Update payment status and/or check-in state for one or more attendees. All fields are optional. Runs atomically in a single transaction.

**Request body:**
```json
{
  "payment_status": "paid",
  "attendees": [
    { "id": 1, "checked_in": true },
    { "id": 2, "checked_in": false }
  ]
}
```

**Behaviour:**
- `payment_status` — updates the order's payment status if provided; ignored if absent
- `attendees` — for each entry, only processes IDs that actually belong to this order (others are silently ignored)
  - `checked_in: true` → sets `checked_in_at` to current time, `checked_in_by_user_id` to current user
  - `checked_in: false` → clears `checked_in_at` and `checked_in_by_user_id`
- If both `payment_status` and `attendees` are absent → 422 `{ "error": "Nothing to update" }`
- Invalid `payment_status` value → 422 with validation error message

**Response 200:** Same shape as GET — returns refreshed order state so the FE doesn't need a separate fetch.

**Response 404:** Order reference not found.

## Code Structure

### Models

**`Order`**
- Add `enum :payment_status, { payment_pending: 0, paid: 1, refunded: 2 }`

**`Attendee`**
- Remove `enum :payment_status, ...`
- Add `belongs_to :checked_in_by, class_name: 'User', foreign_key: :checked_in_by_user_id, optional: true`

### Routes

New namespace under `api/v1`, separate from the user-facing `auth` namespace:

```ruby
namespace :scan do
  scope '/orders/:order_reference' do
    get  '/', to: 'orders#show'
    patch '/', to: 'orders#update'
  end
end
```

### Controller

`Api::V1::Scan::OrdersController`
- `include Authenticatable`
- `before_action :authenticate_user!`
- `before_action` calls `require_permission!(:can_check_in_attendees)` per existing pattern
- `show` — finds order, returns serialised response
- `update` — validates params, runs transaction, returns same serialised response

Inline JSON serialisation in the controller (no new serializer class) — consistent with `BookingsController`.

### Affected Existing Files

| File | Change |
|------|--------|
| `app/models/attendee.rb` | Remove `payment_status` enum |
| `app/models/order.rb` | Add `payment_status` enum |
| `app/controllers/api/v1/auth/me/bookings_controller.rb` | `check` action: filter by `order.payment_status`; `serialise_order`: read `order.payment_status` |
| `app/services/sendgrid_service.rb` | `is_pending` reads `order.payment_pending?` instead of attendee |
| `spec/factories/attendees.rb` | Remove `payment_status` trait |
| `spec/factories/orders.rb` | Add `payment_status` trait |
| `spec/requests/api/v1/auth/me/bookings_spec.rb` | Update to set payment_status on order |
| `spec/services/sendgrid_service_spec.rb` | Update to set payment_status on order |

## Error Handling

| Scenario | Status | Body |
|----------|--------|------|
| No/invalid JWT | 401 | `{ "error": "Unauthorized" }` |
| Role lacks permission | 403 | `{ "error": "Forbidden" }` |
| Order reference not found | 404 | `{ "error": "Not found" }` |
| Invalid payment_status value | 422 | `{ "error": "<validation message>" }` |
| No updateable fields in PATCH body | 422 | `{ "error": "Nothing to update" }` |

## Testing

**New request specs** (`spec/requests/api/v1/scan/orders_spec.rb`):
- GET: happy path, 401, 403, 404, multiple attendees with mixed check-in state
- PATCH: check-in all, check-in one, uncheck-in, mark paid, mark unpaid, combined payment + check-in, 401, 403, 404, unknown attendee IDs ignored, empty body → 422

**Updated specs:**
- `bookings_spec.rb` — payment_status set on order factory, not attendee
- `sendgrid_service_spec.rb` — payment_status set on order factory, not attendee
