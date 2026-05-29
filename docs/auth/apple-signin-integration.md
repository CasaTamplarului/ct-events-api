# Apple Sign-In — FE Integration Guide

## Endpoint

```
POST /api/v1/auth/apple
Content-Type: application/json
```

## Flow

1. FE initiates Apple Sign-In and receives an `identityToken` / `id_token`
2. FE sends that token to this endpoint
3. BE validates the token locally using Apple's public keys and returns a JWT + user object
4. FE stores the JWT and user exactly as it does for Google and Microsoft sign-in

**iOS native and web are both supported** — both platforms produce an identity token that this endpoint accepts.

## Request

```json
{
  "id_token": "<apple_identity_token>"
}
```

| Field | Type | Required |
|-------|------|----------|
| `id_token` | string | Yes — the identity token from Apple |

### Getting the id_token (iOS — Swift)

```swift
import AuthenticationServices

class SignInCoordinator: NSObject, ASAuthorizationControllerDelegate {
    func startSignIn() {
        let provider = ASAuthorizationAppleIDProvider()
        let request  = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData   = credential.identityToken,
            let idToken     = String(data: tokenData, encoding: .utf8)
        else { return }

        // POST to /api/v1/auth/apple with { id_token: idToken }
    }
}
```

**Note:** Apple only provides `fullName` on the first sign-in. The backend derives a display name from the email address — no need to send the name separately.

### Getting the id_token (Web — Apple JS SDK)

Include Apple's JS SDK in your HTML:

```html
<script src="https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js"></script>
```

Configure and sign in:

```js
AppleID.auth.init({
  clientId: '<YOUR_SERVICE_ID>',      // Web Service ID from Apple Developer Console
  scope: 'name email',
  redirectURI: window.location.origin, // must match what's registered in Apple Console
  usePopup: true,
})

const response = await AppleID.auth.signIn()
const idToken  = response.authorization.id_token
// POST to /api/v1/auth/apple with { id_token: idToken }
```

### Getting the id_token (React Native — react-native-apple-authentication)

```bash
npm install @invertase/react-native-apple-authentication
```

```js
import appleAuth from '@invertase/react-native-apple-authentication'

const appleAuthRequestResponse = await appleAuth.performRequest({
  requestedOperation: appleAuth.Operation.LOGIN,
  requestedScopes: [appleAuth.Scope.EMAIL, appleAuth.Scope.FULL_NAME],
})

const { identityToken } = appleAuthRequestResponse
// POST to /api/v1/auth/apple with { id_token: identityToken }
```

This library handles both iOS (native) and Android (web fallback) automatically.

## Response — 200 OK

Same shape as Google, Microsoft, Facebook, and email/password sign-in.

```json
{
  "jwt": "eyJhbGciOiJIUzI1NiJ9...",
  "user": {
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
}
```

### Fields to note

| Field | Notes |
|-------|-------|
| `first_name` | Derived from the email prefix (e.g. `ion` from `ion@icloud.com`); `"Apple"` for Hide My Email relay addresses |
| `last_name` | Always `null` at account creation — set via `PATCH /api/v1/auth/me` |
| `avatar_url` | Always `null` — Apple does not provide a profile photo |
| `can_change_email` | Always `false` for Apple-only accounts — hide the email field on the profile edit screen |
| `language` | `null` at first sign-in — set via `PATCH /api/v1/auth/me` |

## Error Responses

| Status | Body | When |
|--------|------|------|
| `422` | `{ "error": "id_token is required" }` | `id_token` param is missing or blank |
| `401` | `{ "error": "Invalid Apple token" }` | Token is expired, invalid signature, wrong audience, or email not verified |

Both error strings are localised — pass `language` in the request body to receive Romanian errors.

## Language param

```json
{
  "id_token": "<token>",
  "language": "ro-RO"
}
```

## Notes

- The JWT format and expiry (30 days) are identical to all other sign-in methods.
- If an Apple user has a Hide My Email relay address (`@privaterelay.appleid.com`), that relay address is stored as their email. It will not be automatically linked to an existing account created with the real email.
- If a user signs in with Apple after previously registering with email/password using the same email, the Apple identity is linked automatically — no duplicate account.
- `can_change_email` is always `false` for Apple-only accounts. If the user later adds an email/password identity, it becomes `true`.
- Apple Sign-In requires your app to be configured in Apple Developer Console with an App ID (iOS) and a Service ID (web). Update `auth.apple_bundle_ids` in Rails credentials with the real values once configured.
