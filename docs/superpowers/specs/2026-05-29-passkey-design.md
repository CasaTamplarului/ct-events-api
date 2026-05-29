# Passkey (WebAuthn) Implementation Design

**Goal:** Add passkey sign-in and registration to the existing auth system — 6 endpoints covering registration, authentication, and passkey management — using the `webauthn` gem and a stateless JWT-signed challenge token so no Redis or additional infrastructure is needed.

**Architecture:** `PasskeyChallengeService` signs short-lived JWTs containing the WebAuthn challenge (5-minute TTL, `HS256`, existing `jwt_secret`). The client receives the token from an `/options` call, passes it back with the credential on the `/register` or `/authenticate` call, and the server verifies it before handing the challenge to the `webauthn` gem. `PasskeysController` handles all 6 actions. `Passkey` model stores public keys and sign counts.

**Tech Stack:** Rails 8.1, `webauthn` gem (cedarcode), `jwt` gem (already present), PostgreSQL.

---

## Endpoints

All routes are under `/api/v1/auth/`.

| Method | Path | Auth required | Purpose |
|--------|------|---------------|---------|
| `POST` | `/auth/passkeys/register/options` | Yes (JWT) | Generate registration challenge |
| `POST` | `/auth/passkeys/register` | Yes (JWT) | Verify credential + store passkey |
| `POST` | `/auth/passkeys/authenticate/options` | No | Generate authentication challenge |
| `POST` | `/auth/passkeys/authenticate` | No | Verify credential + return JWT + user |
| `GET` | `/auth/passkeys` | Yes (JWT) | List current user's passkeys |
| `DELETE` | `/auth/passkeys/:id` | Yes (JWT) | Delete a passkey by id |

---

## Routes

```ruby
namespace :auth do
  scope '/passkeys' do
    post 'register/options',     to: 'passkeys#register_options'
    post 'register',             to: 'passkeys#register'
    post 'authenticate/options', to: 'passkeys#authenticate_options'
    post 'authenticate',         to: 'passkeys#authenticate'
    get  '/',                    to: 'passkeys#index'
    delete ':id',                to: 'passkeys#destroy'
  end
end
```

---

## Challenge Token

`PasskeyChallengeService` signs and verifies challenge JWTs.

**Payload:**
```json
{
  "challenge": "<base64url WebAuthn challenge>",
  "purpose":   "passkey_registration" | "passkey_authentication",
  "user_id":   42,
  "exp":       <unix timestamp, 5 minutes from now>
}
```

- `purpose` prevents a registration challenge being replayed as an authentication challenge and vice versa.
- `user_id` is the authenticated user's id for registration, `nil` for authentication (user is unknown at that point).
- Uses `HS256` + the existing `Rails.application.credentials.dig(:auth, :jwt_secret)` — no new secret needed.
- Expires in 5 minutes — tight enough to prevent replay, long enough for slow biometrics.

**Interface:**
```ruby
PasskeyChallengeService.encode(challenge:, purpose:, user_id: nil) # → String (JWT)
PasskeyChallengeService.decode(token, expected_purpose:)           # → Hash or raises InvalidTokenError
```

`decode` verifies signature, checks expiry, and asserts `purpose == expected_purpose`. Any failure raises `PasskeyChallengeService::InvalidTokenError`.

---

## PasskeysController

**File:** `app/controllers/api/v1/auth/passkeys_controller.rb`

Includes `Authenticatable` and `LocaleSetter`. `authenticate_user!` is applied to `register_options`, `register`, `index`, and `destroy`. `set_locale` applies to all actions.

### `register_options`

1. Build WebAuthn creation options (excluding credentials the user already has).
2. Sign challenge into a JWT with `purpose: 'passkey_registration'` and `user_id: current_user.id`.
3. Return the options JSON merged with `challenge_token`.

### `register`

1. Decode `params[:challenge_token]` with `expected_purpose: 'passkey_registration'`.
2. Assert `payload['user_id'] == current_user.id` — guards against a different user hijacking an options call.
3. Verify the credential via `WebAuthn::Credential.from_create(params).verify(challenge)`.
4. Create `Passkey` record. Return `{ verified: true }`.
5. Rescue `WebAuthn::Error` → 422. Rescue `ActiveRecord::RecordNotUnique` → 409.

### `authenticate_options`

