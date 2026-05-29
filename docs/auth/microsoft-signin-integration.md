# Microsoft Sign-In — FE Integration Guide

## Endpoint

```
POST /api/v1/auth/microsoft
Content-Type: application/json
```

## Flow

1. FE initiates Microsoft sign-in via MSAL and receives an `id_token`
2. FE sends that token to this endpoint
3. BE validates the token locally using Microsoft's public keys and returns a JWT + user object
4. FE stores the JWT and user exactly as it does for Google sign-in

**Personal accounts only** — this endpoint is configured for Outlook.com, Hotmail.com, and Live.com accounts (`consumers` tenant). Work/school accounts (Azure AD) are not supported.

## Request

```json
{
  "id_token": "<microsoft_id_token>"
}
```

| Field | Type | Required |
|-------|------|----------|
| `id_token` | string | Yes — the `idToken` from MSAL |

### Getting the id_token (Web — MSAL.js)

Install `@azure/msal-browser`:

```bash
npm install @azure/msal-browser
```

Configure and sign in:

```js
import { PublicClientApplication } from '@azure/msal-browser'

const msalInstance = new PublicClientApplication({
  auth: {
    clientId: '<YOUR_MICROSOFT_CLIENT_ID>',
    authority: 'https://login.microsoftonline.com/consumers',
    redirectUri: window.location.origin,
  },
})

await msalInstance.initialize()

const result = await msalInstance.loginPopup({
  scopes: ['openid', 'profile', 'email'],
})

const idToken = result.idToken
// POST to /api/v1/auth/microsoft with { id_token: idToken }
```

### Getting the id_token (React Native — MSAL React Native)

Install `react-native-msal`:

```bash
npm install react-native-msal
```

```js
import PublicClientApplication from 'react-native-msal'

const pca = new PublicClientApplication({
  auth: {
    clientId: '<YOUR_MICROSOFT_CLIENT_ID>',
    authority: 'https://login.microsoftonline.com/consumers',
  },
})

await pca.init()

const result = await pca.acquireToken({
  scopes: ['openid', 'profile', 'email'],
})

const idToken = result.idToken
// POST to /api/v1/auth/microsoft with { id_token: idToken }
```

### Getting the id_token (iOS — MSAL Swift)

```swift
import MSAL

let authority = try MSALAuthority(
    url: URL(string: "https://login.microsoftonline.com/consumers")!
)
let config = MSALPublicClientApplicationConfig(
    clientId: "<YOUR_MICROSOFT_CLIENT_ID>",
    redirectUri: nil,
    authority: authority
)
let application = try MSALPublicClientApplication(configuration: config)

let parameters = MSALInteractiveTokenParameters(
    scopes: ["openid", "profile", "email"],
    webviewParameters: MSALWebviewParameters(authPresentationViewController: viewController)
)

application.acquireToken(with: parameters) { result, error in
    guard let result = result, error == nil else { return }
    let idToken = result.idToken
    // POST to /api/v1/auth/microsoft with { id_token: idToken }
}
```

### Getting the id_token (Android — MSAL Android)

```kotlin
val authority = "https://login.microsoftonline.com/consumers"
val config = PublicClientApplicationConfiguration.Builder(applicationContext)
    .clientId("<YOUR_MICROSOFT_CLIENT_ID>")
    .authority(authority)
    .build()

val pca = PublicClientApplication.create(config)

val parameters = AcquireTokenParameters.Builder()
    .startAuthorizationFromActivity(activity)
    .withScopes(listOf("openid", "profile", "email"))
    .withCallback(object : AuthenticationCallback {
        override fun onSuccess(result: IAuthenticationResult) {
            val idToken = result.account.idToken
            // POST to /api/v1/auth/microsoft with { id_token: idToken }
        }
        override fun onError(exception: MsalException) { /* handle */ }
        override fun onCancel() { /* handle */ }
    })
    .build()

pca.acquireToken(parameters)
```

## Response — 200 OK

Same shape as Google sign-in, Facebook sign-in, and email/password sign-in.

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
    "language": null,
    "can_change_email": false
  }
}
```

### Fields to note

| Field | Notes |
|-------|-------|
| `email` | Always present — personal Microsoft accounts are required to have an email |
| `avatar_url` | Always `null` — Microsoft id_tokens do not include a photo URL |
| `can_change_email` | Always `false` for Microsoft-only accounts — hide the email field on the profile edit screen |
| `language` | `null` at first sign-in — set via `PATCH /api/v1/auth/me` |

## Error Responses

| Status | Body | When |
|--------|------|------|
| `422` | `{ "error": "id_token is required" }` | `id_token` param is missing or blank |
| `401` | `{ "error": "Invalid Microsoft token" }` | Token is expired, invalid, wrong audience, or from a work/school account |

Both error strings are localised — pass `language` in the request body to receive Romanian errors.

## Language param

To receive errors in Romanian:

```json
{
  "id_token": "<token>",
  "language": "ro-RO"
}
```

## Notes

- The JWT format and expiry (30 days) are identical to all other sign-in methods — no changes needed to token storage or refresh logic.
- `useAuthLocale` / `navigateWithLocale` work the same way — `user.language` is set via the profile update endpoint after first sign-in.
- If a Microsoft user already has an account via email/password or another provider (matching email), the Microsoft identity is linked to that account automatically — no duplicate accounts.
- `can_change_email` is always `false` for Microsoft-only accounts. If the user later adds an email/password identity, it becomes `true`.
- Work/school accounts (e.g., `@company.com` Azure AD users) will receive a 401 — they are not supported by this endpoint.
