# Role Permissions System — Design Spec

**Date:** 2026-05-30
**Status:** Approved

## Overview

Add a role-based permission system to the app's `users` table. Every user has one role (`admin`, `volunteer`, or `attendee`). New registrations default to `attendee`. Role assignment is done by staff via Directus. The permission matrix (which role can do what) is defined in Rails code and returned to clients on the `/me` endpoint.

## Permissions (initial set)

| Permission | admin | volunteer | attendee |
|---|---|---|---|
| `can_check_in_attendees` | true | true | false |
| `can_scan_food_stamp` | true | true | false |

New permissions are added by extending the `ROLE_PERMISSIONS` constant and running a deploy — no DB schema change needed for the matrix.

## Database

One migration: add `role` string column to `users`, not null, default `'attendee'`.

```sql
ALTER TABLE users ADD COLUMN role varchar NOT NULL DEFAULT 'attendee';
```

No new tables. The permission matrix lives in code.

## User model (`app/models/user.rb`)

```ruby
ROLES = %w[admin volunteer attendee].freeze

ROLE_PERMISSIONS = {
  "admin"     => { can_check_in_attendees: true,  can_scan_food_stamp: true  },
  "volunteer" => { can_check_in_attendees: true,  can_scan_food_stamp: true  },
  "attendee"  => { can_check_in_attendees: false, can_scan_food_stamp: false }
}.freeze

validates :role, inclusion: { in: ROLES }

def can?(permission)
  ROLE_PERMISSIONS.dig(role, permission) == true
end
```

Unknown permissions return `false` (safe default).

## Authenticatable concern (`app/controllers/concerns/authenticatable.rb`)

Add `require_permission!(permission)` helper:

```ruby
def require_permission!(permission)
  return if current_user&.can?(permission)
  render json: { error: I18n.t('auth.errors.forbidden') }, status: :forbidden
end
```

Controllers use it with `authenticate_user!` as a prior before_action — Rails halts the chain on 401 before permission is checked:

```ruby
before_action :authenticate_user!
before_action { require_permission!(:can_check_in_attendees) }
```

A new i18n key `auth.errors.forbidden` is needed in the locale files.

## Me endpoint response

`user_json` in `Api::V1::Auth::MeController` gains two new keys:

```json
{
  "role": "volunteer",
  "permissions": {
    "can_check_in_attendees": true,
    "can_scan_food_stamp": true
  }
}
```

`permissions` is derived from `User::ROLE_PERMISSIONS[user.role]` — no extra DB query.

## Directus

The `role` field will appear on the `users` collection automatically once the migration runs (Directus shares the same Postgres DB). To make it user-friendly, configure the field via the Directus API on `localhost:8091`:

- Collection: `users`
- Field: `role`
- Interface: `select-dropdown`
- Choices: `admin`, `volunteer`, `attendee`

This call will be applied to local Directus (`localhost:8091`) during implementation, and later replicated to production.

## Tests

- `User#can?`: every role × permission combination, plus unknown permission returns false
- `require_permission!`: returns 403 when user lacks permission, passes through when allowed
- `GET /api/v1/auth/me`: response includes `role` and `permissions` keys with correct values
