# Bookings Integration Guide

Endpoints for displaying a user's event bookings and allowing them to cancel their own spots.

**Base URL:** `https://api.casatamplarului.ro` (or `http://localhost:3000` for local dev)

All endpoints require a valid JWT:

```
Authorization: Bearer <jwt>
Content-Type: application/json
```

---

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/auth/me/bookings/upcoming` | User's upcoming bookings |
| `GET` | `/api/v1/auth/me/bookings/past` | User's past bookings |
| `POST` | `/api/v1/auth/me/bookings/check` | Check if user has bookings for given event slugs |
| `DELETE` | `/api/v1/auth/me/bookings/:order_reference` | Cancel all cancellable attendees in an order |
| `DELETE` | `/api/v1/auth/me/bookings/:order_reference/attendees/:id` | Cancel a single attendee |

---

## 1. Upcoming bookings

```
GET /api/v1/auth/me/bookings/upcoming
```

Returns the authenticated user's bookings for events that haven't started yet, sorted by event start date ascending.

**Response 200**

```json
[
  {
    "order_reference": "CT-2026-00042",
    "payment_status": "paid",
    "total_price": "150.0",
    "event": {
      "name": "Conferința 2026",
      "slug": "conferinta-2026",
      "start_date": "2026-06-18T10:00:00.000Z",
      "end_date": "2026-06-20T18:00:00.000Z",
      "location_name": "Casa Tâmplarului",
      "address": "Str. Tâmplarilor 1, Cluj-Napoca"
    },
    "attendees": [
      {
        "first_name": "Ion",
        "last_name": "Popescu",
        "ticket_name": "General",
        "ticket_description": "Includes all sessions",
        "ticket_price": "150.0",
        "food_included": true,
        "dietary_preference": "no_preference"
      }
    ]
  }
]
```

**Notes**

- Only returns the current user's own attendees — if others are on the same order they are not included.
- `attendee_cancelled` attendees are excluded.
- `payment_status` is computed from the user's visible attendees (see [payment_status values](#payment_status-values)).
- `event.name` is returned in the user's preferred language, falling back to Romanian (`ro-RO`).
- Returns `[]` when there are no upcoming bookings.

---

## 2. Past bookings

```
GET /api/v1/auth/me/bookings/past
```

Same shape as upcoming, but for events where `end_date` has passed. Sorted by event start date descending (most recent first).

---

## 3. Check booking status

Use this to show "already booked" badges on the events listing page without fetching full booking details.

```
POST /api/v1/auth/me/bookings/check
Content-Type: application/json
```

**Request body**

```json
{
  "slugs": ["conferinta-2026", "tabara-2026", "workshop-iulie"]
}
```

- Maximum 50 slugs per request.
- Only slugs with `paid` or `payment_pending` attendees count as booked.

**Response 200** — a map of slug → booking status:

```json
{
  "conferinta-2026": { "has_booking": true,  "order_reference": "CT-2026-00042" },
  "tabara-2026":     { "has_booking": false, "order_reference": null },
  "workshop-iulie":  { "has_booking": false, "order_reference": null }
}
```

**Error responses**

| Scenario | Status | `error` |
|----------|--------|---------|
| `slugs` missing or empty | 422 | `"slugs is required"` |

---

## 4. Cancel an order

Cancels all `payment_pending` attendees belonging to the current user in an order. Only attendees the user owns are affected — other users' attendees in the same order are untouched. Already-paid attendees are also left as-is.

```
DELETE /api/v1/auth/me/bookings/:order_reference
```

**Response 200** — the updated booking (only the user's own attendees):

```json
{
  "order_reference": "CT-2026-00042",
  "payment_status": "attendee_cancelled",
  "total_price": "0.0",
  "event": { ... },
  "attendees": [
    {
      "first_name": "Ion",
      "last_name": "Popescu",
      "ticket_name": "General",
      "ticket_description": "Includes all sessions",
      "ticket_price": "150.0",
      "food_included": true,
      "dietary_preference": "no_preference"
    }
  ]
}
```

**Error responses**

| Scenario | Status | `error` |
|----------|--------|---------|
| Order not found | 404 | `"Not found"` |
| User has no attendees in this order | 404 | `"Not found"` |
| All user attendees are already paid or cancelled | 422 | `"No cancellable attendees found for this order"` |

---

## 5. Cancel a single attendee

Cancels one specific attendee. Only works when the attendee's `payment_status` is `payment_pending`.

```
DELETE /api/v1/auth/me/bookings/:order_reference/attendees/:id
```

**Response 200** — same shape as cancel order, reflecting the updated state.

**Error responses**

| Scenario | Status | `error` |
|----------|--------|---------|
| Order not found | 404 | `"Not found"` |
| Attendee not found or belongs to another user | 404 | `"Not found"` |
| Attendee is already paid or already cancelled | 422 | `"This attendee cannot be cancelled (payment already processed)"` |

---

## payment_status values

`payment_status` on a booking is computed from the user's visible attendees in that order.

| Value | Meaning |
|-------|---------|
| `"payment_pending"` | All attendees are pending payment |
| `"paid"` | All attendees are paid |
| `"refunded"` | All attendees are refunded |
| `"partial"` | Attendees have mixed statuses |
| `"attendee_cancelled"` | All attendees have cancelled |

---

## TypeScript types

```ts
interface BookingEvent {
  name: string;
  slug: string;
  start_date: string;       // ISO 8601
  end_date: string;         // ISO 8601
  location_name: string;
  address: string;
}

