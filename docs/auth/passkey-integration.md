# Passkey (WebAuthn) — FE Integration Guide

## Overview

Passkeys let users sign in with Face ID, fingerprint, or device PIN instead of a password. The browser handles the cryptography; the API generates challenges, verifies responses, and stores public keys.

**Stateless challenge design** — no server-side session needed. Each options response includes a signed `challenge_token` JWT (5-minute TTL). The FE echoes it back in the verify request.

---

## Environment

Set `WEBAUTHN_ORIGIN` to the exact origin the browser is on (scheme + host + port):

```
WEBAUTHN_ORIGIN=https://ctevents.chiciudean.family   # prod
WEBAUTHN_ORIGIN=http://localhost:3003                 # dev
```

---

## Endpoint Summary

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| `POST` | `/api/v1/auth/passkeys/register/options` | JWT | Get registration challenge |
| `POST` | `/api/v1/auth/passkeys/register` | JWT | Verify and store new passkey |
| `POST` | `/api/v1/auth/passkeys/authenticate/options` | No | Get authentication challenge |
| `POST` | `/api/v1/auth/passkeys/authenticate` | No | Verify passkey and get JWT |
| `GET`  | `/api/v1/auth/passkeys` | JWT | List user's passkeys |
| `DELETE` | `/api/v1/auth/passkeys/:id` | JWT | Remove a passkey |

Proxy shortcuts (if your server forwards these):

| Proxy | Forwards to |
|-------|-------------|
| `GET /api/auth/passkeys` | `GET /api/v1/auth/passkeys` |
| `DELETE /api/auth/passkeys/:id` | `DELETE /api/v1/auth/passkeys/:id` |

---

## Registration Flow

### Step 1 — `POST /api/v1/auth/passkeys/register/options`

Requires Bearer JWT. Returns the WebAuthn creation options plus a `challenge_token`.

**Request:** empty body

**Response — 200 OK:**

```json
{
  "challenge": "<base64url>",
  "rp": {
    "name": "Casa Tâmplarului",
    "id": "ctevents.chiciudean.family"
  },
  "user": {
    "id": "<base64url of user.id>",
    "name": "ion@example.com",
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
  ],
  "challenge_token": "<signed JWT — echo this back in Step 2>"
}
```

`excludeCredentials` lists already-registered passkeys so the browser rejects duplicates.

**JS example:**

```js
const res = await fetch('/api/v1/auth/passkeys/register/options', {
  method: 'POST',
  headers: { 'Authorization': `Bearer ${jwt}`, 'Content-Type': 'application/json' },
})
const options = await res.json()
const { challenge_token, ...creationOptions } = options

const credential = await navigator.credentials.create({ publicKey: parseCreationOptions(creationOptions) })
```

(`parseCreationOptions` decodes base64url fields — use `@simplewebauthn/browser` or similar.)

---

### Step 2 — `POST /api/v1/auth/passkeys/register`

Requires Bearer JWT. Verifies the credential and stores the passkey.

**Request:**

```json
{
  "challenge_token": "<from Step 1>",
  "nickname": "Face ID",
  "id": "<credential id, base64url>",
  "rawId": "<same as id>",
  "type": "public-key",
  "response": {
    "clientDataJSON": "<base64url>",
    "attestationObject": "<base64url>"
  }
}
```

`nickname` is optional — a user-friendly label shown in the passkey list.

**Response — 200 OK:**

```json
{ "verified": true }
```

**Errors:**

| Status | Body | When |
|--------|------|------|
| `401` | `{ "error": "Invalid challenge token" }` | `challenge_token` missing, expired, or wrong purpose |
| `409` | `{ "error": "Passkey already registered" }` | Credential already stored |
| `422` | `{ "error": "Passkey verification failed" }` | WebAuthn verification error |

**JS example:**

