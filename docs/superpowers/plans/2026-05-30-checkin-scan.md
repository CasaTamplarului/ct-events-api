# Check-in Scan Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two scan endpoints (`GET` and `PATCH` `/api/v1/scan/orders/:order_reference`) that let admins/volunteers look up an order by its reference and check in attendees, with payment status tracked at the order level.

**Architecture:** Move `payment_status` from `attendees` to `orders` (breaking change that touches BookingsController, SendgridService, and their specs), add check-in tracking columns to `attendees`, then build the scan controller under a new `/api/v1/scan` namespace protected by JWT + `can_check_in_attendees` permission.

**Tech Stack:** Rails 8.1, RSpec, FactoryBot, PostgreSQL

---

## File Map

| Action | File | Purpose |
|--------|------|---------|
| Create | `db/migrate/TIMESTAMP_move_payment_status_to_orders.rb` | Move payment_status column + data migration |
| Create | `db/migrate/TIMESTAMP_add_checkin_to_attendees.rb` | Add checked_in, checked_in_at, checked_in_by_user_id columns |
| Modify | `app/models/order.rb` | Add payment_status enum |
| Modify | `app/models/attendee.rb` | Remove payment_status enum; add checked_in_by association |
| Modify | `config/routes.rb` | Add scan namespace |
| Create | `app/controllers/api/v1/scan/orders_controller.rb` | New scan controller |
| Modify | `app/controllers/api/v1/auth/me/bookings_controller.rb` | Fix check action filter + serialise_order |
| Modify | `app/services/sendgrid_service.rb` | Fix is_pending to read from order |
| Modify | `spec/factories/orders.rb` | Add payment_status default |
| Modify | `spec/requests/api/v1/auth/me/bookings_spec.rb` | Move payment_status to order in fixtures |
| Modify | `spec/services/sendgrid_service_spec.rb` | Move payment_status to order in fixture |
| Create | `spec/requests/api/v1/scan/orders_spec.rb` | New scan endpoint specs |

---

## Task 1: Move payment_status from attendees to orders

This is a breaking change. All code changes must be made in one commit so the test suite is never left in a broken state. The column currently stores `0=payment_pending, 1=paid, 2=refunded`.

**Files:**
- Create: `db/migrate/TIMESTAMP_move_payment_status_to_orders.rb`
- Modify: `app/models/order.rb`
- Modify: `app/models/attendee.rb`
- Modify: `app/controllers/api/v1/auth/me/bookings_controller.rb`
- Modify: `app/services/sendgrid_service.rb`
- Modify: `spec/factories/orders.rb`
- Modify: `spec/requests/api/v1/auth/me/bookings_spec.rb`
- Modify: `spec/services/sendgrid_service_spec.rb`

- [ ] **Step 1: Generate the migration file**

```bash
bin/rails generate migration MovePaymentStatusToOrders
```

Open the generated file in `db/migrate/` and replace its contents with:

```ruby
# frozen_string_literal: true

class MovePaymentStatusToOrders < ActiveRecord::Migration[8.1]
  def up
    add_column :orders, :payment_status, :integer, default: 0, null: false

    execute <<~SQL
      UPDATE orders
      SET payment_status = (
        SELECT payment_status
        FROM attendees
        WHERE attendees.order_id = orders.id
        ORDER BY attendees.id ASC
        LIMIT 1
      )
      WHERE EXISTS (
        SELECT 1 FROM attendees WHERE attendees.order_id = orders.id
      )
    SQL

    remove_column :attendees, :payment_status
  end

  def down
    add_column :attendees, :payment_status, :integer, default: 0, null: false

    execute <<~SQL
      UPDATE attendees
      SET payment_status = orders.payment_status
      FROM orders
      WHERE attendees.order_id = orders.id
    SQL

    remove_column :orders, :payment_status
  end
end
```

- [ ] **Step 2: Update `app/models/order.rb`**

Replace the entire file with:

```ruby
# frozen_string_literal: true

class Order < ApplicationRecord
  has_many :attendees, dependent: :destroy

  enum :payment_status, { payment_pending: 0, paid: 1, refunded: 2 }

  after_create :generate_order_reference

  private

  def generate_order_reference
    update_column(:order_reference, "CT-#{created_at.year}-#{format('%05d', id)}")
  end
end
```

- [ ] **Step 3: Update `app/models/attendee.rb`**

Remove the `payment_status` enum line. Replace the entire file with:

