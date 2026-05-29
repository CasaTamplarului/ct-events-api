# Microsoft Sign-In Implementation Design

**Goal:** Add `POST /api/v1/auth/microsoft` that accepts a Microsoft `id_token` from MSAL, validates it locally via JWKS, and returns a JWT + user object — mirroring the existing Google sign-in flow.

**Architecture:** `MicrosoftAuthService` fetches Microsoft's public JWKS keys (cached 1 hour), validates the signed JWT locally using the existing `jwt` gem, then `MicrosoftsController` finds or creates the user using the same pattern as `GooglesController`. No new gems needed.

**Tech Stack:** Rails 8.1, `jwt` gem (already in project), `Net::HTTP` (stdlib), Microsoft Identity Platform JWKS, existing `UserIdentity`/`User` models.

---

## Endpoint

```
POST /api/v1/auth/microsoft
Content-Type: application/json

{ "id_token": "<microsoft_id_token>" }
```

Response (200) — same shape as Google and Facebook:
```json
{
  "jwt": "<jwt>",
  "user": {
    "id": 1,
    "first_name": "Ion",
    "last_name": "Popescu",
    "email": "ion@outlook.com",
    "avatar_url": null,
    "phone_number": null,
    "church_name": null,
    "city": null,
    "language": null,
    "can_change_email": false
  }
}
```

`avatar_url` is always `null` — Microsoft `id_token`s do not include a photo URL. `can_change_email` is always `false` for Microsoft-only accounts.

---

## MicrosoftAuthService

**File:** `app/services/microsoft_auth_service.rb`

### JWKS endpoint

```
https://login.microsoftonline.com/consumers/discovery/v2.0/keys
```

`consumers` is Microsoft's fixed tenant for personal accounts (Outlook, Hotmail, Live).

### JWKS caching

Keys are cached in a class-level instance variable with a 1-hour TTL:

```ruby
@jwks_cache       # JWT::JWK::Set
@jwks_fetched_at  # Time
JWKS_TTL = 1.hour
```

On each call:
1. If cache is empty or older than 1 hour → fetch fresh keys
2. Decode JWT using cached keys
3. If `JWT::JWKsFetchError` or key not found (`kid` mismatch) → refresh cache once and retry
4. Any remaining failure raises `InvalidTokenError`

### JWT validation

Enforced by the `jwt` gem:

| Claim | Expected value |
|-------|---------------|
| `iss` | `https://login.microsoftonline.com/9188040d-6c67-4c5b-b112-36a304b66dad/v2.0` |
| `aud` | `auth.microsoft_client_id` from Rails credentials |
| `exp` | Must be in the future |
| Signature | Must match a key in the JWKS |

`9188040d-6c67-4c5b-b112-36a304b66dad` is Microsoft's fixed consumer tenant ID — hardcoded, not configurable.

### Return value

```ruby
{
  uid:        payload['sub'],           # always present
  email:      payload['email'],         # always present for personal accounts
  first_name: payload['given_name'].to_s,
  last_name:  payload['family_name'].to_s,
  avatar_url: nil
}
```

### Credentials

Only `auth.microsoft_client_id` is needed — client secret is not required for id_token validation (public-key operation).

---

## MicrosoftsController

**File:** `app/controllers/api/v1/auth/microsofts_controller.rb`

Mirrors `GooglesController` exactly:

- Validates `id_token` param present (422 if blank, reuses existing `auth.errors.id_token_required` key)
- Calls `MicrosoftAuthService.call(params[:id_token])`
- Handles `MicrosoftAuthService::InvalidTokenError` → 401
- Handles `ActiveRecord::RecordNotUnique` race condition
- `find_or_create_user` — same logic as Google (no nil email handling needed; Microsoft personal accounts always have email)
- `user_json` — same 10 fields as all other auth controllers

---

## Routes

```ruby
namespace :auth do
  resource :microsoft, only: :create   # POST /api/v1/auth/microsoft
  resource :facebook,  only: :create
  resource :google,    only: :create
  # ...
end
```

---

## i18n

Add to both locale files:

`en.yml`:
```yaml
auth:
  errors:
    invalid_microsoft_token: "Invalid Microsoft token"
```

`ro.yml`:
```yaml
auth:
  errors:
    invalid_microsoft_token: "Token Microsoft invalid"
```

`id_token_required` already exists (shared with Google).

---

## Error Responses

| Scenario | Status | Body |
|----------|--------|------|
| Missing `id_token` | 422 | `{ "error": "id_token is required" }` |
| Invalid / expired token | 401 | `{ "error": "Invalid Microsoft token" }` |
| Wrong audience (wrong app) | 401 | `{ "error": "Invalid Microsoft token" }` |
| JWKS fetch failure | 401 | `{ "error": "Invalid Microsoft token" }` |

---

## Testing

### `spec/services/microsoft_auth_service_spec.rb`

WebMock stubs the JWKS HTTP fetch. Tests generate real signed JWTs using the `jwt` gem with a test RSA key pair — the public half is returned by the JWKS stub, the private half signs the test tokens. This exercises the actual crypto path.

Covers:
- Valid token returns correct hash (uid, email, first_name, last_name, avatar_url nil)
- Expired token raises `InvalidTokenError`
- Wrong `aud` raises `InvalidTokenError`
- Wrong `iss` raises `InvalidTokenError`
- Bad signature raises `InvalidTokenError`
- JWKS fetch returns non-2xx → `InvalidTokenError`
- Key rotation: kid not in cache triggers one refresh, succeeds on retry
- Key rotation: kid not found even after refresh → `InvalidTokenError`
- JWKS cache is reused within TTL (only one HTTP call for two sign-ins)

### `spec/requests/api/v1/auth/microsoft_spec.rb`

Stubs `MicrosoftAuthService.call` at the service boundary. Covers:
- New user created on first sign-in
- Idempotent (existing UserIdentity)
- Email-match links Microsoft identity to existing user, updates avatar_url (nil)
- Attendee backfill on new user
- Attendee backfill on email-matched existing user
- Missing `id_token` → 422
- `InvalidTokenError` → 401
- `can_change_email: false` for Microsoft-only account
- `language` present in response
