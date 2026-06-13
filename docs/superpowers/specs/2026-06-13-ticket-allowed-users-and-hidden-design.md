# Ticket Allowed Users & Hidden Flag — Design

**Date:** 2026-06-13

## Overview

Two related features that add per-user access control to tickets:

1. **Hidden tickets** — a `hidden` boolean that suppresses a ticket from the public event endpoint entirely, except for admin-role users.
2. **Per-user allowlist on `for_leaders` tickets** — a M2M relationship between tickets and users. When the list is non-empty, only those specific users can book the ticket. When empty, any non-attendee role can book (existing `for_leaders` behaviour). The serializer emits an `allowed` boolean only for `for_leaders` tickets so the frontend can gate price display and basket access.

## Data Model

### `hidden` column on `tickets`

```sql
ALTER TABLE tickets ADD COLUMN hidden boolean NOT NULL DEFAULT false;
```

Registered in `directus_fields` the same way `for_leaders` was (migration inserts the field metadata row).

### `tickets_allowed_users` junction table

| Column      | Type    | Notes                          |
|-------------|---------|--------------------------------|
| `id`        | bigint  | PK                             |
| `ticket_id` | bigint  | FK → tickets, not null         |
| `user_id`   | bigint  | FK → users, not null           |

Unique index on `[ticket_id, user_id]`.

Rails models:
- `TicketAllowedUser` — `belongs_to :ticket`, `belongs_to :user`
- `Ticket` — `has_many :ticket_allowed_users`, `has_many :allowed_users, through: :ticket_allowed_users, source: :user`

Directus: registered as a M2M junction so the admin gets a user-picker on the ticket edit form. Users are pulled from the `users` collection (the app's user table, not `directus_users`).

## Optional Auth on the Event Endpoint

The event endpoint (`GET /api/v1/:languages_code/event/:slug`) is public. To support per-user personalisation without requiring a token, a new `try_authenticate_user` method is added to `Authenticatable`:

```ruby
def try_authenticate_user
  token = request.headers['Authorization']&.split&.last
  return if token.blank?
  user_id = JwtService.decode(token)
  @current_user = User.active.find_by(id: user_id)
rescue JWT::DecodeError
  nil
end
```

`EventController#show` calls this before rendering. `current_user` (which may be `nil`) is passed into the serializer params. Eager-load updated to include `ticket_allowed_users`.

## Ticket Filtering — Hidden

In `EventSerializer`, the `tickets` attribute filters out hidden tickets before passing to `TicketSerializer`:

```ruby
visible = object.tickets.reject do |t|
  t.hidden && params[:current_user]&.role != 'admin'
end
```

Hidden tickets are invisible to unauthenticated users and all non-admin roles.

## Serializer — `allowed` Field

`TicketSerializer` gains an `allowed` attribute emitted only for `for_leaders` tickets:

| Condition                                      | `allowed` value |
|------------------------------------------------|-----------------|
| `for_leaders: false`                           | field omitted   |
| Not logged in                                  | `false`         |
| Logged in, no allowed_users on this ticket     | `true`          |
| Logged in, allowed_users present, user in list | `true`          |
| Logged in, allowed_users present, not in list  | `false`         |

`ticket_allowed_users` is already eager-loaded so no extra queries per ticket.

## Orders Controller — Updated Guard

The existing `for_leaders` guard in `OrdersController` is extended to also enforce the allowed_users list when non-empty:

```ruby
if ticket.for_leaders
  unless %w[leader admin volunteer].include?(@current_user&.role)
    render json: { error: t('orders.errors.leader_ticket_required') }, status: :forbidden
    break
  end

  if ticket.ticket_allowed_users.any? &&
     ticket.ticket_allowed_users.none? { |tau| tau.user_id == @current_user.id }
    render json: { error: t('orders.errors.not_allowed_for_ticket') }, status: :forbidden
    break
  end
end
```

A new I18n key `orders.errors.not_allowed_for_ticket` is added.

`ticket_allowed_users` is added to the orders controller eager-load as well.

## Files Touched

| File | Change |
|------|--------|
| `db/migrate/…_add_hidden_to_tickets.rb` | Add `hidden` column + Directus field metadata |
| `db/migrate/…_create_tickets_allowed_users.rb` | Junction table + Directus M2M registration |
| `app/models/ticket_allowed_user.rb` | New model |
| `app/models/ticket.rb` | Add `has_many :ticket_allowed_users` / `:allowed_users` |
| `app/controllers/concerns/authenticatable.rb` | Add `try_authenticate_user` |
| `app/controllers/api/v1/event_controller.rb` | Call `try_authenticate_user`, pass user to serializer, expand includes |
| `app/serializers/event_serializer.rb` | Filter hidden tickets, pass `current_user` to `TicketSerializer` |
| `app/serializers/ticket_serializer.rb` | Add `allowed` attribute |
| `app/controllers/api/v1/orders_controller.rb` | Extend `for_leaders` guard, expand includes |
| `config/locales/en.yml` (+ other locales) | Add `not_allowed_for_ticket` error key |

## `hidden` and the Orders Layer

`hidden` is a display-only filter — it is not enforced at the orders controller level. If an admin creates a hidden ticket and an attendee somehow obtains its ID or name, the backend will not block the order on the basis of `hidden` alone. The `for_leaders` + `allowed_users` guards remain the booking security gates. This is intentional: hidden tickets are primarily a Directus authoring convenience (draft/internal tickets not yet ready to show), not a hard access restriction.

## Out of Scope

- The `allowed` field is not exposed on scan, booking, or any other endpoint — only the public event detail endpoint.
- No change to the `for_leaders` visibility logic in the frontend (it already uses the `for_leaders` field; `allowed` is additive).
- No admin UI beyond what Directus provides via the M2M picker.
