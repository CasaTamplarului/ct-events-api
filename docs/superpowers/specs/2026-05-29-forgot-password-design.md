# Forgot Password Design

## Section 1: Data Model

Two new nullable columns on `users`:
- `password_reset_token string` — URL-safe base64(32) token, plain text
- `password_reset_token_expires_at datetime` — 1-hour expiry from generation time

One additional nullable column on `users` (stored at registration):
- `language string` — BCP-47 code sent by the client, e.g. `"ro-RO"`, `"en-US"`

Token lifecycle:
- Generated: `SecureRandom.urlsafe_base64(32)`
- Validated: record found where `password_reset_token = ?` AND `password_reset_token_expires_at > NOW()`
- Consumed: `password_reset_token` and `password_reset_token_expires_at` set to `nil` after successful reset

Reset URL: `"#{ENV['FRONTEND_URL']}/reset-password?token=#{token}"`

SendGrid template ID: `d-952a77f57d9f410597cfa1cf84260cef`
Template variables: `is_romanian` (bool), `first_name` (string), `reset_url` (string), `year` (string)

`is_romanian` = `user.language&.start_with?("ro")`

---

## Section 2: Endpoints

### `POST /api/v1/auth/password/forgot`

- Params: `{ email: "..." }`
- Always responds `200 { message: "If that email is registered, a reset link has been sent." }` — no user enumeration
- If user exists: generate token, set expiry (`1.hour.from_now`), save, send SendGrid email
- If user not found: silently do nothing, still return 200
- Rate-limited: 3 req/IP/min (tighter than login — email sending is expensive)

### `POST /api/v1/auth/password/reset`

- Params: `{ token: "...", password: "..." }`
- Finds user by `password_reset_token` where `password_reset_token_expires_at > now`
- If not found or expired → `422 { error: "Invalid or expired reset token" }`
- If found: update `password_digest`, clear both token columns, return `200 { jwt: "...", user: {...} }`
- Password still validated (minimum 8 chars from model)
- `user` shape: `{ id, first_name, last_name, email, avatar_url, phone_number, church_name, city }`

---

## Section 3: Code Structure

### New files

**`app/controllers/api/v1/auth/passwords_controller.rb`**
- `forgot` action: find user, generate token, call `SendgridService.send_password_reset`
- `reset` action: find user by valid token, update password, clear token, return JWT

**`app/services/sendgrid_service.rb`**
- Single class method: `SendgridService.send_password_reset(user:, reset_url:)`
- Uses `sendgrid-ruby` gem
- API key from `Rails.application.credentials.dig(:sendgrid, :api_key)`
- Builds dynamic template mail with `to`, `from`, `template_id`, `dynamic_template_data`
- `from` address from `Rails.application.credentials.dig(:sendgrid, :from_email)`

### Modified files

**`config/initializers/rack_attack.rb`**
- Add `/api/v1/auth/password/forgot` to a new throttle: 3 req/IP/min

**`config/routes.rb`**
- `namespace :password` with `resource :forgot, only: :create` and `resource :reset, only: :create`

**`Gemfile`**
- Add `sendgrid-ruby`

**`db/migrate/...`**
- Add `password_reset_token`, `password_reset_token_expires_at`, `language` to `users`

**`app/controllers/api/v1/auth/registrations_controller.rb`**
- Capture `params[:language]` at registration, store on user

---

## Testing Plan

### Model / service
- `SendgridService`: stub `SendGrid::API.new` with WebMock; verify correct template ID and dynamic data are sent
- Token expiry: set `password_reset_token_expires_at` to past, verify reset returns 422

### Request specs
- `POST /api/v1/auth/password/forgot`:
  - Existing user → 200, token saved, email sent (service stubbed)
  - Unknown user → 200, no email sent
  - Missing email param → 422
  - Rate limit: 4th request from same IP → 429
- `POST /api/v1/auth/password/reset`:
  - Valid token → 200, JWT, user JSON, token cleared
  - Invalid token → 422
  - Expired token → 422
  - Missing params → 422
- `POST /api/v1/auth/registration`:
  - With `language` param → user.language saved
