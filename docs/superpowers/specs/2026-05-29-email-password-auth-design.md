# Email/Password Authentication Design

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add email/password registration and login to the Rails API, reusing the existing JWT and multi-provider identity infrastructure built for Google Sign-In.

**Architecture:** Two new endpoints — registration and session — both returning a signed JWT on success. Email users get a `UserIdentity` record with `provider: "email"` and `uid: <email>`, mirroring the Google flow. Rate limiting via `rack-attack` protects both endpoints.

**Tech Stack:** Rails 8.1 API, PostgreSQL 17, `has_secure_password` (existing, on `User`), `jwt` gem (existing), `rack-attack` gem (new).

---

## Data Model

### `users` table changes
- Add `phone_number` string (nullable) — optional profile field
- Add `church_name` string (nullable) — optional profile field
- Add `city` string (nullable) — optional profile field

These mirror the fields already on `attendees` and complete the user profile for registered accounts.

### Sign-in identity
Email/password users get a `UserIdentity` row: `provider: "email"`, `uid: <email address>`. This keeps them consistent with OAuth users and allows a future transition to email+OAuth linking.

---

## API Endpoints

All under `/api/v1/auth/` — no language code prefix.

### `POST /api/v1/auth/registration`
Create a new account and return a JWT.

**Request body:**
```json
{
  "first_name": "Ion",
  "email": "ion@example.com",
  "password": "MyPassword1!",
  "last_name": "Popescu",
  "phone_number": "+40700000000",
  "church_name": "Biserica Betel",
  "city": "Cluj-Napoca"
}
```
Required: `first_name`, `email`, `password`. All others optional.

**Response (201):**
```json
{
  "jwt": "<signed JWT, 30-day expiry>",
  "user": {
    "id": 1,
    "first_name": "Ion",
    "last_name": "Popescu",
    "email": "ion@example.com",
    "avatar_url": null,
    "phone_number": "+40700000000",
    "church_name": "Biserica Betel",
    "city": "Cluj-Napoca"
  }
}
```

**Error responses:**
- `422 { "error": "..." }` — missing required fields, password too short (< 8 chars), invalid email format
- `409 { "error": "Email is already registered" }` — email already in use

### `POST /api/v1/auth/session`
Authenticate and return a JWT.

**Request body:**
```json
{ "email": "ion@example.com", "password": "MyPassword1!" }
```

**Response (200):** Same `jwt` + `user` shape as registration.

**Error responses:**
- `401 { "error": "Invalid email or password" }` — email not found or wrong password (intentionally vague)
- `422 { "error": "email and password are required" }` — missing params

---

## Rate Limiting

`rack-attack` throttle: **5 requests per IP per minute** on:
- `POST /api/v1/auth/registration`
- `POST /api/v1/auth/session`

Blocked requests receive: `429 { "error": "Too many requests. Please try again later." }`

---

## Registration Logic

1. Validate required params and format → 422 on failure
2. Check `User.exists?(email: email)` → 409 if taken
3. In a transaction:
   - Create `User` (with `password_digest` from `has_secure_password`)
   - Create `UserIdentity` (`provider: "email"`, `uid: email`)
   - Backfill: `Attendee.where(email_address: email).update_all(user_id: user.id)`
4. Return 201 + JWT + user

---

## Session Logic

1. Validate params present → 422 if missing
2. `user = User.find_by(email: email)`
3. `user&.authenticate(password)` — returns the user on success, `false` on wrong password
4. Return 401 with generic message if either step fails (do not reveal whether the email exists)
5. Return 200 + JWT + user

---

## Code Structure

### New files
| File | Responsibility |
|---|---|
| `app/controllers/api/v1/auth/registrations_controller.rb` | `POST /auth/registration` — validate, create user + identity, backfill, return JWT |
| `app/controllers/api/v1/auth/sessions_controller.rb` | `POST /auth/session` — find user, authenticate, return JWT |
| `config/initializers/rack_attack.rb` | Throttle rules for auth endpoints; JSON 429 response |

### Modified files
| File | Change |
|---|---|
| `app/models/user.rb` | `church_name` and `city` are now valid columns; no new validations needed (both optional) |
| `config/routes.rb` | Add `resource :registration, only: :create` and `resource :session, only: :create` inside `namespace :auth` |
| `Gemfile` | Add `gem 'rack-attack'` |
| Migration | Add `phone_number string`, `church_name string`, and `city string` (all nullable) to `users` |

### Shared infrastructure (unchanged)
- `JwtService` — already handles encode/decode
- `Authenticatable` concern — already handles `authenticate_user!`
- `UserIdentity` model — already supports `provider: "email"`
- `has_secure_password(validations: false)` on `User` — already set up

---

## User JSON Shape

Both endpoints return the same user object (extended from the Google auth shape to include the new fields):

```json
{
  "id": 1,
  "first_name": "Ion",
  "last_name": "Popescu",
  "email": "ion@example.com",
  "avatar_url": null,
  "phone_number": "+40700000000",
  "church_name": "Biserica Betel",
  "city": "Cluj-Napoca"
}
```

`GET /api/v1/auth/me` should also be updated to return the new fields.

---

## Testing

- **Migration spec:** `church_name` and `city` columns exist and are nullable
- **RegistrationsController request spec:**
  - Valid params → 201, JWT returned, user created, identity created
  - Missing required field → 422
  - Password < 8 chars → 422
  - Duplicate email → 409
  - Existing attendees with same email are backfilled with `user_id`
- **SessionsController request spec:**
  - Valid credentials → 200, JWT returned
  - Wrong password → 401
  - Unknown email → 401
  - Missing params → 422
- **Rack-attack spec:** 6th request from same IP within 1 minute → 429
- **`GET /api/v1/auth/me`:** Returns `church_name` and `city` in response

---

## Out of Scope

- Password reset (deferred — requires email/SendGrid integration)
- Email verification
- CAPTCHA
- Account deletion