```ruby
# frozen_string_literal: true

class Attendee < ApplicationRecord
  belongs_to :event
  belongs_to :user, optional: true
  belongs_to :order, optional: true
  belongs_to :ticket, optional: true

  enum :dietary_preference, { no_preference: 0, vegetarian: 1, vegan: 2 }

  def self.backfill_user(email:, user_id:)
    # rubocop:disable Rails/SkipsModelValidations
    where('LOWER(email_address) = LOWER(?)', email).update_all(user_id: user_id)
    # rubocop:enable Rails/SkipsModelValidations
  end
end
```

- [ ] **Step 4: Update `app/controllers/api/v1/auth/me/bookings_controller.rb`**

Two changes in this file:

**Change 1** — `check` action (line ~44). The filter `.where(payment_status: ...)` was on attendees; it must now join through orders. Find this line:

```ruby
              .where(payment_status: %i[paid payment_pending])
```

Replace with:

```ruby
              .merge(Order.where(payment_status: %i[paid payment_pending]))
```

**Change 2** — `serialise_order` private method (line ~94). Find:

```ruby
                payment_status: attendees.first.payment_status,
```

Replace with:

```ruby
                payment_status: order.payment_status,
```

- [ ] **Step 5: Update `app/services/sendgrid_service.rb`**

In the `send_confirmation_to` private method, find:

```ruby
          'is_pending' => group.first.payment_pending?,
```

Replace with:

```ruby
          'is_pending' => order.payment_pending?,
```

(`order` is already a named parameter of `send_confirmation_to`.)

- [ ] **Step 6: Update `spec/factories/orders.rb`**

Replace the entire file with:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :order do
    payment_status { :payment_pending }
    sequence(:order_reference) { |n| "CT-#{Time.zone.now.year}-#{n.to_s.rjust(5, '0')}" }
  end
end
```

- [ ] **Step 7: Update `spec/requests/api/v1/auth/me/bookings_spec.rb`**

**Change 1** — `create_booking` helper (~lines 16-29). Move `payment_status` from the attendee to the order, and remove it from the attendee:

```ruby
  def create_booking(user:, start_date:, end_date:, payment_status: :paid, with_ticket: false)
    event = create(:event, start_date: start_date, end_date: end_date)
    create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Conferința Test')
    order = create(:order, payment_status: payment_status)
    ticket = nil
    if with_ticket
      ticket = create(:ticket, event: event, price: 150, food_included: true)
      create(:tickets_translation, tickets_id: ticket.id, languages_code: 'ro-RO', name: 'Adult',
                                   description: 'Includes all meals')
    end
    attendee = create(:attendee, event: event, order: order, user: user, ticket: ticket)
    { event: event, order: order, attendee: attendee }
  end
```

**Change 2** — `check` action context "with a paid booking" (~line 243-246). Move `payment_status` from attendee to order:

```ruby
    context 'with a paid booking' do
      before do
        order = create(:order, payment_status: :paid)
        create(:attendee, event: event_a, order: order, user: user)
      end
```

**Change 3** — `check` action context "with a payment_pending booking" (~line 256-260):

```ruby
    context 'with a payment_pending booking' do
      before do
        order = create(:order, payment_status: :payment_pending)
        create(:attendee, event: event_a, order: order, user: user)
      end
```

**Change 4** — `check` action context "with a refunded booking" (~line 268-272):

```ruby
    context 'with a refunded booking' do
      before do
        order = create(:order, payment_status: :refunded)
        create(:attendee, event: event_a, order: order, user: user)
      end
```

**Change 5** — `check` action context "with multiple slugs" (~line 297-301):

```ruby
    context 'with multiple slugs' do
      before do
        order = create(:order, payment_status: :paid)
        create(:attendee, event: event_a, order: order, user: user)
      end
```

- [ ] **Step 8: Update `spec/services/sendgrid_service_spec.rb`**

Find the "sets is_pending: false when payment is paid" example (~lines 170-178). Move `payment_status` from the attendee to the order:

```ruby
      it 'sets is_pending: false when payment is paid' do # rubocop:disable RSpec/ExampleLength
        paid_order = create(:order, payment_status: :paid)
        create(:attendee, event: event, order: paid_order, ticket: ticket,
                          email_address: 'paid@example.com')
        described_class.send_booking_confirmation(order: paid_order, language: language_code)
        dtd = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
                  .dig('personalizations', 0, 'dynamic_template_data')
        expect(dtd['is_pending']).to be(false)
      end
