# Per-Attendee QR Codes Design

**Date:** 2026-06-03

## Overview

Each attendee gets their own QR code derived from their order reference and attendee ID. The QR code is shown in the bookings list and encoded into a per-attendee Google Wallet pass. Scanning remains order-level — the frontend parses the QR to extract the order ref and uses the attendee ID to highlight the right row.

## QR Token Format

```
CT-2026-XXXXX-<attendee_id>
```

Example: `CT-2026-ABC123-42`

Computed on the fly — no DB column. Deterministic and parseable: split on the last `-` to recover `CT-2026-ABC123` (the order ref) and `42` (the attendee ID).

## Section 1 — Bookings List

**File:** `app/controllers/api/v1/auth/me/bookings_controller.rb`

`serialise_attendee` gains two new fields and a third parameter:

```ruby
def serialise_attendee(attendee, lang, order_reference)
  {
    id: attendee.id,
    qr_code: "#{order_reference}-#{attendee.id}",
    first_name: ...,
    ...
  }
end
```

All three call sites updated to pass `order.order_reference`.

## Section 2 — Google Wallet

### Route

Add to `config/routes.rb` alongside the existing order-level wallet route:

```ruby
get ':order_reference/attendees/:id/wallet/google', to: 'me/bookings#wallet_google_attendee', as: 'google_wallet_attendee'
```

The existing `':order_reference/wallet/google'` route is kept.

### Controller action

New `wallet_google_attendee` action in `BookingsController`:

1. Find `Order` by `order_reference`
2. Find `Attendee` by `id` scoped to that order
3. Authorize: `attendee.user_id == current_user.id`
4. Call `GoogleWalletService.new(attendee: attendee, language: lang).save_url`
5. Return `{ url: url }`

Returns 404 if order or attendee not found, or if the attendee does not belong to the current user.

### GoogleWalletService refactor

Constructor changes from `order:` to `attendee:`. The order is derived via `attendee.order`.

| Field | Old | New |
|---|---|---|
| `qr_token` | — | `"#{attendee.order.order_reference}-#{attendee.id}"` |
| `wallet_object_id` | `issuer_id.order_reference` | `issuer_id.qr_token` (sanitized) |
| `barcode value` | `order.order_reference` | `qr_token` |
| `class_id` | event slug (unchanged) | event slug (unchanged) |
| `event` | derived from order's first attendee | `attendee.event` directly |

One wallet object per attendee. All attendees of the same event share the same `EventTicketClass`.

## Section 3 — Scan Side

No backend changes. The existing `GET /api/v1/scan/orders/:order_reference` endpoint is unchanged.

Frontend responsibility: parse `CT-2026-ABC123-42` by splitting on the last `-`, use `CT-2026-ABC123` to call the scan endpoint, and use `42` to pre-select/highlight that attendee in the UI.

## Out of Scope

- Generating QR code images server-side (frontend renders the token string into a QR image)
- Apple Wallet support
- Changing the existing order-level wallet endpoint
