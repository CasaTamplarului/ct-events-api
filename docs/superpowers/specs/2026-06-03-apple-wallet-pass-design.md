# Apple Wallet Pass — Design

**Date:** 2026-06-03
**Status:** Approved

## Overview

Add Apple Wallet pass generation for event tickets, alongside the existing Google Wallet implementation. The server generates and returns a signed `.pkpass` binary file per attendee. Two endpoints mirror the existing Google Wallet routes.

## Architecture

### Service

`app/services/apple_wallet_service.rb` — initialized with `attendee:` and `language:`, same signature as `GoogleWalletService`. One public method: `pass_data` returns binary `.pkpass` bytes.

Internally builds an in-memory ZIP (via `rubyzip` gem) containing:
- `pass.json` — pass content
- `manifest.json` — SHA1 digest of every other file in the archive
- `signature` — PKCS#7 detached signature of `manifest.json`
- `icon.png`, `icon@2x.png`, `icon@3x.png` — stored at `public/apple_wallet/`
- `logo.png`, `logo@2x.png`, `logo@3x.png` — same directory

Signing uses Ruby's built-in `OpenSSL::PKCS7.sign` with `DETACHED | BINARY` flags. The Apple WWDR G4 intermediate certificate (public, expires 2030) is bundled at `config/apple_wwdr.pem`.

### Credentials (ENV)

| Variable | Description |
|----------|-------------|
| `APPLE_WALLET_PASS_TYPE_ID` | Pass Type Identifier, e.g. `pass.io.synthbit.casatamplarului` |
| `APPLE_WALLET_TEAM_ID` | 10-character Apple Team ID |
| `APPLE_WALLET_CERTIFICATE` | Base64-encoded PEM certificate (extracted from .p12) |
| `APPLE_WALLET_PRIVATE_KEY` | Base64-encoded PEM private key (extracted from .p12) |

`config/apple_wwdr.pem` is committed to the repo (public cert, not sensitive).

### Error class

`AppleWalletService::PassGenerationError < StandardError` — raised on any failure during pass assembly or signing.

## Pass Content (pass.json)

Pass style: `eventTicket`

| Field type | Key | Value |
|------------|-----|-------|
| Primary | `event` | Event name (localized, falls back to `ro-RO`) |
| Secondary | `date` | Formatted start date/time |
| Secondary | `venue` | `event.location_name` |
| Auxiliary | `attendee` | `"#{first_name} #{last_name}"` |
| Back | `order` | Order reference (for support) |
| Barcode | — | QR, value = `attendee.qr_code` (e.g. `CT-2026-ABC123-42`) |

Other fields:
- `serialNumber`: `attendee.qr_code` — unique per attendee, doubles as idempotency key
- `organizationName`: `"Casa Tâmplarului"`
- `description`: event name (shown on lock screen / notifications)
- `passTypeIdentifier`: from `APPLE_WALLET_PASS_TYPE_ID`
- `teamIdentifier`: from `APPLE_WALLET_TEAM_ID`
- Colors: dark background (`rgb(20, 20, 20)`), white foreground (`rgb(255, 255, 255)`) — defined as constants in the service

No `stripImage` or `heroImage` for this iteration (can be added later once image dimensions are confirmed).

## Routes

Added alongside the existing Google Wallet routes in `config/routes.rb`:

```
GET /api/v1/auth/me/bookings/:order_reference/wallet/apple
  → me/bookings#wallet_apple

GET /api/v1/auth/me/bookings/:order_reference/attendees/:id/wallet/apple
  → me/bookings#wallet_apple_attendee
```

Both require JWT authentication (same `before_action :authenticate_user!` as other booking routes).

## Controller

Two new actions in `app/controllers/api/v1/auth/me/bookings_controller.rb`:

**`wallet_apple`** — order-level. Same attendee-lookup logic as `wallet_google`: finds attendee by `user_id`, falls back to first attendee if the order belongs to the current user.

**`wallet_apple_attendee`** — per-attendee. Same logic as `wallet_google_attendee`: finds attendee by `id` and `user_id` on the order, no fallback.

Both respond with:
```ruby
send_data service.pass_data,
  type: 'application/vnd.apple.pkpass',
  filename: "ticket-#{order.order_reference}.pkpass",
  disposition: 'attachment'
```

Error handling: rescue `AppleWalletService::PassGenerationError`, log, render `500`.

## Image Assets

Placeholder PNGs committed at `public/apple_wallet/`:
- `icon.png` (29×29), `icon@2x.png` (58×58), `icon@3x.png` (87×87)
- `logo.png` (160×50), `logo@2x.png` (320×100), `logo@3x.png` (480×150)

These are placeholders — real brand assets replace them once Apple Developer membership activates and pass design is finalized. The service reads them from disk at pass-generation time.

## Testing

**`test/services/apple_wallet_service_test.rb`**
- Generate a pass with a fixture attendee using a throwaway self-signed cert + key created in test setup via OpenSSL
- Assert returned bytes are a valid ZIP
- Assert ZIP contains `pass.json`, `manifest.json`, `signature`, and all image files
- Parse `pass.json`, assert `serialNumber == attendee.qr_code`, barcode value, event name, attendee name

**Controller integration tests** (extend existing booking controller tests)
- Stub `AppleWalletService#pass_data` to return dummy bytes
- Assert `200`, `Content-Type: application/vnd.apple.pkpass`, non-empty body
- Assert `404` for wrong user / wrong order reference

## Dependencies

- Add `gem "rubyzip"` to `Gemfile`
- Bundle `config/apple_wwdr.pem` (Apple WWDR G4 certificate, public)
- Add placeholder images to `public/apple_wallet/`
- Add 4 ENV vars to `.env.example`
