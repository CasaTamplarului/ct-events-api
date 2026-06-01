# Google Wallet Pass — Design Spec

**Date:** 2026-06-01

## Overview

Add a `GET /api/v1/auth/me/bookings/:order_reference/wallet/google` endpoint that returns a Google Wallet save URL for an order. One pass per order (not per attendee). The pass embeds the event details and the order reference as a QR code. Passes can be updated after creation (e.g., if the event is rescheduled) because the pass object is created/updated via the Google Wallet REST API on every request.

---

## API

**Endpoint:** `GET /api/v1/auth/me/bookings/:order_reference/wallet/google`

**Auth:** Bearer token required (`authenticate_user!`). The user must be the order owner (`order.user_id == current_user.id`) or an attendee in the order (`attendees.where(user_id: current_user.id).exists?`). Otherwise → 404.

**Success response (200):**
```json
{ "url": "https://pay.google.com/gp/v/save/<jwt>" }
```

**Error responses:**
- `401` — unauthenticated
- `404` — order not found or user has no access to it
- `500` — Google Wallet API failure (generic message, full error logged)

---

## Implementation

### Route

Added to the existing `scope '/me/bookings'` block in `config/routes.rb`:

```ruby
get ':order_reference/wallet/google', to: 'me/bookings#wallet_google'
```

### Controller

New `wallet_google` action on the existing `Api::V1::Auth::Me::BookingsController`. The controller already has `authenticate_user!` and the order-finding pattern; no new controller is needed.

```ruby
def wallet_google
  order = Order.find_by(order_reference: params[:order_reference])
  return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless order

  authorized = order.user_id == current_user.id ||
               order.attendees.where(user_id: current_user.id).exists?
  return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless authorized

  lang = current_user.language || 'ro-RO'
  url  = GoogleWalletService.new(order: order, language: lang).save_url
  render json: { url: url }
rescue GoogleWalletService::ApiError => e
  Rails.logger.error("Google Wallet error for #{order.order_reference}: #{e.message}")
  render json: { error: 'Internal server error' }, status: :internal_server_error
end
```

### `GoogleWalletService`

`app/services/google_wallet_service.rb`

Responsible for three steps: upsert the event ticket class, upsert the order ticket object, sign and return the JWT URL.

**Credentials:**
| Source | Key |
|--------|-----|
| Env var | `GOOGLE_WALLET_SERVICE_ACCOUNT_JSON` — full service account JSON string |
| Env var | `GOOGLE_WALLET_ISSUER_ID` — issuer/merchant ID from Google Pay & Wallet Console |

Raises `ArgumentError` at instantiation if either is blank, so misconfiguration is caught early.

**New gem:** `googleauth` — handles service account OAuth2 token exchange with Google APIs. The existing `jwt` gem handles the final JWT signing.

#### Step 1 — Upsert `EventTicketClass`

One class per event, shared across all orders for that event.

- **ID:** `{issuer_id}.{sanitized_event_slug}` — non-alphanumeric characters replaced with underscores
- **Fields:** `eventName` (translated name, ro-RO fallback), `venue.name` from `event.location_name`, `dateTime.start` and `dateTime.end`
- **HTTP:** `PATCH https://walletobjects.googleapis.com/walletobjects/v1/eventTicketClass/{id}` — Google treats PATCH as upsert (creates if absent, updates if present)

#### Step 2 — Upsert `EventTicketObject`

One object per order.

- **ID:** `{issuer_id}.{sanitized_order_reference}` — hyphens replaced with underscores (e.g., `CT_2026_XXXXXX`)
- **Fields:** `classId` linking to the class above; `barcode.type: QR_CODE`, `barcode.value: order_reference`; `state: active`
- **HTTP:** `PATCH https://walletobjects.googleapis.com/walletobjects/v1/eventTicketObject/{id}`

#### Step 3 — Sign JWT

Payload:
```json
{
  "iss": "<service_account_email>",
  "aud": "google",
  "typ": "savetowallet",
  "iat": <unix_timestamp>,
  "payload": {
    "eventTicketObjects": [{ "id": "<object_id>" }]
  }
}
```

Signed with the service account private key using RS256 via the `jwt` gem.

Returns `"https://pay.google.com/gp/v/save/#{token}"`.

#### Error handling

`GoogleWalletService::ApiError` is raised when either REST call returns a non-2xx response. The controller rescues it, logs the full message, and returns 500 to the client.

---

## Credentials Setup

The service account JSON and issuer ID go in `.env` (development) and Rails encrypted credentials (production):

```
GOOGLE_WALLET_SERVICE_ACCOUNT_JSON={"type":"service_account",...}
GOOGLE_WALLET_ISSUER_ID=1234567890123456789
```

---

## Testing

### `spec/services/google_wallet_service_spec.rb`

Unit tests with WebMock stubs:
- Successful upsert of class + object + JWT signing → returns correct URL
- Google Wallet API returns 4xx/5xx → raises `GoogleWalletService::ApiError`
- Missing credentials → raises `ArgumentError`

### `spec/requests/api/v1/auth/me/bookings/wallet_spec.rb`

Request specs:
- `200` — authenticated order owner gets back a URL
- `200` — authenticated attendee (not owner) gets back a URL
- `401` — no token
- `404` — order reference does not exist
- `404` — user is neither owner nor attendee
