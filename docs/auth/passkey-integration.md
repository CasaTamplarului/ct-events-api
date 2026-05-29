# Passkey (WebAuthn) — BE Integration Guide

## Overview

Passkeys let users sign in with Face ID, fingerprint, or device PIN instead of a password. The browser handles the cryptography; the BE needs to generate challenges, verify responses, and store public keys.

Recommended Rails gem: [`webauthn`](https://github.com/cedarcode/webauthn-ruby) (maintained by Cedarcode, used by GitHub).

---

## Configuration

```ruby
# config/initializers/webauthn.rb
WebAuthn.configure do |config|
  config.origin = ENV["APP_ORIGIN"]            # e.g. "https://casatamplarului.ro"
  config.rp_name = "Casa Tâmplarului"
  # config.rp_id defaults to the host portion of origin — no need to set explicitly
end
```

`APP_ORIGIN` must match the exact origin the browser is on (scheme + host + port). For local dev: `http://localhost:3000`.

---

## Database

```ruby
create_table :passkeys do |t|
  t.references :user, null: false, foreign_key: true
  t.string     :external_id,       null: false   # credential.id (base64url)
  t.string     :public_key,        null: false   # CBOR-encoded public key (from webauthn gem)
  t.string     :sign_count,        null: false, default: "0"
  t.string     :nickname                         # optional user-friendly label
  t.timestamps
end
add_index :passkeys, :external_id, unique: true
```

---

## Endpoints

### 1. `POST /api/v1/auth/passkeys/register/options`

Generates a registration challenge. **Requires authentication** (JWT in Authorization header).

**Request:** empty body

**Response — 200 OK:**

```json
{
  "challenge": "<base64url>",
  "rp": {
    "name": "Casa Tâmplarului",
    "id": "casatamplarului.ro"
  },
  "user": {
    "id": "<base64url of user.id>",
    "name": "user@example.com",
    "displayName": "Ion Popescu"
  },
  "pubKeyCredParams": [
    { "type": "public-key", "alg": -7 },
    { "type": "public-key", "alg": -257 }
  ],
  "timeout": 60000,
  "attestation": "none",
  "authenticatorSelection": {
    "residentKey": "required",
    "userVerification": "preferred"
  },
  "excludeCredentials": [
    { "id": "<base64url>", "type": "public-key" }
  ]
}
```

`excludeCredentials` should list the user's already-registered passkeys so the browser rejects duplicates.

Store the generated challenge in the session (or a short-lived cache keyed by user ID) — you'll need it to verify the registration response.

**Rails example:**

```ruby
def register_options
  user = current_user
  options = WebAuthn::Credential.options_for_create(
    user: { id: WebAuthn.configuration.encoder.encode(user.id.to_s), name: user.email, display_name: user.display_name },
    exclude: user.passkeys.map { |pk| { id: pk.external_id, type: "public-key" } },
    authenticator_selection: { resident_key: "required", user_verification: "preferred" },
    attestation: "none"
  )
  session[:passkey_registration_challenge] = options.challenge
  render json: options
end
```

---

### 2. `POST /api/v1/auth/passkeys/register`

Verifies the credential created by the browser and stores the passkey. **Requires authentication** (JWT in Authorization header).

**Request:**

```json
{
  "id": "<credential id, base64url>",
  "rawId": "<same as id>",
  "type": "public-key",
  "response": {
    "clientDataJSON": "<base64url>",
    "attestationObject": "<base64url>"
  }
}
```

**Response — 200 OK:**

```json
{ "verified": true }
```

**Errors:**

| Status | When |
|--------|------|
| `422` | Verification failed (wrong challenge, wrong origin, etc.) |
| `409` | Passkey already registered |

**Rails example:**

```ruby
def register
  webauthn_credential = WebAuthn::Credential.from_create(params)
  webauthn_credential.verify(session[:passkey_registration_challenge])

  current_user.passkeys.create!(
    external_id: webauthn_credential.id,
    public_key:  webauthn_credential.public_key,
    sign_count:  webauthn_credential.sign_count
  )
  session.delete(:passkey_registration_challenge)
  render json: { verified: true }
rescue WebAuthn::Error => e
  render json: { error: e.message }, status: :unprocessable_entity
end
```

---

### 3. `POST /api/v1/auth/passkeys/authenticate/options`

Generates an authentication challenge. **No authentication required** — the user is not signed in yet.

**Request:** empty body

**Response — 200 OK:**

```json
{
  "challenge": "<base64url>",
  "timeout": 60000,
  "rpId": "casatamplarului.ro",
  "allowCredentials": [],
  "userVerification": "preferred"
}
```

`allowCredentials` must be an **empty array** — this triggers discoverable credential flow, which lets the browser present a picker of all passkeys registered for this site.

Store the challenge in the session.

**Rails example:**

```ruby
def authenticate_options
  options = WebAuthn::Credential.options_for_get(
    allow: [],
    user_verification: "preferred"
  )
  session[:passkey_authentication_challenge] = options.challenge
  render json: options
end
```

---

### 4. `POST /api/v1/auth/passkeys/authenticate`

Verifies the assertion from the browser and returns a JWT + user. **No authentication required.**

**Request:**

```json
{
  "id": "<credential id, base64url>",
  "rawId": "<same as id>",
  "type": "public-key",
  "response": {
    "clientDataJSON": "<base64url>",
    "authenticatorData": "<base64url>",
    "signature": "<base64url>",
    "userHandle": "<base64url of user.id, or null>"
  }
}
```

**Response — 200 OK:**

Same shape as email/password and Google sign-in:

```json
{
  "jwt": "eyJhbGciOiJIUzI1NiJ9...",
  "user": {
    "id": 42,
    "first_name": "Ion",
    "last_name": "Popescu",
    "email": "ion@example.com",
    "avatar_url": null,
    "phone_number": null,
    "church_name": null,
    "city": null,
    "can_change_email": true,
    "language": "ro-RO"
  }
}
```

**Errors:**

| Status | When |
|--------|------|
| `401` | Verification failed |
| `404` | Passkey not found (`id` doesn't match any stored credential) |

**Rails example:**

```ruby
def authenticate
  webauthn_credential = WebAuthn::Credential.from_get(params)

  passkey = Passkey.find_by!(external_id: webauthn_credential.id)
  webauthn_credential.verify(
    session[:passkey_authentication_challenge],
    public_key: passkey.public_key,
    sign_count: passkey.sign_count.to_i
  )

  passkey.update!(sign_count: webauthn_credential.sign_count)
  session.delete(:passkey_authentication_challenge)

  user = passkey.user
  jwt  = JwtService.encode(user_id: user.id)
  render json: { jwt:, user: UserSerializer.new(user) }
rescue WebAuthn::Error => e
  render json: { error: e.message }, status: :unauthorized
rescue ActiveRecord::RecordNotFound
  render json: { error: "Passkey not found" }, status: :not_found
end
```

---

## Notes

- **Sign count**: the `webauthn` gem automatically rejects replayed assertions if `sign_count` in the stored credential is lower than the one in the assertion — no extra code needed. Just update it after each successful authentication.
- **`userHandle`**: the FE sends the `userHandle` returned by the browser, which is the base64url-encoded user ID used when registering. You can use this to look up the user instead of scanning all passkeys — but matching by `external_id` (credential id) is equally reliable.
- **Session storage**: the challenge must survive between the options request and the verify request. If your API is stateless (no session), store challenges in Redis with a 5-minute TTL keyed by a UUID, and return/accept that UUID in the options response / verify request.
- **Language**: pass `?lang=ro-RO` in the query string if you want localised error messages (consistent with other auth endpoints).
