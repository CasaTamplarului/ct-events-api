# Scan Search Feature Design

**Date:** 2026-05-31  
**Status:** Approved

## Overview

Add a search endpoint to the scan API so staff can find orders by partial order reference, attendee name, email, or phone number. The staff selects an order from the results list and then uses the existing `GET /api/v1/scan/orders/:order_reference` endpoint to operate on it.

## API Endpoint

```
GET /api/v1/scan/search
```

**Auth:** JWT + `can_check_in_attendees` permission (admin or volunteer). Returns 401/403 otherwise.

### Query Parameters

| Param | Required | Values |
|-------|----------|--------|
| `type` | always | `order_ref` \| `name` \| `email` \| `phone` |
| `query` | always | partial string, minimum 2 characters |
| `event_slug` | for `name`, `email`, `phone` | event slug string |

### Response — 200 OK

Always a list of orders. Empty array when no results. Capped at 20 results, ordered by `order_reference`.

```json
[
  {
    "order_reference": "CT-2026-00042",
    "payment_status": "paid",
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
]
```

Each order's `attendees` array contains **all** attendees in that order (consistent with the existing scan endpoint). For `name`/`email`/`phone` searches, the `event_slug` scopes which orders are found (orders where at least one attendee in that event matches the query), but all attendees in each matching order are returned.

`ticket_name` is resolved from the `ro-RO` translation (scan endpoints are not language-scoped). `checked_in_by` is the full name of the user who checked in the attendee, or `null`.

### Error Responses

| Scenario | Status | Body |
|----------|--------|------|
| No JWT token | 401 | `{ "error": "Unauthorized" }` |
| Role lacks permission | 403 | `{ "error": "Forbidden" }` |
| Missing `type` or `query` | 422 | `{ "error": "type and query are required" }` |
| Invalid `type` value | 422 | `{ "error": "Invalid type" }` |
| `query` shorter than 2 chars | 422 | `{ "error": "query must be at least 2 characters" }` |
| `event_slug` missing for name/email/phone | 422 | `{ "error": "event_slug is required for this search type" }` |
| Event not found for given slug | 404 | `{ "error": "Not found" }` |

## Query Logic

### `order_ref`

ILIKE on `orders.order_reference`. No event scope needed (order references are globally unique).

```sql
SELECT * FROM orders
WHERE order_reference ILIKE '%<query>%'
ORDER BY order_reference
LIMIT 20
```

### `name`

ILIKE across first name, last name, and full name concatenation, scoped to event:

```sql
SELECT DISTINCT orders.* FROM orders
INNER JOIN attendees ON attendees.order_id = orders.id
INNER JOIN events ON events.id = attendees.event_id
WHERE events.slug = '<event_slug>'
  AND (
    attendees.first_name ILIKE '%<query>%'
    OR attendees.last_name ILIKE '%<query>%'
    OR CONCAT(attendees.first_name, ' ', attendees.last_name) ILIKE '%<query>%'
  )
ORDER BY orders.order_reference
LIMIT 20
```

### `email`

Same join pattern as `name`, single ILIKE on `attendees.email_address`.

### `phone`

Same join pattern as `name`, single ILIKE on `attendees.phone_number`.

## Code Structure

### New Files

- `app/controllers/api/v1/scan/search_controller.rb` — single `index` action; validates params, runs the appropriate query, renders list
- `app/controllers/concerns/scan/serialisable.rb` — shared concern with `serialise_order` and `serialise_attendee` methods

### Modified Files

| File | Change |
|------|--------|
| `app/controllers/api/v1/scan/orders_controller.rb` | Include `Scan::Serialisable`; remove now-shared private methods |
| `config/routes.rb` | Add `get 'search', to: 'search#index'` inside the scan namespace |

### Controller Design

`SearchController` includes `Authenticatable` and `Scan::Serialisable`. The `index` action:

1. Validates params (type, query length, event_slug presence)
2. Resolves event from slug for name/email/phone types
3. Runs the appropriate private query method based on `type`
4. Eager-loads attendees with their associations (same as orders controller)
5. Renders `orders.map { |o| serialise_order(o) }`

The four query methods (`search_by_order_ref`, `search_by_name`, `search_by_email`, `search_by_phone`) are private methods on `SearchController`.

### Shared Concern: `Scan::Serialisable`

Extracted from `OrdersController`. Contains:
- `serialise_order(order)` — returns hash with `order_reference`, `payment_status`, `attendees`
- `serialise_attendee(attendee)` — returns hash with all attendee fields

`OrdersController` gains `include Scan::Serialisable` and loses those two private methods.

## Testing

**New request spec** (`spec/requests/api/v1/scan/search_spec.rb`):

- GET: 401, 403, 422 (missing params), 422 (invalid type), 422 (short query), 422 (missing event_slug), 404 (bad event slug)
- `order_ref` type: partial match returns results, no match returns `[]`, multiple matches all returned
- `name` type: partial first name match, partial last name match, full name match, no match returns `[]`
- `email` type: partial email match
- `phone` type: partial phone match
- Results capped at 20
- Response shape matches existing scan endpoint

**Updated spec** (`spec/requests/api/v1/scan/orders_spec.rb`):
- No changes to test behaviour; serialisation now comes from shared concern but tests remain the same
