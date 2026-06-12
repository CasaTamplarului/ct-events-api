# Ticket Valid Date Range — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `valid_from` / `valid_to` date columns to tickets so staff can restrict day-tickets to a specific date range in Directus; check-in outside the range is a hard block.

**Architecture:** Two nullable `date` columns on `tickets`; a Rails migration also registers them in `directus_fields`. `ScanSerialisable#serialise_attendee` exposes the dates to the UI. `OrdersController#update_attendee_checkins` validates `Date.current` against the range before setting `checked_in: true`.

**Tech Stack:** Rails 8.1, RSpec, PostgreSQL, Directus 10 (port 8092)

---

### Task 1: Migration — add `valid_from` / `valid_to` and register in Directus

**Files:**
- Create: `db/migrate/20260612120000_add_valid_dates_to_tickets.rb`

- [ ] **Step 1: Write the migration**

```ruby
# db/migrate/20260612120000_add_valid_dates_to_tickets.rb
# frozen_string_literal: true

class AddValidDatesToTickets < ActiveRecord::Migration[8.1]
  def up
    add_column :tickets, :valid_from, :date
    add_column :tickets, :valid_to,   :date

    execute("DELETE FROM directus_fields WHERE collection = 'tickets' AND field IN ('valid_from', 'valid_to')")
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, special, options, width)
      VALUES
        ('tickets', 'valid_from', 'datetime', false, false, NULL, NULL, 'half'),
        ('tickets', 'valid_to',   'datetime', false, false, NULL, NULL, 'half')
    SQL
  end

  def down
    remove_column :tickets, :valid_from
    remove_column :tickets, :valid_to
    execute("DELETE FROM directus_fields WHERE collection = 'tickets' AND field IN ('valid_from', 'valid_to')")
  end
end
```

- [ ] **Step 2: Run on dev DB (port 5432)**

```bash
bin/rails db:migrate
```

Expected: `AddValidDatesToTickets: migrated`

- [ ] **Step 3: Run on production DB (port 5433)**

```bash
DATABASE_PORT=5433 DATABASE_PASSWORD=cTeventsPostgres2024! bin/rails db:migrate
```

Expected: `AddValidDatesToTickets: migrated`

- [ ] **Step 4: Restart Directus to reload schema cache**

```bash
docker restart events-directus-1
```

Wait ~5 seconds, then verify the `valid_from` and `valid_to` fields appear on the Tickets collection in the Directus UI at http://localhost:8092.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20260612120000_add_valid_dates_to_tickets.rb db/schema.rb
git commit -m "Add valid_from/valid_to date range to tickets"
```

---

### Task 2: Locale strings

**Files:**
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ro.yml`

- [ ] **Step 1: Add English key**

In `config/locales/en.yml`, under `scan.errors`:

```yaml
      invalid_checkin_date: "This ticket is not valid for today's date"
```

Result:
```yaml
  scan:
    errors:
      self_checkin_forbidden: "You cannot check in an order you are part of"
      attendee_not_eligible: "This attendee's ticket has been cancelled or refunded"
      invalid_checkin_date: "This ticket is not valid for today's date"
```

- [ ] **Step 2: Add Romanian key**

In `config/locales/ro.yml`, under `scan.errors`:

```yaml
      invalid_checkin_date: "Acest bilet nu este valabil pentru data de astăzi"
```

Result:
```yaml
  scan:
    errors:
      self_checkin_forbidden: "Nu poți efectua check-in pentru o comandă la care ești participant"
      attendee_not_eligible: "Biletul acestui participant a fost anulat sau rambursat"
      invalid_checkin_date: "Acest bilet nu este valabil pentru data de astăzi"
```

- [ ] **Step 3: Commit**

```bash
git add config/locales/en.yml config/locales/ro.yml
git commit -m "Add invalid_checkin_date locale key"
```

---

### Task 3: Expose `valid_from` / `valid_to` in scan serializer

**Files:**
- Modify: `app/controllers/concerns/scan_serialisable.rb`

