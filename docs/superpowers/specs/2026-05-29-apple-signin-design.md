# Apple Sign-In Implementation Design

**Goal:** Add Apple Sign-In to the existing auth system — a single `POST /api/v1/auth/apple` endpoint that handles both iOS native and web clients — using the `jwt` gem and Apple's JWKS endpoint, consistent with the existing Microsoft and Google implementations.

**Architecture:** `AppleAuthService` verifies Apple identity tokens (RS256 JWTs) against Apple's JWKS, accepting an array of audiences so one endpoint serves both the iOS Bundle ID and the web Service ID. `ApplesController` mirrors `GooglesController`/`MicrosoftsController` exactly. No new gems required.

**Tech Stack:** Rails 8.1, `jwt` gem (already present), PostgreSQL.

---

## Endpoint

| Method | Path | Auth required | Purpose |
|--------|------|---------------|---------|
| `POST` | `/api/v1/auth/apple` | No | Verify Apple id_token + return JWT + user |

Route: `resource :apple, only: :create` inside `namespace :auth`.

---

## Request

```json
{
  "id_token": "<apple_identity_token>"
}
```

`id_token` is the `identityToken` string from `ASAuthorizationAppleIDCredential` (native iOS) or the `id_token` from Apple's JS SDK response (web). Both are RS256 JWTs signed by Apple.

Optional: `language` param for locale (same as other auth endpoints).

---

## AppleAuthService

**File:** `app/services/apple_auth_service.rb`

Mirrors `MicrosoftAuthService` structurally:

### JWKS

- **Endpoint:** `https://appleid.apple.com/auth/keys`
- **Algorithm:** RS256
- **Cache:** class-level `@jwks_cache` + `@jwks_fetched_at`, 1-hour TTL
- **Retry:** single retry on `'Could not find public key'` (stale key rotation)

### JWT Verification

```ruby
JWT.decode(id_token, nil, true, {
  algorithms: ['RS256'],
  jwks: fetch_jwks,
  iss: 'https://appleid.apple.com',
  verify_iss: true,
  aud: bundle_ids,      # Array — accepts any value in the array
  verify_aud: true
})
```

`bundle_ids` reads `Rails.application.credentials.dig(:auth, :apple_bundle_ids)` — an array of strings containing both the iOS Bundle ID and the web Service ID.

### Additional Validation

After JWT decode, assert `payload['email_verified'] == true` (Apple may return unverified emails in edge cases). Raise `InvalidTokenError` if not verified.

### Return Value

```ruby
{
  uid:        payload['sub'],       # stable Apple user ID, opaque string
  email:      payload['email'],     # may be @privaterelay.appleid.com
  first_name: derive_first_name(payload['email']),
  last_name:  nil,                  # Apple never provides this in the JWT
  avatar_url: nil                   # Apple never provides this
}
```

### Name Derivation

Apple never includes the user's name in the JWT. `derive_first_name` uses the email as a fallback:

- For regular emails (`ion@icloud.com`) → extract the prefix before `@`: `"ion"`
- For privaterelay addresses (domain is `privaterelay.appleid.com`) → use `"Apple"` (the prefix is a random opaque string, not useful as a display name)
- Detection: `email.end_with?('@privaterelay.appleid.com')`

### Error Handling

All failures raise `AppleAuthService::InvalidTokenError`:
- Missing/invalid credentials configuration
- JWKS fetch failure (network, non-200, invalid JSON)
- JWT expired, wrong issuer, audience not in accepted list, bad signature
- `email_verified` is not `true`

---

## ApplesController

**File:** `app/controllers/api/v1/auth/apples_controller.rb`

Mirrors `MicrosoftsController` exactly, substituting `AppleAuthService` and `'apple'` as the provider string.

```ruby
class ApplesController < ActionController::API
  include LocaleSetter
  before_action :set_locale

  def create
    # 1. Validate id_token presence → 422 if blank
    # 2. Call AppleAuthService.call(params[:id_token])
    # 3. find_or_create_user(apple_data)
    # 4. JwtService.encode(user.id) → render jwt + user_json
    # Rescue AppleAuthService::InvalidTokenError → 401
    # Rescue ActiveRecord::RecordNotUnique → race condition fallback
  end
end
```