interface BookingAttendee {
  first_name: string;
  last_name: string;
  ticket_name: string | null;
  ticket_description: string | null;
  ticket_price: string | null;  // decimal string, e.g. "150.0"
  food_included: boolean | null;
  dietary_preference: "no_preference" | "vegetarian" | "vegan";
}

interface Booking {
  order_reference: string;
  payment_status: "payment_pending" | "paid" | "refunded" | "partial" | "attendee_cancelled";
  total_price: string;      // decimal string
  event: BookingEvent;
  attendees: BookingAttendee[];
}

interface CheckResult {
  has_booking: boolean;
  order_reference: string | null;
}
```

---

## Frontend implementation

### Bookings page

```ts
const BASE = "https://api.casatamplarului.ro";

async function getUpcomingBookings(jwt: string): Promise<Booking[]> {
  const res = await fetch(`${BASE}/api/v1/auth/me/bookings/upcoming`, {
    headers: { Authorization: `Bearer ${jwt}` },
  });
  if (!res.ok) throw new Error((await res.json()).error);
  return res.json();
}

async function getPastBookings(jwt: string): Promise<Booking[]> {
  const res = await fetch(`${BASE}/api/v1/auth/me/bookings/past`, {
    headers: { Authorization: `Bearer ${jwt}` },
  });
  if (!res.ok) throw new Error((await res.json()).error);
  return res.json();
}
```

### "Already booked" badges on event listing

```ts
async function checkBookings(
  jwt: string,
  slugs: string[]
): Promise<Record<string, CheckResult>> {
  const res = await fetch(`${BASE}/api/v1/auth/me/bookings/check`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${jwt}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ slugs }),
  });
  if (!res.ok) throw new Error((await res.json()).error);
  return res.json();
}

// Usage — pass all visible slugs in one call:
const status = await checkBookings(jwt, events.map((e) => e.slug));
// status["conferinta-2026"].has_booking → true/false
```

### Cancel order

```ts
async function cancelOrder(jwt: string, orderRef: string): Promise<Booking> {
  const res = await fetch(`${BASE}/api/v1/auth/me/bookings/${orderRef}`, {
    method: "DELETE",
    headers: { Authorization: `Bearer ${jwt}` },
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error);
  return data;
}
```

### Cancel single attendee

```ts
async function cancelAttendee(
  jwt: string,
  orderRef: string,
  attendeeId: number
): Promise<Booking> {
  const res = await fetch(
    `${BASE}/api/v1/auth/me/bookings/${orderRef}/attendees/${attendeeId}`,
    {
      method: "DELETE",
      headers: { Authorization: `Bearer ${jwt}` },
    }
  );
  const data = await res.json();
  if (!res.ok) throw new Error(data.error);
  return data;
}
```

---

## Cancellation rules

- Only **`payment_pending`** attendees can be cancelled. Already-paid spots cannot be self-cancelled.
- **Cancel order** (`DELETE /:order_reference`) cancels all of the user's `payment_pending` attendees in the order at once.
- **Cancel attendee** (`DELETE /:order_reference/attendees/:id`) cancels one specific attendee.
- Both endpoints return 422 if there is nothing to cancel.
- Cancelling does not affect other users' attendees on the same order.