1. Build WebAuthn get options with `allow: []` (discoverable credential flow).
2. Sign challenge into a JWT with `purpose: 'passkey_authentication'` and `user_id: nil`.
3. Return the options JSON merged with `challenge_token`.

### `authenticate`

1. Decode `params[:challenge_token]` with `expected_purpose: 'passkey_authentication'`.
2. Look up `Passkey` by `external_id: params[:id]` — the credential id from the browser's WebAuthn response body (base64url string, not the database primary key). Raises `ActiveRecord::RecordNotFound` → 404.
3. Verify the assertion via `WebAuthn::Credential.from_get(params).verify(challenge, public_key:, sign_count:)`.
4. Update `passkey.sign_count`.
5. Issue app JWT + return `user_json` (same 10-field shape as all other auth endpoints).
6. Rescue `WebAuthn::Error` → 401.

### `index`

Return `current_user.passkeys.order(:created_at).map { |pk| { id: pk.id, nickname: pk.nickname, created_at: pk.created_at } }`.

### `destroy`

Find passkey by `params[:id]` scoped to `current_user.passkeys` (404 if not found or not owned). Destroy it. Return `204 No Content`.

---

## PasskeyChallengeService

**File:** `app/services/passkey_challenge_service.rb`

```
class PasskeyChallengeService
  class InvalidTokenError < StandardError; end

  PURPOSE_REGISTER     = 'passkey_registration'
  PURPOSE_AUTHENTICATE = 'passkey_authentication'
  EXPIRY = 5.minutes

  .encode(challenge:, purpose:, user_id: nil) → String
  .decode(token, expected_purpose:)           → Hash (payload) or raises InvalidTokenError
end
```

Private helpers: `.secret` reads `credentials.dig(:auth, :jwt_secret)`.

---

## Passkey Model

**File:** `app/models/passkey.rb`

```ruby
class Passkey < ApplicationRecord
  belongs_to :user
  validates :external_id, :public_key, presence: true
  validates :external_id, uniqueness: true
end
```

`User` gets `has_many :passkeys, dependent: :destroy`.

---

## Database Migration

```ruby
create_table :passkeys do |t|
  t.references :user,        null: false, foreign_key: true
  t.string     :external_id, null: false
  t.string     :public_key,  null: false
  t.integer    :sign_count,  null: false, default: 0
  t.string     :nickname
  t.timestamps
end
add_index :passkeys, :external_id, unique: true
```

---

## WebAuthn Configuration

**File:** `config/initializers/webauthn.rb`

```ruby
WebAuthn.configure do |config|
  config.origin  = Rails.application.credentials.dig(:webauthn, :origin)
  config.rp_name = "Casa Tâmplarului"
end
```

`origin` is the web app's origin — not the API's origin. Example values:
- Production: `https://casatamplarului.ro`
- Development: `http://localhost:5173` (or wherever the FE dev server runs)

Add to Rails credentials:
```yaml
webauthn:
  origin: https://casatamplarului.ro
```

`rp_id` defaults to the hostname portion of `origin` automatically (e.g. `casatamplarului.ro`).

---

## i18n Keys

Add to both `en.yml` and `ro.yml` under `auth.errors`:

```yaml
# en.yml
invalid_challenge_token: "Invalid or expired challenge"
passkey_verification_failed: "Passkey verification failed"
passkey_not_found: "Passkey not found"
passkey_already_registered: "Passkey already registered"

# ro.yml
invalid_challenge_token: "Provocare invalidă sau expirată"
passkey_verification_failed: "Verificarea passkey a eșuat"
passkey_not_found: "Passkey negăsit"
passkey_already_registered: "Passkey deja înregistrat"
```

---

## Request / Response Reference

### `POST /auth/passkeys/register/options` — 200 OK

```json
{
  "challenge_token": "<jwt>",
  "challenge": "<base64url>",
  "rp": { "name": "Casa Tâmplarului", "id": "casatamplarului.ro" },
  "user": { "id": "<base64url of user.id>", "name": "ion@outlook.com", "displayName": "Ion Popescu" },
  "pubKeyCredParams": [
    { "type": "public-key", "alg": -7 },
    { "type": "public-key", "alg": -257 }
  ],
  "timeout": 60000,
  "attestation": "none",
  "authenticatorSelection": { "residentKey": "required", "userVerification": "preferred" },
  "excludeCredentials": [{ "id": "<base64url>", "type": "public-key" }]
}
```