### find_or_create_user

Identical three-step pattern used by Google/Microsoft/Facebook:

1. `UserIdentity.find_by(provider: 'apple', uid: apple_data[:uid])` → return `identity.user`
2. `User.find_by(email: apple_data[:email])` → link Apple identity (no avatar update — Apple never provides one) + attendee backfill → return user
3. Create new `User` + `UserIdentity` + attendee backfill

### user_json

Same 10-field shape as all other auth endpoints:

```json
{
  "id": 42,
  "first_name": "ion",
  "last_name": null,
  "email": "ion@icloud.com",
  "avatar_url": null,
  "phone_number": null,
  "church_name": null,
  "city": null,
  "language": null,
  "can_change_email": false
}
```

`can_change_email` is `false` for Apple-only accounts (no `email` provider identity).

---

## Credentials

Add to Rails credentials:

```yaml
auth:
  apple_bundle_ids:
    - com.example.app          # iOS Bundle ID (placeholder)
    - com.example.app.web      # Web Service ID (placeholder)
```

These are placeholders — real values are configured in Apple Developer Console once the team sets up the App ID and Service ID.

---

## Routes

```ruby
namespace :auth do
  resource :apple, only: :create
  # ... existing routes
end
```

---

## i18n Keys

Add to `en.yml` and `ro.yml` under `auth.errors:`:

```yaml
# en.yml
id_token_required: "id_token is required"   # already exists — reuse
invalid_apple_token: "Invalid Apple token"

# ro.yml
invalid_apple_token: "Token Apple invalid"
```

---

## Error Responses

| Scenario | Status | Body |
|----------|--------|------|
| `id_token` missing or blank | 422 | `{ "error": "id_token is required" }` |
| Token invalid, expired, wrong audience, bad signature | 401 | `{ "error": "Invalid Apple token" }` |
| `email_verified` is false | 401 | `{ "error": "Invalid Apple token" }` |

---

## Testing

### `spec/services/apple_auth_service_spec.rb`

Unit tests — real RSA key signing + WebMock JWKS stubs (same pattern as `microsoft_auth_service_spec.rb`):

- Valid token → returns correct 5-field hash
- Expired token → raises `InvalidTokenError`
- Wrong issuer → raises `InvalidTokenError`
- Audience matches first bundle_id → succeeds
- Audience matches second bundle_id → succeeds
- Audience not in list → raises `InvalidTokenError`
- `email_verified: false` → raises `InvalidTokenError`
- JWKS fetch returns 503 → raises `InvalidTokenError`
- Unknown `kid` → retries JWKS once, then raises `InvalidTokenError`
- Regular email → `first_name` equals email prefix
- Privaterelay email → `first_name` equals `"Apple"`, `last_name` nil

### `spec/requests/api/v1/auth/apple_spec.rb`

Request tests — `AppleAuthService.call` stubbed:

- New user → 200, JWT present, User + UserIdentity created
- Second sign-in (same Apple uid) → 200, same user, idempotent
- Email-match → links Apple identity to existing User
- Attendee backfill — new user path: attendees with matching email get `user_id` set
- Attendee backfill — email-match path: attendees with matching email get `user_id` set
- Missing `id_token` → 422 with `"id_token is required"`
- Invalid token (`InvalidTokenError`) → 401 with `"Invalid Apple token"`

---

## Notes

- **Privaterelay emails** are stored as-is. They are valid unique email addresses. If a user later signs in with a different method using the same underlying email, the accounts will not be automatically linked (Apple does not expose the real email when Hide My Email is active). This is acceptable — the user can contact support if needed.
- **`last_name` is always `nil`** at account creation. The user can set it via `PATCH /api/v1/auth/me`.
- The **JWT secret** used by `AppleAuthService` for JWKS verification is Apple's public key (fetched from their JWKS endpoint), not the app's `jwt_secret`. No credentials change needed for the signing key.
- Once the team configures the Apple App ID and Service ID in Apple Developer Console, update `apple_bundle_ids` in credentials with the real values.
