# Facebook Sign-In Implementation Design

**Goal:** Add `POST /api/v1/auth/facebook` endpoint that accepts a Facebook `accessToken` from any platform (web, iOS, Android) and returns a JWT + user object, mirroring the existing Google sign-in flow.

**Architecture:** New `FacebookAuthService` validates the token via two Facebook Graph API calls, then `FacebooksController` finds or creates the user using the same pattern as `GooglesController`. No new gems — token validation is HTTP calls, not crypto.

**Tech Stack:** Rails 8.1, Net::HTTP (stdlib), Facebook Graph API v20, existing `UserIdentity` / `User` models.

---

## Endpoint

```
POST /api/v1/auth/facebook
Content-Type: application/json

{ "access_token": "<facebook_access_token>" }
```

Response (200):
```json
{
  "jwt": "<jwt>",
  "user": {
    "id": 1,
    "first_name": "Ion",
    "last_name": "Popescu",
    "email": "ion@example.com",
    "avatar_url": "https://...",
    "phone_number": null,
    "church_name": null,
    "city": null,
    "language": null,
    "can_change_email": false
  }
}
```

`email` may be `null` for users who signed up on Facebook with a phone number or declined to share it. `can_change_email` is always `false` for Facebook-only accounts (no `email` identity).

---

## FacebookAuthService

**File:** `app/services/facebook_auth_service.rb`

Two sequential Graph API calls:

### Step 1 — Validate token ownership
```
GET https://graph.facebook.com/debug_token
  ?input_token={access_token}
  &access_token={app_id}|{app_secret}
```
Response must have `data.is_valid: true` and `data.app_id` matching our configured app ID. Any failure raises `FacebookAuthService::InvalidTokenError`.

### Step 2 — Fetch user data
```
GET https://graph.facebook.com/me
  ?fields=id,email,first_name,last_name,picture.type(large)
  &access_token={access_token}
```
Returns:
```ruby
{
  uid:        payload['id'],           # Facebook user ID (string)
  email:      payload['email'],        # may be nil
  first_name: payload['first_name'].to_s,
  last_name:  payload['last_name'].to_s,
  avatar_url: payload.dig('picture', 'data', 'url')
}
```

Any non-2xx HTTP response raises `InvalidTokenError`.

**Credentials** (Rails encrypted credentials, top-level under `auth:`):
```yaml
auth:
  facebook_app_id: "..."
  facebook_app_secret: "..."
```

---

## FacebooksController

**File:** `app/controllers/api/v1/auth/facebooks_controller.rb`

Mirrors `GooglesController` exactly:

- Validates `access_token` param is present (422 if blank)
- Calls `FacebookAuthService.call(params[:access_token])`
- Calls `find_or_create_user(facebook_data)`
- Handles `FacebookAuthService::InvalidTokenError` → 401
- Handles `ActiveRecord::RecordNotUnique` race condition (concurrent sign-ins)
- Returns `{ jwt:, user: user_json }` on success

`find_or_create_user` logic:
1. Look up `UserIdentity` by `provider: 'facebook', uid: facebook_data[:uid]` → return existing user
2. If not found, look up `User` by email (only when email is non-nil) → link new Facebook identity, update avatar_url, backfill attendees
3. If not found, create new `User` + `UserIdentity` + backfill attendees
4. New users created via Facebook may have `email: nil`

---

## User Model Change

**File:** `app/models/user.rb`

Relax email validations to allow nil (for Facebook users with no email):

```ruby
# Before
validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

# After
validates :email, uniqueness: { allow_nil: true }, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
```

`normalizes :email` already handles nil safely (Rails 7.1+ `apply_to_nil` defaults to false).

Email presence for email/password registration is enforced at the controller level in `RegistrationsController`, so nothing regresses.

---

## Routes

```ruby
namespace :auth do
  resource :facebook, only: :create   # POST /api/v1/auth/facebook
  resource :google,   only: :create
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
    invalid_facebook_token: "Invalid Facebook token"
    access_token_required: "access_token is required"
```

`ro.yml`:
```yaml
auth:
  errors:
    invalid_facebook_token: "Token Facebook invalid"
    access_token_required: "access_token este necesar"
```

---

## Error Responses

| Scenario | Status | Body |
|----------|--------|------|
| Missing `access_token` param | 422 | `{ "error": "access_token is required" }` |
| Invalid / expired token | 401 | `{ "error": "Invalid Facebook token" }` |
| Token from wrong app | 401 | `{ "error": "Invalid Facebook token" }` |

---

## Testing

**File:** `spec/requests/api/v1/auth/facebook_spec.rb`

WebMock stubs both Graph API endpoints. Covers:

- New user created on first sign-in
- Existing `UserIdentity` → returns same user (idempotent)
- Existing `User` by email → links Facebook identity, updates avatar_url
- Attendee backfill on new user
- Attendee backfill on email-matched existing user
- Facebook user with `nil` email → creates user successfully
- Missing `access_token` param → 422
- Invalid token (`is_valid: false` from debug_token) → 401
- Non-2xx from Graph API → 401
- Returns correct JWT decoding to user_id
- `can_change_email` is `false` for Facebook-only account