- [ ] **Step 1: Write a failing test**

In `spec/requests/api/v1/scan/orders_spec.rb`, inside the `GET` describe block, add after the existing "includes required fields" test:

```ruby
context 'when an attendee has a ticket with valid dates' do
  before do
    ticket = create(:ticket, event: event, valid_from: Date.new(2026, 6, 18), valid_to: Date.new(2026, 6, 20))
    first_attendee.update!(ticket: ticket)
  end

  it 'includes valid_from and valid_to on the attendee' do
    get_order(order.order_reference)
    a = json['attendees'].find { |x| x['id'] == first_attendee.id }
    expect(a['valid_from']).to eq('2026-06-18')
    expect(a['valid_to']).to eq('2026-06-20')
  end
end

context 'when an attendee has a ticket with no valid dates' do
  before do
    ticket = create(:ticket, event: event)
    first_attendee.update!(ticket: ticket)
  end

  it 'returns valid_from and valid_to as nil' do
    get_order(order.order_reference)
    a = json['attendees'].find { |x| x['id'] == first_attendee.id }
    expect(a['valid_from']).to be_nil
    expect(a['valid_to']).to be_nil
  end
end
```

- [ ] **Step 2: Run the tests and confirm they fail**

```bash
bin/rspec spec/requests/api/v1/scan/orders_spec.rb --format documentation 2>&1 | grep -A2 "valid_from\|valid_to"
```

Expected: FAILED — key not present in response.

- [ ] **Step 3: Add `valid_from` and `valid_to` to `serialise_attendee`**

In `app/controllers/concerns/scan_serialisable.rb`, add after `ticket_price`:

```ruby
        ticket_price:   attendee.ticket&.price,
        valid_from:     attendee.ticket&.valid_from,
        valid_to:       attendee.ticket&.valid_to,
```

- [ ] **Step 4: Run the tests and confirm they pass**

```bash
bin/rspec spec/requests/api/v1/scan/orders_spec.rb --format documentation 2>&1 | grep -E "valid_from|valid_to|FAILED|passed"
```

Expected: both new examples pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/concerns/scan_serialisable.rb spec/requests/api/v1/scan/orders_spec.rb
git commit -m "Expose ticket valid_from/valid_to in scan serializer"
```

---

### Task 4: Check-in date validation

**Files:**
- Modify: `app/controllers/api/v1/scan/orders_controller.rb`

- [ ] **Step 1: Write failing tests**

In `spec/requests/api/v1/scan/orders_spec.rb`, inside the `PATCH` describe block, add after the existing check-in tests:

```ruby
context 'ticket valid date range' do
  let(:ticket) { create(:ticket, event: event) }

  before { first_attendee.update!(ticket: ticket) }

  context 'when ticket has no valid dates' do
    it 'allows check-in on any day' do
      patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: true }] })
      expect(response).to have_http_status(:ok)
      expect(first_attendee.reload.checked_in).to be true
    end
  end

  context 'when today is within the valid range' do
    before { ticket.update!(valid_from: Date.current - 1, valid_to: Date.current + 1) }

    it 'allows check-in' do
      patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: true }] })
      expect(response).to have_http_status(:ok)
      expect(first_attendee.reload.checked_in).to be true
    end
  end

  context 'when today is before valid_from' do
    before { ticket.update!(valid_from: Date.current + 1, valid_to: Date.current + 2) }

    it 'returns 422 and does not check in the attendee' do
      patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: true }] })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq("This ticket is not valid for today's date")
      expect(first_attendee.reload.checked_in).to be false
    end
  end

  context 'when today is after valid_to' do
    before { ticket.update!(valid_from: Date.current - 2, valid_to: Date.current - 1) }

    it 'returns 422 and does not check in the attendee' do
      patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: true }] })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq("This ticket is not valid for today's date")
      expect(first_attendee.reload.checked_in).to be false
    end
  end

  context 'when today equals valid_from (first day)' do
    before { ticket.update!(valid_from: Date.current, valid_to: Date.current + 1) }

    it 'allows check-in' do
      patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: true }] })
      expect(response).to have_http_status(:ok)
    end
  end

  context 'when today equals valid_to (last day)' do
    before { ticket.update!(valid_from: Date.current - 1, valid_to: Date.current) }

    it 'allows check-in' do
      patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: true }] })
      expect(response).to have_http_status(:ok)
    end
  end

  context 'when only valid_from is set and today is before it' do
    before { ticket.update!(valid_from: Date.current + 1, valid_to: nil) }

    it 'returns 422' do
      patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: true }] })
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  context 'when only valid_to is set and today is after it' do
    before { ticket.update!(valid_from: nil, valid_to: Date.current - 1) }

    it 'returns 422' do
      patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: true }] })
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  context 'when unchecking an attendee with an invalid date ticket' do
    before do
      ticket.update!(valid_from: Date.current + 1, valid_to: Date.current + 2)
      first_attendee.update!(checked_in: true, checked_in_at: Time.current,
                              checked_in_by_user_id: admin.id)
    end

    it 'allows unchecking regardless of date' do
      patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: false }] })
      expect(response).to have_http_status(:ok)
      expect(first_attendee.reload.checked_in).to be false
    end
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rspec spec/requests/api/v1/scan/orders_spec.rb --format documentation 2>&1 | grep -E "ticket valid date|FAILED|failed"
```

Expected: multiple failures — no date validation exists yet.

- [ ] **Step 3: Update `update_attendee_checkins` in `OrdersController`**

Replace the `update_attendee_checkins` method and the `update` action in `app/controllers/api/v1/scan/orders_controller.rb`:

```ruby
def update
  update_params = params.permit(attendees: %i[id checked_in payment_status])

  if update_params[:attendees].blank?
    return render json: { error: 'Nothing to update' }, status: :unprocessable_content
  end

  error = update_attendee_checkins(update_params)
  return render json: error, status: :unprocessable_content if error

  render json: serialise_order(@order)