```js
await fetch('/api/v1/auth/passkeys/register', {
  method: 'POST',
  headers: { 'Authorization': `Bearer ${jwt}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    challenge_token,
    nickname: 'Face ID',
    ...serializeCredential(credential),  // encodes ArrayBuffers to base64url
  }),
})
```

---

## Authentication Flow

### Step 1 — `POST /api/v1/auth/passkeys/authenticate/options`

No authentication required. Returns WebAuthn get options plus a `challenge_token`.

**Request:** empty body

**Response — 200 OK:**

```json
{
  "challenge": "<base64url>",
  "timeout": 60000,
  "rpId": "ctevents.chiciudean.family",
  "allowCredentials": [],
  "userVerification": "preferred",
  "challenge_token": "<signed JWT — echo this back in Step 2>"
}
```

`allowCredentials` is always empty — this triggers the browser's discoverable credential picker (shows all passkeys registered for this site).

**JS example:**

```js
const res = await fetch('/api/v1/auth/passkeys/authenticate/options', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
})
const options = await res.json()
const { challenge_token, ...getOptions } = options

const assertion = await navigator.credentials.get({ publicKey: parseGetOptions(getOptions) })
```

---

### Step 2 — `POST /api/v1/auth/passkeys/authenticate`

No authentication required. Verifies the assertion and returns a JWT + user.

**Request:**

```json
{
  "challenge_token": "<from Step 1>",
  "id": "<credential id, base64url>",
  "rawId": "<same as id>",
  "type": "public-key",
  "response": {
    "clientDataJSON": "<base64url>",
    "authenticatorData": "<base64url>",
    "signature": "<base64url>",
    "userHandle": "<base64url of user.id, may be null>"
  }
}
```

**Response — 200 OK:**

Same shape as email/password, Google, Apple, and Microsoft sign-in:

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
    "language": "ro-RO",
    "can_change_email": true
  }
}
```

**Errors:**

| Status | Body | When |
|--------|------|------|
| `401` | `{ "error": "Invalid challenge token" }` | `challenge_token` missing, expired, or wrong purpose |
| `401` | `{ "error": "Passkey verification failed" }` | WebAuthn verification error |
| `404` | `{ "error": "Passkey not found" }` | `id` doesn't match any stored credential |

**JS example:**

```js
const res = await fetch('/api/v1/auth/passkeys/authenticate', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    challenge_token,
    ...serializeAssertion(assertion),
  }),
})
const { jwt, user } = await res.json()
// Store jwt and user, redirect to app
```

---

## Passkey Management

These endpoints let signed-in users see and remove their registered passkeys.

### `GET /api/v1/auth/passkeys`

Requires Bearer JWT. Returns the user's passkeys in registration order.

**Response — 200 OK:**

```json
[
  {
    "id": 1,
    "nickname": "Face ID",
    "created_at": "2026-05-29T10:00:00.000Z"
  },
  {
    "id": 2,
    "nickname": null,
    "created_at": "2026-05-30T08:30:00.000Z"
  }
]
```

`nickname` is `null` if the user didn't provide one during registration.

---

### `DELETE /api/v1/auth/passkeys/:id`

Requires Bearer JWT. Removes the passkey with the given `id`. Users can only delete their own passkeys.

**Response — 204 No Content** on success.

**Errors:**

| Status | Body | When |
|--------|------|------|
| `404` | `{ "error": "Passkey not found" }` | `id` doesn't exist or belongs to another user |

**JS example:**

```js
await fetch(`/api/v1/auth/passkeys/${passkeyId}`, {
  method: 'DELETE',
  headers: { 'Authorization': `Bearer ${jwt}` },
})
```

---

## Notes

- **`challenge_token` TTL is 5 minutes.** If the user takes longer than 5 minutes between the options and verify steps, the token expires and the FE must restart the flow.
- **Sign count** is updated after every successful authentication. The BE automatically rejects replayed assertions.
- **Rate limiting** — `POST /api/v1/auth/passkeys/authenticate` and `POST /api/v1/auth/passkeys/authenticate/options` are rate-limited to 5 requests/minute per IP.
- **Language** — pass `"language": "ro-RO"` in the request body to receive Romanian error messages.