```

- [ ] **Step 9: Run the migration**

```bash
bin/rails db:migrate
```

Expected: migration runs without errors.

- [ ] **Step 10: Run the affected specs**

```bash
bin/rspec spec/requests/api/v1/auth/me/bookings_spec.rb spec/services/sendgrid_service_spec.rb
```

Expected: all examples pass.

- [ ] **Step 11: Commit**

```bash
git add db/migrate app/models/order.rb app/models/attendee.rb \
  app/controllers/api/v1/auth/me/bookings_controller.rb \
  app/services/sendgrid_service.rb \
  spec/factories/orders.rb \
  spec/requests/api/v1/auth/me/bookings_spec.rb \
  spec/services/sendgrid_service_spec.rb \
  db/schema.rb
git commit -m "Move payment_status from attendees to orders"
```

---

## Task 2: Add check-in tracking columns to attendees

**Files:**
- Create: `db/migrate/TIMESTAMP_add_checkin_to_attendees.rb`
- Modify: `app/models/attendee.rb`

- [ ] **Step 1: Generate the migration**

```bash
bin/rails generate migration AddCheckinToAttendees
```

Open the generated file and replace its contents with:

```ruby
# frozen_string_literal: true

class AddCheckinToAttendees < ActiveRecord::Migration[8.1]
  def change
    add_column :attendees, :checked_in, :boolean, default: false, null: false
    add_column :attendees, :checked_in_at, :datetime
    add_column :attendees, :checked_in_by_user_id, :bigint
    add_foreign_key :attendees, :users, column: :checked_in_by_user_id
    add_index :attendees, :checked_in_by_user_id
  end
end
```

- [ ] **Step 2: Update `app/models/attendee.rb`**

Add the `checked_in_by` association. Replace the entire file with:

```ruby
# frozen_string_literal: true

class Attendee < ApplicationRecord
  belongs_to :event
  belongs_to :user, optional: true
  belongs_to :order, optional: true
  belongs_to :ticket, optional: true
  belongs_to :checked_in_by, class_name: 'User', foreign_key: :checked_in_by_user_id, optional: true

  enum :dietary_preference, { no_preference: 0, vegetarian: 1, vegan: 2 }

  def self.backfill_user(email:, user_id:)
    # rubocop:disable Rails/SkipsModelValidations
    where('LOWER(email_address) = LOWER(?)', email).update_all(user_id: user_id)
    # rubocop:enable Rails/SkipsModelValidations
  end
end
```

- [ ] **Step 3: Run the migration**

```bash
bin/rails db:migrate
```

Expected: migration runs without errors.

- [ ] **Step 4: Confirm existing specs still pass**

```bash
bin/rspec spec/models/attendee_spec.rb
```

Expected: all examples pass.

- [ ] **Step 5: Commit**

```bash
git add db/migrate app/models/attendee.rb db/schema.rb
git commit -m "Add check-in tracking columns to attendees"
```

---

## Task 3: Add scan routes and controller scaffold

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/api/v1/scan/orders_controller.rb`

- [ ] **Step 1: Add scan namespace to `config/routes.rb`**

Inside `namespace :api` → `namespace :v1`, add the following block alongside the existing `namespace :auth` and `scope '/:languages_code'` blocks:

```ruby
      namespace :scan do
        scope '/orders/:order_reference' do
          get  '/', to: 'orders#show',   as: 'scan_order'
          patch '/', to: 'orders#update', as: 'scan_order_update'
        end
      end
```

The full `v1` namespace will now look like:

```ruby
    namespace :v1 do
      namespace :auth do
        # ... existing auth routes ...
      end

      namespace :scan do
        scope '/orders/:order_reference' do
          get  '/', to: 'orders#show',   as: 'scan_order'
          patch '/', to: 'orders#update', as: 'scan_order_update'
        end
      end

      get '/unsubscribe', to: 'unsubscribe#show'

      scope '/:languages_code', constraints: { languages_code: /[a-zA-Z]{2}-[a-zA-Z]{2}/ } do
        # ... existing event routes ...
      end
    end
```

- [ ] **Step 2: Verify routes are defined**

```bash
bin/rails routes | grep scan
```

Expected output (approximately):

```
scan_order        GET   /api/v1/scan/orders/:order_reference(.:format)  api/v1/scan/orders#show
scan_order_update PATCH /api/v1/scan/orders/:order_reference(.:format)  api/v1/scan/orders#update
```