end
```

```ruby
def update_attendee_checkins(update_params) # rubocop:disable Metrics/CyclomaticComplexity
  order_attendees = @order.attendees.includes(:ticket).index_by(&:id)
  Array(update_params[:attendees]).each do |entry|
    attendee = order_attendees[entry[:id].to_i]
    next unless attendee

    attrs = {}

    if entry.key?(:checked_in)
      if ActiveModel::Type::Boolean.new.cast(entry[:checked_in])
        if date_restricted?(attendee.ticket)
          return { error: I18n.t('scan.errors.invalid_checkin_date') }
        end

        attrs.merge!(checked_in: true, checked_in_at: Time.current,
                     checked_in_by_user_id: current_user.id)
        attrs[:payment_status] = :payment_pending if attendee.attendee_cancelled? || attendee.refunded?
      else
        attrs.merge!(checked_in: false, checked_in_at: nil, checked_in_by_user_id: nil)
      end
    end

    if entry[:payment_status].present? && Attendee.payment_statuses.key?(entry[:payment_status].to_s)
      attrs[:payment_status] = entry[:payment_status]
    end

    attendee.update!(attrs) if attrs.any?
  end
  nil
end

def date_restricted?(ticket)
  return false unless ticket
  return false if ticket.valid_from.nil? && ticket.valid_to.nil?

  today = Date.current
  (ticket.valid_from && today < ticket.valid_from) ||
    (ticket.valid_to  && today > ticket.valid_to)
end
```

- [ ] **Step 4: Run the tests and confirm they all pass**

```bash
bin/rspec spec/requests/api/v1/scan/orders_spec.rb --format documentation
```

Expected: all examples pass, 0 failures.

- [ ] **Step 5: Run the full test suite to check for regressions**

```bash
bin/rails test && bin/rspec
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/api/v1/scan/orders_controller.rb spec/requests/api/v1/scan/orders_spec.rb
git commit -m "Block check-in when ticket date range does not include today"
```

---

### Task 5: Push

- [ ] **Push all commits**

```bash
git push origin master
```
