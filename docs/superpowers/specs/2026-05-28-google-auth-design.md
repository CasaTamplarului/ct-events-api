# Google Sign-In Authentication Design

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Google Sign-In to the Rails API, issuing stateless JWTs, with a multi-provider identity model that supports future addition of Apple, Facebook, Microsoft, and email/password sign-in.

**Architecture:** The FE (web and mobile) handles the Google OAuth flow client-side and sends a Google ID token to the API. The API verifies the token with Google, finds or creates the user, and returns a signed JWT. All subsequent authenticated requests carry the JWT in the `Authorization: Bearer` header.

**Tech Stack:** Rails 8.1 API, PostgreSQL 17, `google-id-token` gem (ID token verification), `jwt` gem (JWT encode/decode), `bcrypt` (existing, for future email/password).

---

## Data Model

### `users` table changes
- Make `password_digest` **nullable** — OAuth users don't have one; email/password users will.
- Add `avatar_url` string (nullable) — populated from the OAuth provider's profile picture.

### New `user_identities` table
| Column | Type | Notes |
|---|---|---|
| `id` | bigint PK | |
| `user_id` | bigint FK → users | NOT NULL, cascade delete |
| `provider` | string | `"google"`, `"apple"`, `"facebook"`, `"microsoft"`, `"email"` |
| `uid` | string | Provider's unique user ID (Google's `sub` claim, etc.) |
| `created_at` | datetime | |
| `updated_at` | datetime | |

Unique index on `[provider, uid]`.

### Sign-in look-up logic
1. Find `UserIdentity` by `provider="google"` + `uid=<Google sub>` → return JWT for that user.
2. Not found → find `User` by email → if found, create a new `UserIdentity` linking the existing user to Google, return JWT. (This handles users who previously booked as a guest with the same email.)
3. Neither found → create `User` + `UserIdentity`, then backfill `user_id` on all `Attendee` records whose `email_address` matches, return JWT.

---

## API Endpoints

All under `/api/v1/` — no language code prefix (auth is language-agnostic).

### `POST /api/v1/auth/google`
Exchange a Google ID token for an API JWT.

**Request body:**
```json
{ "id_token": "<Google ID token from client-side Google Sign-In>" }
```

**Response (200):**
```json
{
  "jwt": "<signed JWT, 30-day expiry>",
  "user": {
    "id": 1,
    "first_name": "Ion",
    "last_name": "Popescu",
    "email": "ion@example.com",
    "avatar_url": "https://lh3.googleusercontent.com/..."
  }
}
```

**Error responses:**
- `401 { "error": "Invalid Google token" }` — token failed verification or is expired
- `422 { "error": "id_token is required" }` — missing param

### `GET /api/v1/auth/me`
Return the current user's profile. Requires `Authorization: Bearer <jwt>` header.

**Response (200):** Same `user` shape as above.

**Error responses:**
- `401 { "error": "Unauthorized" }` — missing, invalid, or expired JWT

---

## JWT Structure

Payload: `{ user_id: <integer>, exp: <Unix timestamp 30 days from now> }`

Signed with HS256 using a secret stored in Rails encrypted credentials under `auth.jwt_secret`.

---

## Code Structure

### New files
| File | Responsibility |
|---|---|
| `app/models/user_identity.rb` | `belongs_to :user`; validates presence of `provider`, `uid` |
| `app/services/google_auth_service.rb` | Verifies Google ID token using `google-id-token` gem; returns `{ uid, email, first_name, last_name, avatar_url }` or raises on invalid token |
| `app/services/jwt_service.rb` | `encode(user_id)` → signed JWT string; `decode(token)` → `user_id` or raises `JWT::DecodeError` |
| `app/controllers/api/v1/auth/google_controller.rb` | `POST /auth/google` — calls `GoogleAuthService`, runs find-or-create logic, returns JWT + user |
| `app/controllers/api/v1/auth/me_controller.rb` | `GET /auth/me` — calls `authenticate_user!`, renders current user |
| `app/controllers/concerns/authenticatable.rb` | `authenticate_user!` method: reads `Authorization` header, decodes JWT, sets `@current_user`; renders 401 on failure |

### Modified files
| File | Change |
|---|---|
| `app/models/user.rb` | Add `has_many :user_identities, dependent: :destroy`; change `has_secure_password` to `has_secure_password(validations: false)` — the default adds `validates :password, presence: true, on: :create` which blocks OAuth user creation. With `validations: false`, the existing `validates :password, length: { minimum: 8 }, allow_nil: true` handles password length for email/password users. |
| `config/routes.rb` | Add `namespace :auth` block inside `api/v1` with `google` and `me` resources |
| `Gemfile` | Add `gem 'google-id-token'` and `gem 'jwt'` |
| `config/credentials.yml.enc` | Add `auth.jwt_secret` (a random 64-char hex string) |

### ApplicationController
`authenticate_user!` is defined in `Authenticatable` and included in `ApplicationController`. It is **not** called as a global `before_action` — each controller opts in explicitly.

---

## Google Client ID
The Google OAuth client ID (needed to verify ID tokens) is stored in Rails encrypted credentials under `auth.google_client_id`. The `GoogleAuthService` reads it from there.

---

## Future Providers
Adding Apple/Facebook/Microsoft/email-password:
- Each gets its own controller (`auth/apple_controller.rb`, etc.) and service (`apple_auth_service.rb`, etc.)
- All share the same `UserIdentity` model (`provider` column distinguishes them)
- All share `JwtService` and `Authenticatable`
- No schema changes required — just new `provider` values in `user_identities`

Email/password sign-in will use the existing `has_secure_password` on `User` and create a `UserIdentity` with `provider="email"`, `uid=<email>`.

---

## Testing
- `GoogleAuthService` is tested with a stubbed `google-id-token` verifier (WebMock or stub the gem)
- `JwtService` is unit-tested: encode → decode round-trip, expired token raises error
- `POST /api/v1/auth/google` request spec: valid token creates user + identity + returns JWT; invalid token returns 401; existing user by google_uid returns same user; existing user by email gets identity attached
- `GET /api/v1/auth/me` request spec: valid JWT returns user; missing/invalid JWT returns 401
- Attendee backfill: request spec verifies that creating a user via Google links existing attendees with matching email
