# Facebook Sign-In — FE Integration Guide

## Endpoint

```
POST /api/v1/auth/facebook
Content-Type: application/json
```

## Flow

1. FE initiates Facebook Login via the Facebook SDK and receives an `accessToken`
2. FE sends that token to this endpoint
3. BE validates it against Facebook's Graph API and returns a JWT + user object
4. FE stores the JWT and user exactly as it does for Google sign-in

## Request

```json
{
  "access_token": "<facebook_access_token>"
}
```

| Field | Type | Required |
|-------|------|----------|
| `access_token` | string | Yes — the `accessToken` from Facebook SDK |

### Getting the access token (Web)

```js
FB.login((response) => {
  if (response.authResponse) {
    const accessToken = response.authResponse.accessToken
    // POST to /api/v1/auth/facebook with { access_token: accessToken }
  }
}, { scope: 'email,public_profile' })
```

### Getting the access token (React Native / Mobile)

Use the [Facebook SDK for iOS](https://developers.facebook.com/docs/ios) or [Android](https://developers.facebook.com/docs/android). After a successful login, pass `AccessToken.getCurrentAccessToken().tokenString` as `access_token`.

## Response — 200 OK

Same shape as Google sign-in and email/password sign-in.

```json
{
  "jwt": "eyJhbGciOiJIUzI1NiJ9...",
  "user": {
    "id": 42,
    "first_name": "Ion",
    "last_name": "Popescu",
    "email": "ion@example.com",
    "avatar_url": "https://platform-lookaside.fbsbx.com/...",
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
| `email` | May be `null` — Facebook users who signed up with a phone number or declined to share their email will have no email |
| `can_change_email` | Always `false` for Facebook-only accounts — hide the email field on the profile edit screen |
| `avatar_url` | Pulled from Facebook profile picture; may be `null` if no picture set |
| `language` | `null` at first sign-in — set via `PATCH /api/v1/auth/me` |

## Error Responses

| Status | Body | When |
|--------|------|------|
| `422` | `{ "error": "access_token is required" }` | `access_token` param is missing or blank |
| `401` | `{ "error": "Invalid Facebook token" }` | Token is expired, invalid, or from a different Facebook app |

Both error strings are localised — pass `?language=ro-RO` in the query string (or include it in the body) if you want Romanian errors.

## Language param

To receive errors in Romanian:

```json
{
  "access_token": "<token>",
  "language": "ro-RO"
}
```

## Notes

- The JWT format and expiry (30 days) are identical to Google sign-in and email/password sign-in — no changes needed to token storage or refresh logic.
- `useAuthLocale` / `navigateWithLocale` work the same way — `user.language` is set via the profile update endpoint after first sign-in.
- If a Facebook user already has an account via email/password (matching email), the Facebook identity is linked to that account automatically — no duplicate accounts.
- Facebook users with `email: null` will have `can_change_email: false` permanently and cannot set an email via the profile page. This is a known limitation with no current workaround on the BE side.