### `POST /auth/passkeys/register` — 200 OK

Request:
```json
{
  "challenge_token": "<jwt>",
  "nickname": "MacBook Pro",
  "id": "<base64url>",
  "rawId": "<base64url>",
  "type": "public-key",
  "response": {
    "clientDataJSON": "<base64url>",
    "attestationObject": "<base64url>"
  }
}
```

Response: `{ "verified": true }`

### `POST /auth/passkeys/authenticate/options` — 200 OK

```json
{
  "challenge_token": "<jwt>",
  "challenge": "<base64url>",
  "timeout": 60000,
  "rpId": "casatamplarului.ro",
  "allowCredentials": [],
  "userVerification": "preferred"
}
```

### `POST /auth/passkeys/authenticate` — 200 OK

Request:
```json
{
  "challenge_token": "<jwt>",
  "id": "<base64url>",
  "rawId": "<base64url>",
  "type": "public-key",
  "response": {
    "clientDataJSON": "<base64url>",
    "authenticatorData": "<base64url>",
    "signature": "<base64url>",
    "userHandle": "<base64url or null>"
  }
}
```

Response — same shape as all other sign-in endpoints:
```json
{
  "jwt": "eyJhbGciOiJIUzI1NiJ9...",
  "user": {
    "id": 42,
    "first_name": "Ion",
    "last_name": "Popescu",
    "email": "ion@outlook.com",
    "avatar_url": null,
    "phone_number": null,
    "church_name": null,
    "city": null,
    "language": "ro-RO",
    "can_change_email": true
  }
}
```

### `GET /auth/passkeys` — 200 OK

```json
[
  { "id": 1, "nickname": "MacBook Pro", "created_at": "2026-05-29T10:00:00.000Z" },
  { "id": 2, "nickname": null, "created_at": "2026-05-29T11:00:00.000Z" }
]
```

### `DELETE /auth/passkeys/:id` — 204 No Content

---

## Error Responses

| Scenario | Status | Body |
|----------|--------|------|
| `challenge_token` missing, expired, or wrong purpose | 401 | `{ "error": "Invalid or expired challenge" }` |
| WebAuthn registration verification fails | 422 | `{ "error": "Passkey verification failed" }` |
| Credential already registered | 409 | `{ "error": "Passkey already registered" }` |
| Passkey not found on authenticate | 404 | `{ "error": "Passkey not found" }` |
| WebAuthn authentication verification fails | 401 | `{ "error": "Passkey verification failed" }` |
| `DELETE` passkey not owned by user | 404 | `{ "error": "Passkey not found" }` |

---

## Testing

### `spec/services/passkey_challenge_service_spec.rb`

Unit tests — no mocking needed (fast JWT operations):
- `encode` + `decode` round-trip returns correct challenge and user_id
- `decode` with wrong `expected_purpose` raises `InvalidTokenError`
- `decode` with expired token raises `InvalidTokenError`
- `decode` with tampered signature raises `InvalidTokenError`

### `spec/requests/api/v1/auth/passkeys_spec.rb`

Request-level tests. Stub WebAuthn boundary calls:
- `WebAuthn::Credential.options_for_create` → returns a fake options object with `.challenge`, `.to_json`
- `WebAuthn::Credential.options_for_get` → same
- `WebAuthn::Credential.from_create` → returns a double with `.verify(challenge)` (pass or raise `WebAuthn::Error`)
- `WebAuthn::Credential.from_get` → returns a double with `.verify(...)`, `.id`, `.sign_count`

Covers:
- `register_options` returns options + `challenge_token` (authenticated)
- `register_options` without auth → 401
- `register` with valid credential → `{ verified: true }`, Passkey created
- `register` with invalid challenge token → 401
- `register` with WebAuthn error → 422
- `register` duplicate credential → 409
- `authenticate_options` returns options + `challenge_token` (no auth needed)
- `authenticate` with valid credential → 200, JWT + user
- `authenticate` with unknown passkey id → 404
- `authenticate` with invalid challenge token → 401
- `authenticate` with WebAuthn error → 401
- `index` returns list of passkeys (authenticated)
- `index` without auth → 401
- `destroy` removes passkey → 204
- `destroy` passkey belonging to another user → 404
- `destroy` without auth → 401