- [ ] **Step 3: Create `app/controllers/api/v1/scan/orders_controller.rb`**

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Scan
      class OrdersController < ActionController::API
        include Authenticatable

        before_action :authenticate_user!
        before_action { require_permission!(:can_check_in_attendees) }
        before_action :set_order

        def show
          render json: serialise_order
        end

        def update
        end

        private

          def set_order
            @order = Order.find_by(order_reference: params[:order_reference])
            render json: { error: 'Not found' }, status: :not_found unless @order
          end

          def serialise_order
            attendees = @order.attendees
                              .includes(:checked_in_by, ticket: :tickets_translations)
                              .order(:id)
            {
              order_reference: @order.order_reference,
              payment_status: @order.payment_status,
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
              checked_in: attendee.checked_in,
              checked_in_at: attendee.checked_in_at,
              checked_in_by: by ? "#{by.first_name} #{by.last_name}".strip : nil
            }
          end
      end
    end
  end
end
```

- [ ] **Step 4: Commit**

```bash
git add config/routes.rb app/controllers/api/v1/scan/
git commit -m "Add scan routes and orders controller scaffold"
```

---

## Task 4: Implement GET /api/v1/scan/orders/:order_reference (TDD)

**Files:**
- Create: `spec/requests/api/v1/scan/orders_spec.rb`
- Modify: `app/controllers/api/v1/scan/orders_controller.rb` (show action is already complete from Task 3)

- [ ] **Step 1: Create the spec file**

Create `spec/requests/api/v1/scan/orders_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Scan Orders API' do
  let(:admin)          { create(:user, role: 'admin') }
  let(:volunteer)      { create(:user, role: 'volunteer') }
  let(:attendee_user)  { create(:user, role: 'attendee') }
  let(:event)          { create(:event) }
  let(:order)          { create(:order, payment_status: :paid) }
  let!(:attendee1) do
    create(:attendee, event: event, order: order,
                      first_name: 'Ion', last_name: 'Popescu', email_address: 'ion@example.com')
  end
  let!(:attendee2) do
    create(:attendee, event: event, order: order,
                      first_name: 'Maria', last_name: 'Ionescu', email_address: 'maria@example.com')
  end

  def auth_header(user)
    { 'Authorization' => "Bearer #{JwtService.encode(user.id)}", 'Content-Type' => 'application/json' }
  end

  describe 'GET /api/v1/scan/orders/:order_reference' do
    def get_order(ref, user: admin)
      get "/api/v1/scan/orders/#{ref}", headers: auth_header(user)
    end

    it 'returns 401 without a token' do
      get "/api/v1/scan/orders/#{order.order_reference}"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 for attendee role' do
      get_order(order.order_reference, user: attendee_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 200 and order data for admin' do
      get_order(order.order_reference)
      expect(response).to have_http_status(:ok)
      expect(json['order_reference']).to eq(order.order_reference)
      expect(json['payment_status']).to eq('paid')
    end

    it 'returns 200 for volunteer role' do
      get_order(order.order_reference, user: volunteer)
      expect(response).to have_http_status(:ok)
    end

    it 'returns 404 for unknown order reference' do
      get_order('CT-2026-99999')
      expect(response).to have_http_status(:not_found)
    end

    it 'returns all attendees in the order' do
      get_order(order.order_reference)
      emails = json['attendees'].pluck('email_address')
      expect(emails).to contain_exactly('ion@example.com', 'maria@example.com')
    end

    it 'includes required fields on each attendee' do
      get_order(order.order_reference)
      a = json['attendees'].first
      expect(a.keys).to include('id', 'first_name', 'last_name', 'email_address',
                                'ticket_name', 'checked_in', 'checked_in_at', 'checked_in_by')
    end

    it 'returns checked_in: false and nil timestamps for unchecked attendees' do
      get_order(order.order_reference)
      a = json['attendees'].first
      expect(a['checked_in']).to be false
      expect(a['checked_in_at']).to be_nil
      expect(a['checked_in_by']).to be_nil
    end

    context 'when an attendee is checked in' do
      before do
        attendee1.update!(
          checked_in: true,
          checked_in_at: Time.zone.parse('2026-06-01 10:00:00'),
          checked_in_by_user_id: admin.id
        )
      end

      it 'returns checked_in: true with timestamp and checker name' do
        get_order(order.order_reference)
        a = json['attendees'].find { |x| x['id'] == attendee1.id }
        expect(a['checked_in']).to be true
        expect(a['checked_in_at']).to be_present
        expect(a['checked_in_by']).to eq("#{admin.first_name} #{admin.last_name}".strip)
      end
    end

    context 'when an attendee has a ticket with a ro-RO translation' do
      before do
        ticket = create(:ticket, event: event, price: 100)
        create(:tickets_translation, tickets_id: ticket.id, languages_code: 'ro-RO', name: 'General')
        attendee1.update!(ticket: ticket)
      end

      it 'includes the ticket name from the ro-RO translation' do
        get_order(order.order_reference)
        a = json['attendees'].find { |x| x['id'] == attendee1.id }
        expect(a['ticket_name']).to eq('General')
      end
    end

    context 'when an attendee has no ticket' do
      it 'returns ticket_name: nil' do
        get_order(order.order_reference)
        a = json['attendees'].find { |x| x['id'] == attendee1.id }
        expect(a['ticket_name']).to be_nil
      end
    end
  end
end
```

- [ ] **Step 2: Run the GET specs to verify they pass**

The `show` action is already implemented in the scaffold.

```bash
bin/rspec spec/requests/api/v1/scan/orders_spec.rb -e 'GET'
```

Expected: all GET examples pass.

- [ ] **Step 3: Commit**

```bash
git add spec/requests/api/v1/scan/orders_spec.rb
git commit -m "Add GET scan order endpoint with specs"
```

---

## Task 5: Implement PATCH /api/v1/scan/orders/:order_reference (TDD)

**Files:**
- Modify: `spec/requests/api/v1/scan/orders_spec.rb` (add PATCH tests)
- Modify: `app/controllers/api/v1/scan/orders_controller.rb` (implement update action)

- [ ] **Step 1: Add PATCH specs to the spec file**

Append the following `describe` block inside `RSpec.describe 'Scan Orders API'`, after the GET describe block:

```ruby
  describe 'PATCH /api/v1/scan/orders/:order_reference' do
    def patch_order(ref, body, user: admin)
      patch "/api/v1/scan/orders/#{ref}",
            params: body.to_json,
            headers: auth_header(user)
    end

    it 'returns 401 without a token' do
      patch "/api/v1/scan/orders/#{order.order_reference}",
            params: { payment_status: 'paid' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 for attendee role' do
      patch_order(order.order_reference, { payment_status: 'paid' }, user: attendee_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 404 for unknown order reference' do
      patch_order('CT-2026-99999', { payment_status: 'paid' })
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 422 when body has no updateable fields' do
      patch_order(order.order_reference, {})
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to eq('Nothing to update')
    end

    it 'returns 422 for an invalid payment_status value' do
      patch_order(order.order_reference, { payment_status: 'bounced' })
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns the same shape as GET on success' do
      patch_order(order.order_reference, { payment_status: 'paid' })
      expect(json.keys).to include('order_reference', 'payment_status', 'attendees')
    end

    context 'updating payment_status' do
      it 'marks the order as paid' do
        order.update!(payment_status: :payment_pending)
        patch_order(order.order_reference, { payment_status: 'paid' })
        expect(response).to have_http_status(:ok)
        expect(json['payment_status']).to eq('paid')
        expect(order.reload.payment_status).to eq('paid')
      end

      it 'marks the order as payment_pending (unpay)' do
        order.update!(payment_status: :paid)
        patch_order(order.order_reference, { payment_status: 'payment_pending' })
        expect(response).to have_http_status(:ok)
        expect(json['payment_status']).to eq('payment_pending')
        expect(order.reload.payment_status).to eq('payment_pending')
      end
    end

    context 'checking in attendees' do
      it 'checks in a single attendee and records who did it' do
        patch_order(order.order_reference, { attendees: [{ id: attendee1.id, checked_in: true }] })
        expect(response).to have_http_status(:ok)
        attendee1.reload
        expect(attendee1.checked_in).to be true
        expect(attendee1.checked_in_at).to be_present
        expect(attendee1.checked_in_by_user_id).to eq(admin.id)
      end

      it 'checks in multiple attendees in one request' do
        patch_order(order.order_reference, {
          attendees: [
            { id: attendee1.id, checked_in: true },
            { id: attendee2.id, checked_in: true }
          ]
        })
        expect(response).to have_http_status(:ok)
        expect(attendee1.reload.checked_in).to be true
        expect(attendee2.reload.checked_in).to be true
      end

      it 'unchecks in an attendee and clears the tracking fields' do
        attendee1.update!(checked_in: true, checked_in_at: Time.current,
                          checked_in_by_user_id: admin.id)
        patch_order(order.order_reference, { attendees: [{ id: attendee1.id, checked_in: false }] })
        expect(response).to have_http_status(:ok)
        attendee1.reload
        expect(attendee1.checked_in).to be false
        expect(attendee1.checked_in_at).to be_nil
        expect(attendee1.checked_in_by_user_id).to be_nil
      end

      it 'reflects check-in state in the response' do
        patch_order(order.order_reference, { attendees: [{ id: attendee1.id, checked_in: true }] })
        a = json['attendees'].find { |x| x['id'] == attendee1.id }
        expect(a['checked_in']).to be true
        expect(a['checked_in_by']).to eq("#{admin.first_name} #{admin.last_name}".strip)
      end

      it 'silently ignores attendee IDs not belonging to this order' do
        other_order = create(:order)
        other_attendee = create(:attendee, event: event, order: other_order)
        patch_order(order.order_reference, { attendees: [{ id: other_attendee.id, checked_in: true }] })
        expect(response).to have_http_status(:ok)
        expect(other_attendee.reload.checked_in).to be false
      end
    end

    context 'combined payment and check-in update' do
      it 'updates both in one request' do
        order.update!(payment_status: :payment_pending)
        patch_order(order.order_reference, {
          payment_status: 'paid',
          attendees: [{ id: attendee1.id, checked_in: true }]
        })
        expect(response).to have_http_status(:ok)
        expect(json['payment_status']).to eq('paid')
        a = json['attendees'].find { |x| x['id'] == attendee1.id }
        expect(a['checked_in']).to be true
      end
    end
  end
```

- [ ] **Step 2: Run the PATCH specs to see them fail**

```bash
bin/rspec spec/requests/api/v1/scan/orders_spec.rb -e 'PATCH'
```

Expected: failures because `update` action is empty.

- [ ] **Step 3: Implement the update action in `app/controllers/api/v1/scan/orders_controller.rb`**

Replace the empty `def update; end` and add two private helpers. The full controller becomes:

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Scan
      class OrdersController < ActionController::API
        include Authenticatable

        before_action :authenticate_user!
        before_action { require_permission!(:can_check_in_attendees) }
        before_action :set_order

        def show
          render json: serialise_order
        end

        def update
          if params[:payment_status].blank? && params[:attendees].blank?
            return render json: { error: 'Nothing to update' }, status: :unprocessable_entity
          end

          if params[:payment_status].present? && !Order.payment_statuses.key?(params[:payment_status].to_s)
            return render json: { error: "Invalid payment_status: #{params[:payment_status]}" },
                          status: :unprocessable_entity
          end

          ActiveRecord::Base.transaction do
            @order.update!(payment_status: params[:payment_status]) if params[:payment_status].present?
            update_attendee_checkins
          end

          render json: serialise_order
        end

        private

          def set_order
            @order = Order.find_by(order_reference: params[:order_reference])
            render json: { error: 'Not found' }, status: :not_found unless @order
          end

          def update_attendee_checkins
            return if params[:attendees].blank?

            order_attendee_ids = @order.attendees.pluck(:id).to_set
            Array(params[:attendees]).each do |entry|
              id = entry[:id].to_i
              next unless order_attendee_ids.include?(id)

              attendee = Attendee.find(id)
              if ActiveModel::Type::Boolean.new.cast(entry[:checked_in])
                attendee.update!(checked_in: true, checked_in_at: Time.current,
                                 checked_in_by_user_id: current_user.id)
              else
                attendee.update!(checked_in: false, checked_in_at: nil, checked_in_by_user_id: nil)
              end
            end
          end

          def serialise_order
            attendees = @order.attendees
                              .includes(:checked_in_by, ticket: :tickets_translations)
                              .order(:id)
            {
              order_reference: @order.order_reference,
              payment_status: @order.payment_status,
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
              checked_in: attendee.checked_in,
              checked_in_at: attendee.checked_in_at,
              checked_in_by: by ? "#{by.first_name} #{by.last_name}".strip : nil
            }
          end
      end
    end
  end
end
```

- [ ] **Step 4: Run all scan specs**

```bash
bin/rspec spec/requests/api/v1/scan/orders_spec.rb
```

Expected: all examples pass.

- [ ] **Step 5: Run the full test suite**

```bash
bin/rspec
```

Expected: all examples pass, no regressions.

- [ ] **Step 6: Run RuboCop**

```bash
bin/rubocop
```

Expected: no offenses. If there are any, fix them before committing.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/api/v1/scan/orders_controller.rb \
        spec/requests/api/v1/scan/orders_spec.rb
git commit -m "Implement PATCH scan order endpoint with check-in and payment update"
```
