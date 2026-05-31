# Scan API

Endpoints for the event check-in scanner UI. All endpoints require a JWT bearer token from an account with `admin` or `volunteer` role.

## Authentication

Every request must include:

```
Authorization: Bearer <token>
Content-Type: application/json
```

A missing or invalid token returns `401 Unauthorized`. An `attendee`-role account returns `403 Forbidden`.

---

## 1. List upcoming events

Use this to populate the "which event are you scanning?" picker before searching.

```
GET /api/v1/scan/events
```

**Response 200**

```json
[
  { "name": "Conferința 2026", "slug": "conferinta-2026" },
  { "name": "Tabăra 2026",     "slug": "tabara-2026" }
]
```

- Sorted by start date ascending (soonest first).
- Name is returned in the authenticated user's language, falling back to Romanian (`ro-RO`).
- Returns `[]` when there are no upcoming live events.

---

## 2. Search orders

Search for orders by order reference, attendee name, email, or phone. Use the event slug from step 1 for name/email/phone searches.

```
GET /api/v1/scan/search
```

**Query parameters**

| Parameter    | Required                        | Description |
|--------------|---------------------------------|-------------|
| `type`       | Always                          | `order_ref` \| `name` \| `email` \| `phone` |
| `query`      | Always                          | Partial string, minimum 2 characters |
| `event_slug` | Required for `name`/`email`/`phone` | Scopes search to a specific event |

**Example requests**

```
GET /api/v1/scan/search?type=order_ref&query=CT-2026
GET /api/v1/scan/search?type=name&query=Ion&event_slug=conferinta-2026
GET /api/v1/scan/search?type=email&query=ion@&event_slug=conferinta-2026
GET /api/v1/scan/search?type=phone&query=0722&event_slug=conferinta-2026
```

**Response 200** — list of matching orders (max 20, ordered by `order_reference`):

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
        "payment_status": "paid",
        "checked_in": false,
        "checked_in_at": null,
        "checked_in_by": null
      }
    ]
  }
]
```

Returns `[]` when nothing matches.

**Error responses**

| Scenario | Status | `error` |
|----------|--------|---------|
| Missing `type` or `query` | 422 | `"type and query are required"` |
| Invalid `type` value | 422 | `"Invalid type"` |
| `query` shorter than 2 characters | 422 | `"query must be at least 2 characters"` |
| Missing `event_slug` for name/email/phone | 422 | `"event_slug is required for this search type"` |
| `event_slug` not found | 404 | `"Not found"` |

**Notes**

- `order_ref` search does not require `event_slug` — order references are globally unique.
- For `name`/`email`/`phone`, the `event_slug` scopes which orders are returned (only orders where at least one attendee at that event matches). All attendees in each matching order are included in the response.
- `ticket_name` is always the Romanian (`ro-RO`) translation.
- `checked_in_by` is the full name of the staff member who performed the check-in, or `null`.
- The order-level `payment_status` is computed from attendees (see [payment_status values](#payment_status-values)).

---

## 3. Get order by reference

Fetch a single order once you have the exact reference (from search results or a scanned QR code).

```
GET /api/v1/scan/orders/:order_reference
```

**Response 200**

```json
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
      "payment_status": "paid",
      "checked_in": false,
      "checked_in_at": null,
      "checked_in_by": null
    }
  ]
}
```

**Error responses**

| Scenario | Status | `error` |
|----------|--------|---------|
| Order reference not found | 404 | `"Not found"` |

---

## 4. Check in / update an order

Check in one or more attendees and optionally update payment status per attendee. All fields are optional — send only what you want to change.

```
PATCH /api/v1/scan/orders/:order_reference
```

**Request body**

```json
{
  "attendees": [
    { "id": 1, "checked_in": true, "payment_status": "paid" },
    { "id": 2, "checked_in": false }
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `attendees` | array | List of attendees to update (required — at least this key must be present) |
| `attendees[].id` | integer | Attendee ID |
| `attendees[].checked_in` | boolean (optional) | `true` to check in, `false` to undo |
| `attendees[].payment_status` | string (optional) | `"payment_pending"` \| `"paid"` \| `"refunded"` |

**Behaviour**

- **Check in** (`checked_in: true`): records `checked_in_at` (current time) and `checked_in_by` (current user).
- **Undo check-in** (`checked_in: false`): clears `checked_in_at` and `checked_in_by`.
- **Payment status** is set per attendee. An invalid value is silently ignored (attendee unchanged).
- Attendee IDs that do not belong to this order are silently ignored.
- `checked_in` and `payment_status` can be combined in a single attendee entry.

**Response 200** — same shape as GET, reflecting the updated state:

```json
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
      "payment_status": "paid",
      "checked_in": true,
      "checked_in_at": "2026-06-01T10:00:00.000Z",
      "checked_in_by": "Ana Ionescu"
    }
  ]
}
```

**Error responses**

| Scenario | Status | `error` |
|----------|--------|---------|
| Order reference not found | 404 | `"Not found"` |
| `attendees` key missing or empty | 422 | `"Nothing to update"` |
| Authenticated user is an attendee in this order | 403 | `"Forbidden"` |

---

## Typical scan flow

```
1. GET  /api/v1/scan/events
       → pick event, get slug

2. User scans QR code → extract order_reference string (format: CT-YYYY-NNNNN)
   GET  /api/v1/scan/orders/:order_reference
       → show order + attendees

   OR user types a name / email / phone:
   GET  /api/v1/scan/search?type=name&query=Ion&event_slug=conferinta-2026
       → show list → user picks an order
   GET  /api/v1/scan/orders/:order_reference
       → show order + attendees

3. Staff checks in attendees (optionally marks payment):
   PATCH /api/v1/scan/orders/:order_reference
         { "attendees": [{ "id": 1, "checked_in": true, "payment_status": "paid" }] }

4. Response from PATCH is the refreshed order — no need for a separate GET.
```

---

## payment_status values

### Per-attendee

| Value | Meaning |
|-------|---------|
| `"payment_pending"` | Payment not yet received |
| `"paid"` | Payment confirmed |
| `"refunded"` | Payment was refunded |
| `"attendee_cancelled"` | Attendee cancelled their own spot |

### Order-level (computed)

The order-level `payment_status` is derived from its attendees. `attendee_cancelled` attendees are excluded from the calculation.

| Value | Meaning |
|-------|---------|
| `"payment_pending"` | All active attendees are pending |
| `"paid"` | All active attendees are paid |
| `"refunded"` | All active attendees are refunded |
| `"partial"` | Active attendees have mixed statuses |
| `"attendee_cancelled"` | All attendees have cancelled |
