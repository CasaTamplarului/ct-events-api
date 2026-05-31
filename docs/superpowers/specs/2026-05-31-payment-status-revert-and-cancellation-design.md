# Payment Status Revert, Attendee Cancelled & Booking Cancellation Design

**Date:** 2026-05-31  
**Status:** Approved

## Overview

Three related changes:

1. **Revert payment_status to attendees** — move `payment_status` back from `orders` to `attendees` where it semantically belongs; add `attendee_cancelled` as a 4th enum value
2. **Computed order payment_status** — `Order#payment_status` becomes a derived method (no stored column), computed from the attendees' individual statuses
3. **Booking cancellation endpoints** — users can cancel their own order or a single attendee (only when `payment_pending`)

---

## Database Changes

### Migration: Revert payment_status to attendees

- Remove `payment_status` column from `orders`
- Re-add `payment_status` (integer, default 0, not null) to `attendees`
- Data migration: for each attendee whose order had a non-default payment_status, copy it to the attendee

Enum values on `attendees.payment_status`:

| Integer | Symbol | Meaning |
|---------|--------|---------|
| 0 | `payment_pending` | Awaiting bank transfer |
| 1 | `paid` | Payment confirmed by admin |
| 2 | `refunded` | Admin-processed refund (was paid, then cancelled) |
| 3 | `attendee_cancelled` | User self-cancelled before paying |

---

## Model Changes

### `Attendee`

Restore the full enum:

```ruby
enum :payment_status, { payment_pending: 0, paid: 1, refunded: 2, attendee_cancelled: 3 }
```

### `Order`

Remove the stored `payment_status` enum. Add two computed methods:

```ruby
def payment_status(attendees_collection = nil)
  collection = attendees_collection || attendees
  active = collection.reject(&:attendee_cancelled?)
  return 'attendee_cancelled' if active.empty?

  statuses = active.map(&:payment_status).uniq
  statuses.size == 1 ? statuses.first : 'partial'
end

def payment_pending?(attendees_collection = nil)
  %w[payment_pending partial].include?(payment_status(attendees_collection))
end
```

**Computed status rules:**

| Active attendee statuses | Computed order status |
|--------------------------|----------------------|
| All `payment_pending` | `payment_pending` |
| All `paid` | `paid` |
| All `refunded` | `refunded` |
| All `attendee_cancelled` (none active) | `attendee_cancelled` |
| Any mix | `partial` |

"Active" = not `attendee_cancelled`. Cancelled attendees are excluded from the computation.

`payment_pending?` returns true for both `payment_pending` and `partial` — used by the booking confirmation email to indicate money is still owed.

**Important:** callers must pass the already-loaded attendees collection to avoid N+1 queries. See consumer updates below.

---

## Consumer Updates

### `ScanSerialisable` concern

`serialise_order` now:
- Passes loaded attendees to `order.payment_status(attendees)`
- Includes `payment_status` in each serialised attendee

```ruby
def serialise_order(order)
  attendees = if order.association(:attendees).loaded?
                order.attendees.sort_by(&:id)
              else
                order.attendees
                     .includes(:checked_in_by, ticket: :tickets_translations)
                     .order(:id)
              end
  {
    order_reference: order.order_reference,
    payment_status: order.payment_status(attendees),
    attendees: attendees.map { |a| serialise_attendee(a) }
  }
end

def serialise_attendee(attendee)
  by = attendee.checked_in_by
  {
    id: attendee.id,
    first_name: attendee.first_name,
    last_name: attendee.last_name,
    email_address: attendee.email_address,
    ticket_name: attendee.ticket
                         &.tickets_translations
                         &.find { |t| t.languages_code == 'ro-RO' }
                         &.name,
    payment_status: attendee.payment_status,
    checked_in: attendee.checked_in,
    checked_in_at: attendee.checked_in_at,
    checked_in_by: by ? "#{by.first_name} #{by.last_name}".strip : nil
  }
end
```

### `Scan::OrdersController` — PATCH update action

`update_attendee_checkins` now also accepts optional `payment_status` per attendee entry. The permitted params expand:

```ruby
update_params = params.permit(:payment_status, attendees: %i[id checked_in payment_status])
```

