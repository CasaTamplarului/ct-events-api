# Scan: Self-Check-in Guard & Events List Design

**Date:** 2026-05-31  
**Status:** Approved

## Overview

Two small additions to the scan API:

1. **Self-check-in guard** — prevent a user from operating on an order they belong to (as an attendee)
2. **Events list** — endpoint for the scan FE to choose which event to search in

---

## Feature 1: Self-Check-in Guard

### Rule

A user making a `PATCH /api/v1/scan/orders/:order_reference` request must not have any attendee records in the order they are trying to operate on. If they do, the request is rejected with 403 regardless of which attendees they are trying to check in or whether they are changing payment status.

`GET /api/v1/scan/orders/:order_reference` is unaffected — read access is always allowed.

### Implementation

Add a `before_action :prevent_self_checkin!, only: :update` to `Api::V1::Scan::OrdersController`, positioned after `set_order` so `@order` is available:

```ruby
before_action :set_order
before_action :prevent_self_checkin!, only: :update
```

```ruby
def prevent_self_checkin!
  return unless current_user.attendees.exists?(order: @order)
  render json: { error: I18n.t('auth.errors.forbidden') }, status: :forbidden
end
```

Uses the same 403 body as the existing permission check.

### Modified File

`app/controllers/api/v1/scan/orders_controller.rb`

### Test Cases (added to existing `spec/requests/api/v1/scan/orders_spec.rb`)

- PATCH returns 403 when the authenticated user is an attendee in the order
- PATCH returns 403 when the user is an attendee in the order even if they also have the `can_check_in_attendees` permission (admin/volunteer who also registered)
- GET is unaffected — returns 200 even when the user is an attendee in the order

---

## Feature 2: Scan Events List

### Endpoint

```
GET /api/v1/scan/events
```

**Auth:** JWT + `can_check_in_attendees` (admin or volunteer). Returns 401/403 otherwise.

**Response — 200 OK:**

Array of live events whose `start_date` is in the future, sorted by `start_date ASC` (soonest first). Empty array `[]` when none match.

```json
[
  { "name": "Conferința 2026", "slug": "conferinta-2026" },
  { "name": "Tabăra 2026",     "slug": "tabara-2026" }
]
```

`name` is resolved from the event's translation for `current_user.language`, falling back to `ro-RO` if no translation exists for the user's language, then to the first available translation if `ro-RO` also has none.

### Scope

- Status: `live` only (excludes `draft`, `cancelled`, `deleted`)
- Date: `start_date > Time.current`
- Sort: `start_date ASC`

### Code Structure

**New file:** `app/controllers/api/v1/scan/events_controller.rb`

```
class Api::V1::Scan::EventsController < ActionController::API
  include Authenticatable
  before_action :authenticate_user!
  before_action { require_permission!(:can_check_in_attendees) }

  def index
    # query: Event.live.where('start_date > ?', Time.current).order(:start_date)
    # with includes(:events_translations)
    # serialise inline: { name: resolve_name(event), slug: event.slug }
  end
end
```

**Route:** `get 'events', to: 'events#index'` inside `namespace :scan`

**Modified file:** `config/routes.rb`

### Test Cases (`spec/requests/api/v1/scan/events_spec.rb`)

- 401 without token
- 403 for attendee role
- Returns only live future events (excludes past start_date, excludes non-live status)
- Returns name from user's language translation
- Falls back to ro-RO when user's language has no translation
- Returns slug
- Sorted by start_date ASC (soonest first)
- Returns empty array when no upcoming live events
