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
| `GET` | `/api/v1/auth/me/bookings/:order_reference/wallet/google` | Google Wallet pass for the user's attendee (order-level) |
| `GET` | `/api/v1/auth/me/bookings/:order_reference/attendees/:id/wallet/google` | Google Wallet pass for a specific attendee |
| `GET` | `/api/v1/auth/me/bookings/:order_reference/wallet/apple` | Apple Wallet pass for the user's attendee (order-level) |
| `GET` | `/api/v1/auth/me/bookings/:order_reference/attendees/:id/wallet/apple` | Apple Wallet pass for a specific attendee |

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
        "id": 42,
        "qr_code": "CT-2026-ABC123-42",
        "first_name": "Ion",
        "last_name": "Popescu",
        "payment_status": "paid",
        "ticket_name": "General",
        "ticket_description": "Includes all sessions",
        "ticket_price": "150.0",
        "food_included": true,
        "dietary_preference": "no_preference",
        "allergies": []
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
      "id": 42,
      "qr_code": "CT-2026-ABC123-42",
      "first_name": "Ion",
      "last_name": "Popescu",
      "payment_status": "attendee_cancelled",
      "ticket_name": "General",
      "ticket_description": "Includes all sessions",
      "ticket_price": "150.0",
      "food_included": true,
      "dietary_preference": "no_preference",
      "allergies": []
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
  id: number;
  qr_code: string;              // "CT-YYYY-XXXXX-<attendee_id>" — use for in-app QR display and wallet
  first_name: string;
  last_name: string;
  payment_status: "payment_pending" | "paid" | "refunded" | "attendee_cancelled";
  ticket_name: string | null;
  ticket_description: string | null;
  ticket_price: string | null;  // decimal string, e.g. "150.0"
  food_included: boolean | null;
  dietary_preference: "no_preference" | "vegetarian" | "vegan";
  allergies: Array<"gluten" | "lactose" | "nuts" | "eggs" | "soy" | "fish" | "shellfish">;
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

### Add to Google Wallet (per-attendee)

```ts
async function getAttendeeWalletUrl(
  jwt: string,
  orderRef: string,
  attendeeId: number
): Promise<string> {
  const res = await fetch(
    `${BASE}/api/v1/auth/me/bookings/${orderRef}/attendees/${attendeeId}/wallet/google`,
    { headers: { Authorization: `Bearer ${jwt}` } }
  );
  const data = await res.json();
  if (!res.ok) throw new Error(data.error);
  return data.url; // open this URL in a browser tab
}
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

## 6. Google Wallet pass (order-level)

Returns a URL the user can open to save their ticket to Google Wallet. This finds the user's own attendee in the order; if the user is the order creator with no attendee row it falls back to the order's first attendee.

```
GET /api/v1/auth/me/bookings/:order_reference/wallet/google
```

**Response 200**

```json
{ "url": "https://pay.google.com/gp/v/save/<jwt>" }
```

**Error responses**

| Scenario | Status | `error` |
|----------|--------|---------|
| Order not found or user has no access | 404 | `"Not found"` |
| Google Wallet API error | 500 | `"Internal server error"` |

---

## 7. Google Wallet pass (per-attendee)

Returns a wallet URL for a specific attendee. The attendee must belong to the authenticated user (`user_id` match). Use this when displaying individual tickets — each attendee gets their own pass with a unique QR code.

```
GET /api/v1/auth/me/bookings/:order_reference/attendees/:id/wallet/google
```

**Response 200** — same shape as the order-level endpoint.

**Error responses**

| Scenario | Status | `error` |
|----------|--------|---------|
| Order not found | 404 | `"Not found"` |
| Attendee not found or belongs to another user | 404 | `"Not found"` |
| Google Wallet API error | 500 | `"Internal server error"` |

**Note:** Each wallet pass encodes the attendee's `qr_code` (`CT-YYYY-XXXXX-<attendee_id>`) as its barcode. See [QR codes](#qr-codes) below.

---

## QR codes

Each attendee has a `qr_code` field in the booking response:

```
CT-2026-ABC123-42
```

Format: `<order_reference>-<attendee_id>`

**Uses:**
- Render as a QR image in the app for the attendee to show at the door
- Passed as the barcode value in Google Wallet passes

**Scanning:** The check-in scan API resolves by `order_reference` only. When parsing a scanned QR:
```ts
function parseQrCode(qr: string): { orderRef: string; attendeeId: number } {
  const lastDash = qr.lastIndexOf("-");
  return {
    orderRef: qr.slice(0, lastDash),      // "CT-2026-ABC123"
    attendeeId: parseInt(qr.slice(lastDash + 1), 10), // 42
  };
}
```
Use `orderRef` to call `GET /api/v1/scan/orders/:order_reference`, then use `attendeeId` to highlight the matching attendee row.

---

## Frontend implementation

### Bookings page

- Only **`payment_pending`** attendees can be cancelled. Already-paid spots cannot be self-cancelled.
- **Cancel order** (`DELETE /:order_reference`) cancels all of the user's `payment_pending` attendees in the order at once.
- **Cancel attendee** (`DELETE /:order_reference/attendees/:id`) cancels one specific attendee.
- Both endpoints return 422 if there is nothing to cancel.
- Cancelling does not affect other users' attendees on the same order.
