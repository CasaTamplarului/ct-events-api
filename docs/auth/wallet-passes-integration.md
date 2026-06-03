# Wallet Passes Integration Guide

Endpoints for adding event tickets to Google Wallet and Apple Wallet. Both wallets are supported; the UX differs because Apple returns a binary file while Google returns a redirect URL.

**Base URL:** `https://api.casatamplarului.ro` (or `http://localhost:3000` for local dev)

All endpoints require a valid JWT:

```
Authorization: Bearer <jwt>
Content-Type: application/json
```

---

## Endpoints

| Method | Path | Response | Description |
|--------|------|----------|-------------|
| `GET` | `/api/v1/auth/me/bookings/:order_reference/wallet/google` | JSON `{ url }` | Google Wallet pass — order-level |
| `GET` | `/api/v1/auth/me/bookings/:order_reference/attendees/:id/wallet/google` | JSON `{ url }` | Google Wallet pass — specific attendee |
| `GET` | `/api/v1/auth/me/bookings/:order_reference/wallet/apple` | Binary `.pkpass` | Apple Wallet pass — order-level |
| `GET` | `/api/v1/auth/me/bookings/:order_reference/attendees/:id/wallet/apple` | Binary `.pkpass` | Apple Wallet pass — specific attendee |

---

## Order-level vs attendee-level

Both wallets offer two endpoint flavours:

**Order-level** (`/wallet/:provider`) — finds the attendee associated with the current user on that order. If the user is the order owner and no attendee row matches their user ID, it falls back to the first attendee on the order. Use this for the "Add to Wallet" button on the order confirmation / booking detail screen when you don't yet know which attendee ID to target.

**Attendee-level** (`/attendees/:id/wallet/:provider`) — targets a specific attendee by ID. The attendee must belong to the current user (`user_id` match) — no fallback. Use this when displaying per-attendee tickets (e.g. a booking with multiple attendees).

---

## 1. Google Wallet

```
GET /api/v1/auth/me/bookings/:order_reference/wallet/google
GET /api/v1/auth/me/bookings/:order_reference/attendees/:id/wallet/google
```

**Response 200**

```json
{ "url": "https://pay.google.com/gp/v/save/eyJhb..." }
```

**Integration**

Redirect the user (or open the URL in a new tab) to the returned `url`. On Android, this opens the Google Pay app and prompts "Add to Google Wallet". On desktop it opens the web flow.

```ts
const { url } = await fetchGoogleWalletUrl(orderRef);
window.open(url, '_blank');
```

The pass contains:
- Event name, venue, and start date
- Attendee name
- Order reference (on the back of the pass)
- QR code — value is the attendee's `qr_code` (e.g. `CT-2026-ABC123-42`)

---

## 2. Apple Wallet

```
GET /api/v1/auth/me/bookings/:order_reference/wallet/apple
GET /api/v1/auth/me/bookings/:order_reference/attendees/:id/wallet/apple
```

**Response 200**

Returns a binary `.pkpass` file:

```
Content-Type: application/vnd.apple.pkpass
Content-Disposition: attachment; filename="ticket-CT-2026-ABC123.pkpass"
```

**Integration**

Apple Wallet cannot be opened via a redirect URL — you must trigger a file download. On iOS Safari, the browser automatically prompts "Add to Apple Wallet" when it receives `application/vnd.apple.pkpass`. On other browsers/platforms the file downloads normally.

**Recommended approach: fetch → Blob → object URL**

```ts
async function addToAppleWallet(orderRef: string) {
  const res = await fetch(
    `/api/v1/auth/me/bookings/${orderRef}/wallet/apple`,
    { headers: { Authorization: `Bearer ${jwt}` } }
  );

  if (!res.ok) throw new Error('Failed to get pass');

  const blob = await res.blob();
  const url  = URL.createObjectURL(blob);

  const a = document.createElement('a');
  a.href     = url;
  a.download = `ticket-${orderRef}.pkpass`;
  a.click();

  URL.revokeObjectURL(url);
}
```

On iOS Safari this triggers the native "Add to Apple Wallet" sheet instead of a download prompt.

The pass contains:
- Event name (primary field)
- Date and venue (secondary fields)
- Attendee name (auxiliary field)
- Order reference (on the back of the pass)
- QR code — value is the attendee's `qr_code` (e.g. `CT-2026-ABC123-42`)

---

## Showing the right wallet button

Show the wallet button(s) on the booking detail / order confirmation screen. You can show both buttons simultaneously — each is independent.

```ts
// Detect iOS to show Apple Wallet button
const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream;

// Always show Google Wallet button (works on Android + web)
// Show Apple Wallet button on iOS (or universally if you want to allow saving from desktop too)
```

**Recommended UI:**

- On iOS: show "Add to Apple Wallet" button (Apple badge asset, see [Apple HIG](https://developer.apple.com/wallet/))
- On Android: show "Add to Google Wallet" button
- On desktop: show both, or show Google Wallet only (Apple Wallet files download on desktop but can't be opened without a Mac/iOS device)

---

## Per-attendee tickets (multiple attendees on one order)

If an order has multiple attendees, render a wallet button per attendee using the attendee-level endpoint:

```ts
for (const attendee of order.attendees) {
  // Google Wallet
  const googleUrl = await fetch(
    `/api/v1/auth/me/bookings/${order.order_reference}/attendees/${attendee.id}/wallet/google`,
    { headers: { Authorization: `Bearer ${jwt}` } }
  ).then(r => r.json()).then(d => d.url);

  // Apple Wallet
  // Use the attendee-level endpoint in the fetch call above
}
```

The `qr_code` on each attendee object (returned by `/bookings/upcoming` and `/bookings/past`) is the value that will appear on the pass barcode — use it for your own in-app QR display too:

```ts
attendee.qr_code // e.g. "CT-2026-ABC123-42"
```

---

## Error responses

| Scenario | Status | Body |
|----------|--------|------|
| Not authenticated | 401 | `{ "error": "..." }` |
| Order not found, or user has no access | 404 | `{ "error": "Not found" }` |
| Wallet API / pass generation failed | 500 | `{ "error": "Internal server error" }` |

On 500, retry once after a short delay. If it persists, show a fallback message ("Wallet pass temporarily unavailable").
