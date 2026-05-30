# User Soft-Delete (Account Deletion) Design

**Goal:** Let users delete their own account from the FE apps. Keep all rows in the database but anonymise the user's PII so the data is no longer attributable. Attendee records are preserved intact — including the `user_id` FK — so event attendance counts and history remain accurate.

**Architecture:** A single `DELETE /api/v1/auth/me` endpoint calls `UserDeletionService`, which stamps `deleted_at`, wipes all PII fields, and destroys OAuth identities and passkeys in one transaction. One line change to `Authenticatable` blocks deleted users from all protected endpoints. No new gems required.

**Tech Stack:** Rails 8.1, PostgreSQL.

---

## Endpoint

| Method | Path | Auth required | Purpose |
|--------|------|---------------|---------|
| `DELETE` | `/api/v1/auth/me` | Yes (JWT) | Anonymise the authenticated user's account |

Route: add `:destroy` to the existing `resource :me` in `namespace :auth`.

---

## Migration

Add a nullable `deleted_at` timestamp to `users`:

```ruby
add_column :users, :deleted_at, :datetime, default: nil
add_index  :users, :deleted_at
```

---

## UserDeletionService

**File:** `app/services/user_deletion_service.rb`

Single public method `.call(user)`. Wraps everything in one transaction.

### What it does

1. Updates the user row in one `update_columns` call (skips validations — `first_name` presence would block a nil write):
   - `deleted_at` → `Time.current`
   - `email` → `nil`
   - `first_name` → `"Deleted"`
   - `last_name` → `nil`
   - `avatar_url` → `nil`
   - `phone_number` → `nil`
   - `church_name` → `nil`
   - `city` → `nil`
   - `language` → `nil`
   - `password_digest` → `nil`
   - `password_reset_token` → `nil`
   - `password_reset_token_expires_at` → `nil`

2. Calls `user.user_identities.destroy_all` — removes all OAuth/email identities so the same credentials produce a fresh account on next sign-in.

3. Calls `user.passkeys.destroy_all` — removes all passkeys for the same reason.

### What it does NOT touch

- `Attendee` records — `user_id` FK stays intact, all fields unchanged. The user row still exists (anonymised), so the FK remains valid. Event attendance counts are unaffected.

---

## MeController

**File:** `app/controllers/api/v1/auth/me_controller.rb` (modify)

Add a `destroy` action:

```ruby
def destroy
  UserDeletionService.call(current_user)
  head :no_content
end
```

Update routes to include `:destroy`:

```ruby
resource :me, only: %i[show update destroy], controller: 'me' do
  patch :password, on: :member
end
```

---

## Auth Guard

**File:** `app/controllers/concerns/authenticatable.rb` (modify)

Change the user lookup from:

```ruby
@current_user = User.find_by(id: user_id)
```

to:

```ruby
@current_user = User.find_by(id: user_id, deleted_at: nil)
```

A deleted user presenting a still-valid JWT receives `401 Unauthorized` on every protected endpoint. No other changes needed — sign-in flows already miss deleted users naturally:
- Email/password: `email` is `nil`, so lookup finds nothing
- OAuth (Google, Microsoft, Apple, Facebook): `user_identities` destroyed, so lookup finds nothing → fresh account created on next sign-in
- Passkeys: destroyed

---

## Response

| Scenario | Status | Body |
|----------|--------|------|
| Valid JWT, deletion succeeds | 204 | (empty) |
| No JWT | 401 | `{ "error": "Unauthorized" }` |
| Deleted user's JWT reused | 401 | `{ "error": "Unauthorized" }` |

The FE should discard its stored JWT and navigate the user to the sign-in screen on receiving 204.

---

## i18n

No new i18n keys required — the 401 reuses the existing `auth.errors.unauthorized` key.

---

## Testing

### `spec/services/user_deletion_service_spec.rb`

- Stamps `deleted_at` with the current time
- Sets `first_name` to `"Deleted"`
- Clears `email`, `last_name`, `avatar_url`, `phone_number`, `church_name`, `city`, `language`, `password_digest`, `password_reset_token`, `password_reset_token_expires_at` to `nil`
- Destroys all `user_identities`
- Destroys all `passkeys`
- Leaves attendee `user_id` FK intact
- Leaves all other attendee fields unchanged

### `spec/requests/api/v1/auth/me_spec.rb` (additions)

- `DELETE /api/v1/auth/me` with valid JWT → 204
- `DELETE /api/v1/auth/me` with valid JWT → user has `deleted_at` set
- `GET /api/v1/auth/me` after deletion with same JWT → 401
- `DELETE /api/v1/auth/me` with no JWT → 401

---

## Notes

- `update_columns` is used deliberately to bypass the `first_name: presence: true` validation when setting it to `"Deleted"`. This is an intentional system operation, not user input.
- The `deleted_at` index makes it easy to query all deleted users or run a future hard-delete job if needed.
- If a deleted user signs in again (Google, Apple, etc.), a brand new `User` row is created — no link to the old anonymised row.
- The `Attendee` → `User` FK remains valid because the user row is never removed, only anonymised.