Note: the top-level `payment_status` param (for updating the whole order's payment) is **removed** — payment is now per-attendee. If `payment_status` is sent at the top level it is ignored. Each attendee entry may optionally include a `payment_status` value.

Updated `update_attendee_checkins`:

```ruby
def update_attendee_checkins(update_params)
  return if update_params[:attendees].blank?

  order_attendees = @order.attendees.index_by(&:id)
  Array(update_params[:attendees]).each do |entry|
    attendee = order_attendees[entry[:id].to_i]
    next unless attendee

    attrs = {}
    if entry.key?(:checked_in)
      if ActiveModel::Type::Boolean.new.cast(entry[:checked_in])
        attrs.merge!(checked_in: true, checked_in_at: Time.current, checked_in_by_user_id: current_user.id)
      else
        attrs.merge!(checked_in: false, checked_in_at: nil, checked_in_by_user_id: nil)
      end
    end

    if entry[:payment_status].present? && Attendee.payment_statuses.key?(entry[:payment_status].to_s)
      attrs[:payment_status] = entry[:payment_status]
    end

    attendee.update!(attrs) if attrs.any?
  end
end
```

The PATCH `update` action's top-level `payment_status` validation is removed. The "Nothing to update" guard stays.

### `BookingsController`

**`orders_for_user_scoped_to`**: exclude cancelled attendees so orders where all user's attendees are cancelled don't appear in upcoming/past lists:

```ruby
Attendee.joins(:event)
        .where(user_id: current_user.id)
        .where.not(payment_status: :attendee_cancelled)
        .where(where_clause, Time.current)
        .where(events: { status: Event.statuses[:live] })
        .order(sort)
        .pluck(:order_id)
        .uniq
```

**`check` action**: revert to filtering on attendee-level payment_status (remove the `merge(Order.where(...))` that was added during the order-level migration):

```ruby
.where(payment_status: %i[paid payment_pending])
```

**`serialise_order`**: pass loaded attendees to `order.payment_status`:

```ruby
payment_status: order.payment_status(attendees),
```

### `SendgridService`

Load all attendees first (not just those with emails), pass to `order.payment_pending?`:

```ruby
def send_booking_confirmation(order:, language:)
  all_attendees = order.attendees
                       .includes({ ticket: :tickets_translations }, { event: :events_translations })
                       .to_a

  attendees_with_email = all_attendees.reject { |a| a.email_address.blank? }
  return if attendees_with_email.empty?

  # ... qr code generation ...

  attendees_with_email.group_by(&:email_address).each do |email_address, group|
    send_confirmation_to(
      email_address: email_address,
      group: group,
      order: order,
      all_attendees: all_attendees,
      # ...
    )
  end
end
```

In `send_confirmation_to`, replace `order.payment_pending?` with `order.payment_pending?(all_attendees)`.

### Factories & specs

- `spec/factories/attendees.rb`: no changes needed (no payment_status was in factory)
- `spec/factories/orders.rb`: no changes needed
- `spec/requests/api/v1/auth/me/bookings_spec.rb`: `create_booking` helper → `create(:attendee, ..., payment_status: payment_status)` instead of `create(:order, ..., payment_status: payment_status)`
- `spec/services/sendgrid_service_spec.rb`: move `payment_status` back to attendee
- Scan specs: add `payment_status` assertions to attendee shape

---

## Cancellation Endpoints

### Routes (added to `auth/me/bookings` scope)

```ruby
scope '/me/bookings' do
  get  :upcoming, to: 'me/bookings#upcoming'
  get  :past,     to: 'me/bookings#past'
  post :check,    to: 'me/bookings#check'
  delete ':order_reference',              to: 'me/bookings#cancel_order',    as: 'cancel_booking'
  delete ':order_reference/attendees/:id', to: 'me/bookings#cancel_attendee', as: 'cancel_booking_attendee'
end
```

### Controller actions (in `Me::BookingsController`)

**`cancel_order`**: cancels all `payment_pending` attendees in the order that belong to `current_user`

```ruby
def cancel_order
  order = Order.find_by(order_reference: params[:order_reference])
  return render json: { error: 'Not found' }, status: :not_found unless order

  cancellable = order.attendees.where(user_id: current_user.id, payment_status: :payment_pending)
  return render json: { error: I18n.t('bookings.errors.nothing_to_cancel') }, status: :unprocessable_content if cancellable.empty?

  cancellable.update_all(payment_status: Attendee.payment_statuses['attendee_cancelled']) # rubocop:disable Rails/SkipsModelValidations
  render json: serialise_order(order, order.attendees.includes({ ticket: :tickets_translations }, { event: :events_translations }).where(user_id: current_user.id).to_a)
end
```

**`cancel_attendee`**: cancels a single attendee

```ruby
def cancel_attendee
  order = Order.find_by(order_reference: params[:order_reference])
  return render json: { error: 'Not found' }, status: :not_found unless order

  attendee = order.attendees.find_by(id: params[:id], user_id: current_user.id)
  return render json: { error: 'Not found' }, status: :not_found unless attendee

  unless attendee.payment_pending?
    return render json: { error: I18n.t('bookings.errors.cannot_cancel') }, status: :unprocessable_content
  end

  attendee.update!(payment_status: :attendee_cancelled)
  attendees = order.attendees.includes({ ticket: :tickets_translations }, { event: :events_translations }).where(user_id: current_user.id).to_a
  render json: serialise_order(order, attendees)
end
```

### I18n keys to add

```yaml
# en.yml and ro.yml
bookings:
  errors:
    nothing_to_cancel: "No cancellable attendees found for this order"
    cannot_cancel: "This attendee cannot be cancelled (payment already processed)"
```

### Response

Same shape as the existing `upcoming` booking entry:

```json
{
  "order_reference": "CT-2026-00042",
  "payment_status": "attendee_cancelled",
  "total_price": 0,
  "event": { "name": "...", "slug": "...", "start_date": "...", "end_date": "...", "location_name": "...", "address": "..." },
  "attendees": [
    { "first_name": "Ion", "last_name": "Popescu", "ticket_name": "General", "ticket_price": 150, "food_included": false, "dietary_preference": "no_preference" }
  ]
}
```

### Error responses

| Scenario | Status |
|----------|--------|
| Order not found | 404 |
| No cancellable attendees in order (all paid/refunded/already cancelled) | 422 |
| Attendee not found or belongs to another user | 404 |
| Attendee is paid or refunded | 422 |

### Test cases (`spec/requests/api/v1/auth/me/bookings_spec.rb`)

**`DELETE /me/bookings/:order_reference`:**
- 401 without token
- 404 for unknown order reference
- 404 for order belonging to another user (no attendees for current user)
- 422 when all user's attendees are already paid
- 422 when all user's attendees are already cancelled
- 200: cancels all payment_pending attendees, returns updated order
- 200: does not cancel attendees belonging to other users in the same order
- 200: does not cancel paid attendees in the same order

**`DELETE /me/bookings/:order_reference/attendees/:id`:**
- 401 without token
- 404 for unknown order reference
- 404 for attendee belonging to another user
- 422 when attendee is already paid
- 422 when attendee is already cancelled
- 200: cancels the specific attendee, returns updated order
- 200: does not affect other attendees in the same order
