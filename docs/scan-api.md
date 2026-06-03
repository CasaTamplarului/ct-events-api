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
  { "name": "Conferința 2026", "slug": "conferinta-2026", "has_meal_tracking": false },
  { "name": "Tabăra 2026",     "slug": "tabara-2026",     "has_meal_tracking": true  }
]
```

- Sorted by start date ascending (soonest first).
- Name is returned in the authenticated user's language, falling back to Romanian (`ro-RO`).
- `has_meal_tracking` is `true` when at least one ticket on the event has meal slots configured. Use this to decide whether to show the food stamp UI.
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
      "checked_in_by": null,
      "meal_slots": [
        { "id": 12, "meal_type": "lunch",  "occurs_on": "2026-07-15", "sort": 1, "stamp_count": 1 },
        { "id": 13, "meal_type": "dinner", "occurs_on": "2026-07-15", "sort": 2, "stamp_count": 0 }
      ]
    }
  ]
}
```

- `meal_slots` is an array of all meal entitlements for that attendee's ticket, sorted by date then sort order.
- `stamp_count: 0` — not yet received. `stamp_count: 1` — received once. `stamp_count: 2+` — had seconds.
- Attendees on tickets with no meal slots receive `meal_slots: []`.

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
      "checked_in_by": "Ana Ionescu",
      "meal_slots": [
        { "id": 12, "meal_type": "lunch", "occurs_on": "2026-07-15", "sort": 1, "stamp_count": 0 }
      ]
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

## 5. List meal slots for a date

Used by the kitchen UI to show which meals are being served today and let staff select the current one before scanning.

```
GET /api/v1/scan/meal_slots?event_slug=tabara-2026&date=2026-07-15
```

**Query parameters**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `event_slug` | Yes | Slug of the event |
| `date` | Yes | `YYYY-MM-DD` — the date to list meals for |

**Response 200**

```json
[
  { "id": 12, "meal_type": "lunch",  "occurs_on": "2026-07-15", "sort": 1 },
  { "id": 13, "meal_type": "dinner", "occurs_on": "2026-07-15", "sort": 2 }
]
```

- Results are deduplicated by `meal_type` — if multiple ticket types share the same meal on a given date, only one entry appears. The kitchen selects a meal once, regardless of how many ticket types it applies to.
- Sorted by `sort` then `id`.
- Returns `[]` when no meals are configured for that date.

**Error responses**

| Scenario | Status | `error` |
|----------|--------|---------|
| Unknown `event_slug` | 404 | `"Not found"` |
| Missing `date` | 422 | `"date is required"` |
| Invalid `date` format | 422 | `"invalid date"` |

---

## 6. Stamp a meal

Records that an attendee received a specific meal. Call this when the kitchen scans a QR code.

```
POST /api/v1/scan/meal_stamps
Content-Type: application/json
```

**Request body**

```json
{
  "qr_code":   "CT-2026-ABC123-42",
  "meal_type": "lunch",
  "occurs_on": "2026-07-15"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `qr_code` | string | The scanned QR code value (attendee's `qr_code`) |
| `meal_type` | string | One of `breakfast` \| `lunch` \| `dinner` \| `snack` |
| `occurs_on` | string | `YYYY-MM-DD` — the date of the meal |

**Response 200**

```json
{
  "stamp": {
    "id":         99,
    "stamped_at": "2026-07-15T12:34:00.000Z",
    "stamped_by": "Ana Ionescu"
  },
  "already_stamped": false,
  "total_stamps":    1,
  "attendee": { "id": 42, "first_name": "Ion", "last_name": "Popescu" }
}
```

| Field | Description |
|-------|-------------|
| `already_stamped` | `true` if the attendee had already received this meal today (seconds). Always stamp anyway — this is a warning, not a block. |
| `total_stamps` | Total number of times this meal has been given to this attendee (1 = first time, 2+ = seconds). |

**Behaviour**

- Always succeeds if the attendee is entitled to the meal — even if they've already received it.
- Show a warning in the UI when `already_stamped: true` so kitchen staff can decide whether to proceed.
- `total_stamps` lets you display "2nd serving" or track daily consumption totals.

**Error responses**

| Scenario | Status | `error` |
|----------|--------|---------|
| QR code not found | 404 | `"Not found"` |
| Attendee's ticket doesn't include this meal on this date | 422 | `"Not entitled"` |
| Missing `qr_code`, `meal_type`, or `occurs_on` | 422 | `"qr_code, meal_type, and occurs_on are required"` |

---

## Typical scan flow

```
1. GET  /api/v1/scan/events
       → pick event, get slug

2. User scans QR code.

   QR codes come in two formats:
   - Order-level (email confirmation): "CT-2026-ABC123"
   - Per-attendee (wallet pass / in-app): "CT-2026-ABC123-42"

   Parse the scanned value before calling the API:
     const lastDash = qr.lastIndexOf("-");
     const isPerAttendee = lastDash > "CT-2026-".length + 5; // attendee_id suffix present
     const orderRef  = isPerAttendee ? qr.slice(0, lastDash) : qr;
     const attendeeId = isPerAttendee ? parseInt(qr.slice(lastDash + 1), 10) : null;

   GET  /api/v1/scan/orders/:orderRef
       → show order + attendees
       → if attendeeId is set, scroll to / highlight that attendee

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

## Typical food stamp flow

Only relevant when `has_meal_tracking: true` for the event.

```
1. GET  /api/v1/scan/events
       → pick event, note has_meal_tracking: true

2. Kitchen selects today's meal:
   GET  /api/v1/scan/meal_slots?event_slug=tabara-2026&date=2026-07-15
       → show list of meals for today (e.g. Lunch, Dinner)
       → kitchen taps the current meal — store selected { id, meal_type, occurs_on }

3. Kitchen scans attendee QR code:
   POST /api/v1/scan/meal_stamps
        { "qr_code": "CT-2026-ABC123-42", "meal_type": "lunch", "occurs_on": "2026-07-15" }

4. Handle response:
   - already_stamped: false → show green ✓ "Ion Popescu — Lunch confirmed"
   - already_stamped: true  → show yellow ⚠ "Already received (×2 total) — stamp again?"
   - 422 Not entitled        → show red ✗ "Not entitled to this meal"
   - 404                     → show red ✗ "QR code not recognised"

5. Kitchen keeps the selected meal active and scans the next attendee (back to step 3).
   No need to re-select the meal between scans — only change it when the meal service changes.
```

**Displaying `meal_slots` on the order detail screen:**

When showing an order via `GET /scan/orders/:order_reference`, each attendee includes `meal_slots` with `stamp_count`. Use this to show a visual food status per attendee:

```
Ion Popescu
  🍽 Lunch   Jul 15  ✓ (1)
  🍽 Dinner  Jul 15  —
  🍽 Lunch   Jul 16  —
```

---

## meal_type values

| Value | Label (translate in FE) |
|-------|------------------------|
| `"breakfast"` | Breakfast / Mic dejun |
| `"lunch"` | Lunch / Prânz |
| `"dinner"` | Dinner / Cină |
| `"snack"` | Snack / Gustare |

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
