# Payment Status Revert, Attendee Cancelled & Booking Cancellation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `payment_status` back to the `attendees` table (adding `attendee_cancelled` as a 4th value), derive order-level payment status from attendees, update all consumers, and add endpoints for users to cancel their own bookings.

**Architecture:** Task 1 is an atomic breaking change — migration + all consumer updates land in one commit so the suite is never broken. Task 2 adds cancellation endpoints using the new enum value. The `Order#payment_status` method is computed from its attendees collection; callers pass the already-loaded collection to avoid N+1.

**Tech Stack:** Rails 8.1, PostgreSQL, RSpec, FactoryBot

---

## File Map

| Action | File | Purpose |
|--------|------|---------|
| Create | `db/migrate/TIMESTAMP_revert_payment_status_to_attendees.rb` | Move column + add `attendee_cancelled` |
| Modify | `app/models/attendee.rb` | Restore 4-value enum |
| Modify | `app/models/order.rb` | Computed `payment_status` + `payment_pending?` |
| Modify | `app/controllers/concerns/scan_serialisable.rb` | Add per-attendee `payment_status`; use computed order status |
| Modify | `app/controllers/api/v1/scan/orders_controller.rb` | PATCH: remove order-level payment, add per-attendee; replace 'Not found' literal |
| Modify | `app/controllers/api/v1/scan/search_controller.rb` | Replace 'Not found' literal |
| Modify | `app/controllers/api/v1/auth/me/bookings_controller.rb` | Computed order status; exclude cancelled; revert `check` filter; add cancel actions |
| Modify | `app/services/sendgrid_service.rb` | Load all attendees; pass to `payment_pending?` |
| Modify | `config/routes.rb` | Add cancel routes |
| Modify | `spec/factories/orders.rb` | Remove `payment_status` default |
| Modify | `spec/requests/api/v1/scan/orders_spec.rb` | Update for per-attendee payment_status |
| Modify | `spec/requests/api/v1/auth/me/bookings_spec.rb` | Revert to attendee-level; add cancel tests |
| Modify | `spec/services/sendgrid_service_spec.rb` | Move `payment_status` back to attendee |

---

## Task 1: Migrate payment_status back to attendees + update all consumers

This is a breaking change. Every file change must land in a single commit. Do not run tests mid-task until all files are updated.

**Files:** All files listed above except `config/routes.rb` and the cancel tests.

- [ ] **Step 1: Generate the migration**

```bash
bin/rails generate migration RevertPaymentStatusToAttendees
```

Replace the generated file's contents with:

```ruby
# frozen_string_literal: true

class RevertPaymentStatusToAttendees < ActiveRecord::Migration[8.1]
  def up
    add_column :attendees, :payment_status, :integer, default: 0, null: false

    execute <<~SQL
      UPDATE attendees
      SET payment_status = orders.payment_status
      FROM orders
      WHERE attendees.order_id = orders.id
    SQL

    remove_column :orders, :payment_status
  end

  def down
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
end
```

- [ ] **Step 2: Update `app/models/attendee.rb`**

Replace the entire file with:

```ruby
# frozen_string_literal: true

class Attendee < ApplicationRecord
  belongs_to :event
  belongs_to :user, optional: true
  belongs_to :order, optional: true
  belongs_to :ticket, optional: true
  belongs_to :checked_in_by, class_name: 'User', foreign_key: :checked_in_by_user_id, optional: true,
                              inverse_of: false

  enum :payment_status, { payment_pending: 0, paid: 1, refunded: 2, attendee_cancelled: 3 }
  enum :dietary_preference, { no_preference: 0, vegetarian: 1, vegan: 2 }

  def self.backfill_user(email:, user_id:)
    # rubocop:disable Rails/SkipsModelValidations
    where('LOWER(email_address) = LOWER(?)', email).update_all(user_id: user_id)
    # rubocop:enable Rails/SkipsModelValidations
  end
end
```

- [ ] **Step 3: Update `app/models/order.rb`**

Replace the entire file with:

```ruby
# frozen_string_literal: true

class Order < ApplicationRecord
  has_many :attendees, dependent: :destroy

  after_create :generate_order_reference

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

  private

  def generate_order_reference
    update_column(:order_reference, "CT-#{created_at.year}-#{format('%05d', id)}")
  end
end
```

- [ ] **Step 4: Update `app/controllers/concerns/scan_serialisable.rb`**

Replace the entire file with:

```ruby
# frozen_string_literal: true

module ScanSerialisable
  private

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
end
```

- [ ] **Step 5: Update `app/controllers/api/v1/scan/orders_controller.rb`**

Replace the entire file with:

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Scan
      class OrdersController < ActionController::API
        include Authenticatable
        include ScanSerialisable

        before_action :authenticate_user!
        before_action { require_permission!(:can_check_in_attendees) }
        before_action :set_order
        before_action :prevent_self_checkin!, only: :update

        def show
          render json: serialise_order(@order)
        end

        def update
          update_params = params.permit(attendees: %i[id checked_in payment_status])

          if update_params[:attendees].blank?
            return render json: { error: 'Nothing to update' }, status: :unprocessable_content
          end

          update_attendee_checkins(update_params)
          render json: serialise_order(@order)
        end

        private

          def set_order
            @order = Order.find_by(order_reference: params[:order_reference])
            render json: { error: I18n.t('errors.not_found') }, status: :not_found unless @order
          end

          def prevent_self_checkin!
            return unless current_user.attendees.exists?(order: @order)

            render json: { error: I18n.t('auth.errors.forbidden') }, status: :forbidden
          end

          def update_attendee_checkins(update_params)
            order_attendees = @order.attendees.index_by(&:id)
            Array(update_params[:attendees]).each do |entry|
              attendee = order_attendees[entry[:id].to_i]
              next unless attendee

              attrs = {}

              if entry.key?(:checked_in)
                if ActiveModel::Type::Boolean.new.cast(entry[:checked_in])
                  attrs.merge!(checked_in: true, checked_in_at: Time.current,
                               checked_in_by_user_id: current_user.id)
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
      end
    end
  end
end
```

- [ ] **Step 6: Update `app/controllers/api/v1/scan/search_controller.rb`**

Replace the `'Not found'` string literal for event not found with `I18n.t('errors.not_found')`. Find:

```ruby
            return render json: { error: 'Not found' }, status: :not_found unless @event
```

Replace with:

```ruby
            return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless @event
```

- [ ] **Step 7: Update `app/controllers/api/v1/auth/me/bookings_controller.rb`**

Three changes in this file:

**Change 1** — `orders_for_user_scoped_to`: add `.where.not(payment_status: :attendee_cancelled)` to exclude cancelled attendees. Find:

```ruby
              Attendee.joins(:event)
                      .where(user_id: current_user.id)
                      .where(where_clause, Time.current)
```

Replace with:

```ruby
              Attendee.joins(:event)
                      .where(user_id: current_user.id)
                      .where.not(payment_status: :attendee_cancelled)
                      .where(where_clause, Time.current)
```

**Change 2** — `check` action: revert to attendee-level filter (remove the `.merge(Order.where(...))` introduced during the earlier order-level migration). Find:

```ruby
              .merge(Order.where(payment_status: %i[paid payment_pending]))
```

Replace with:

```ruby
              .where(payment_status: %i[paid payment_pending])
```

**Change 3** — `serialise_order`: pass loaded attendees to `order.payment_status`. Find:

```ruby
                payment_status: order.payment_status,
```

Replace with:

```ruby
                payment_status: order.payment_status(attendees),
```

- [ ] **Step 8: Update `app/services/sendgrid_service.rb`**

In `send_booking_confirmation`, load ALL attendees (not just those with emails) first, then filter for email recipients, and pass all_attendees when checking `payment_pending?`.

Replace the current `send_booking_confirmation` method body (from `return unless emails_enabled?` through the `rescue`) with:

```ruby
  def self.send_booking_confirmation(order:, language:) # rubocop:disable Metrics/CyclomaticComplexity
    return unless emails_enabled?

    all_attendees = order.attendees
                         .includes({ ticket: :tickets_translations }, { event: :events_translations })
                         .to_a

    attendees_with_email = all_attendees.reject { |a| a.email_address.blank? }
    return if attendees_with_email.empty?

    qr     = RQRCode::QRCode.new(order.order_reference)
    png    = qr.as_png(size: 300, border_modules: 4)
    qr_b64 = Base64.strict_encode64(png.to_s)

    from_email = Rails.application.credentials.dig(:sendgrid, :from_email) || 'noreply@example.com'
    client     = SendGrid::API.new(api_key: Rails.application.credentials.dig(:sendgrid, :api_key))

    attendees_with_email.group_by(&:email_address).each do |email_address, group|
      send_confirmation_to(
        email_address: email_address,
        group: group,
        order: order,
        all_attendees: all_attendees,
        language: language.to_s,
        qr_b64: qr_b64,
        from_email: from_email,
        client: client
      )
    end
  rescue StandardError => e
    Rails.logger.error("SendGrid booking confirmation error: #{e.message}")
  end
```

Also update the `send_confirmation_to` private method signature to add `all_attendees:` and use `order.payment_pending?(all_attendees)`. Find:

```ruby
      def send_confirmation_to(email_address:, group:, order:, language:, qr_b64:, from_email:, client:) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
```

Replace with:

```ruby
      def send_confirmation_to(email_address:, group:, order:, language:, qr_b64:, from_email:, client:, all_attendees:) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
```

And find:

```ruby
          'is_pending' => order.payment_pending?,
```

Replace with:

```ruby
          'is_pending' => order.payment_pending?(all_attendees),
```

- [ ] **Step 9: Update `spec/factories/orders.rb`**

Remove the `payment_status` default. Replace the entire file with:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :order do
    sequence(:order_reference) { |n| "CT-#{Time.zone.now.year}-#{n.to_s.rjust(5, '0')}" }
  end
end
```

Wait — in a previous task the sequence was removed and the model's `after_create` callback generates order_reference. Check the current factory file and remove only `payment_status { :payment_pending }`. The factory should not have a sequence if the model generates the reference. The current factory is:

```ruby
FactoryBot.define do
  factory :order do
    payment_status { :payment_pending }
    sequence(:order_reference) { |n| "CT-#{Time.zone.now.year}-#{n.to_s.rjust(5, '0')}" }
  end
end
```

Based on a previous task, `sequence(:order_reference)` was already removed. Check the current file and remove only the `payment_status` line. The file should become:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :order do
  end
end
```

- [ ] **Step 10: Update `spec/requests/api/v1/scan/orders_spec.rb`**

Replace the entire file with the version below. Key changes:
- Order created without `payment_status`; attendees now carry `payment_status: :paid`
- GET spec: `payment_status` added to attendee fields assertion
- PATCH spec: order-level payment_status tests removed; per-attendee tests added; auth/404 test bodies updated; self-checkin prevention test updated

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Scan Orders API' do
  let(:admin)          { create(:user, role: 'admin') }
  let(:volunteer)      { create(:user, role: 'volunteer') }
  let(:attendee_user)  { create(:user, role: 'attendee') }
  let(:event)          { create(:event) }
  let(:order)          { create(:order) }
  let!(:first_attendee) do
    create(:attendee, event: event, order: order,
                      first_name: 'Ion', last_name: 'Popescu',
                      email_address: 'ion@example.com', payment_status: :paid)
  end
  let!(:second_attendee) do
    create(:attendee, event: event, order: order,
                      first_name: 'Maria', last_name: 'Ionescu',
                      email_address: 'maria@example.com', payment_status: :paid)
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
                                'ticket_name', 'payment_status', 'checked_in', 'checked_in_at', 'checked_in_by')
    end

    it 'returns payment_status for each attendee' do
      get_order(order.order_reference)
      json['attendees'].each do |a|
        expect(a['payment_status']).to be_present
      end
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
        first_attendee.update!(
          checked_in: true,
          checked_in_at: Time.zone.parse('2026-06-01 10:00:00'),
          checked_in_by_user_id: admin.id
        )
      end

      it 'returns checked_in: true with timestamp and checker name' do
        get_order(order.order_reference)
        a = json['attendees'].find { |x| x['id'] == first_attendee.id }
        expect(a['checked_in']).to be true
        expect(a['checked_in_at']).to be_present
        expect(a['checked_in_by']).to eq("#{admin.first_name} #{admin.last_name}".strip)
      end
    end

    context 'when an attendee has a ticket with a ro-RO translation' do
      before do
        Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }
        ticket = create(:ticket, event: event, price: 100)
        create(:tickets_translation, tickets_id: ticket.id, languages_code: 'ro-RO', name: 'General')
        first_attendee.update!(ticket: ticket)
      end

      it 'includes the ticket name from the ro-RO translation' do
        get_order(order.order_reference)
        a = json['attendees'].find { |x| x['id'] == first_attendee.id }
        expect(a['ticket_name']).to eq('General')
      end
    end

    context 'when an attendee has no ticket' do
      it 'returns ticket_name: nil' do
        get_order(order.order_reference)
        a = json['attendees'].find { |x| x['id'] == first_attendee.id }
        expect(a['ticket_name']).to be_nil
      end
    end

    describe 'self-check-in prevention' do
      context 'when the current user is an attendee in the order' do
        before { create(:attendee, event: event, order: order, user: admin) }

        it 'still returns 200 for GET' do
          get_order(order.order_reference)
          expect(response).to have_http_status(:ok)
        end
      end
    end
  end

  describe 'PATCH /api/v1/scan/orders/:order_reference' do
    def patch_order(ref, body, user: admin)
      patch "/api/v1/scan/orders/#{ref}",
            params: body.to_json,
            headers: auth_header(user)
    end

    it 'returns 401 without a token' do
      patch "/api/v1/scan/orders/#{order.order_reference}",
            params: { attendees: [{ id: first_attendee.id, checked_in: true }] }.to_json,
            headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 for attendee role' do
      patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: true }] },
                  user: attendee_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 404 for unknown order reference' do
      patch_order('CT-2026-99999', { attendees: [{ id: 1, checked_in: true }] })
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 422 when body has no updateable fields' do
      patch_order(order.order_reference, {})
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('Nothing to update')
    end

    it 'returns the same shape as GET on success' do
      patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: true }] })
      expect(json.keys).to include('order_reference', 'payment_status', 'attendees')
    end

    context 'when checking in attendees' do
      it 'checks in a single attendee and records who did it' do
        patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: true }] })
        expect(response).to have_http_status(:ok)
        first_attendee.reload
        expect(first_attendee.checked_in).to be true
        expect(first_attendee.checked_in_at).to be_present
        expect(first_attendee.checked_in_by_user_id).to eq(admin.id)
      end

      it 'checks in multiple attendees in one request' do
        patch_order(order.order_reference, {
                      attendees: [
                        { id: first_attendee.id, checked_in: true },
                        { id: second_attendee.id, checked_in: true }
                      ]
                    })
        expect(response).to have_http_status(:ok)
        expect(first_attendee.reload.checked_in).to be true
        expect(second_attendee.reload.checked_in).to be true
      end

      it 'unchecks in an attendee and clears the tracking fields' do
        first_attendee.update!(checked_in: true, checked_in_at: Time.current,
                               checked_in_by_user_id: admin.id)
        patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: false }] })
        expect(response).to have_http_status(:ok)
        first_attendee.reload
        expect(first_attendee.checked_in).to be false
        expect(first_attendee.checked_in_at).to be_nil
        expect(first_attendee.checked_in_by_user_id).to be_nil
      end

      it 'reflects check-in state in the response' do
        patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: true }] })
        a = json['attendees'].find { |x| x['id'] == first_attendee.id }
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

    context 'when updating attendee payment_status' do
      it 'marks an attendee as paid' do
        first_attendee.update!(payment_status: :payment_pending)
        patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, payment_status: 'paid' }] })
        expect(response).to have_http_status(:ok)
        expect(first_attendee.reload.payment_status).to eq('paid')
        a = json['attendees'].find { |x| x['id'] == first_attendee.id }
        expect(a['payment_status']).to eq('paid')
      end

      it 'marks an attendee as payment_pending' do
        patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, payment_status: 'payment_pending' }] })
        expect(response).to have_http_status(:ok)
        expect(first_attendee.reload.payment_status).to eq('payment_pending')
      end

      it 'silently ignores an invalid payment_status value' do
        patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, payment_status: 'bounced' }] })
        expect(response).to have_http_status(:ok)
        expect(first_attendee.reload.payment_status).to eq('paid')
      end

      it 'can update both checked_in and payment_status in one entry' do
        first_attendee.update!(payment_status: :payment_pending)
        patch_order(order.order_reference, {
                      attendees: [{ id: first_attendee.id, checked_in: true, payment_status: 'paid' }]
                    })
        expect(response).to have_http_status(:ok)
        first_attendee.reload
        expect(first_attendee.checked_in).to be true
        expect(first_attendee.payment_status).to eq('paid')
      end
    end

    context 'when computed order payment_status reflects attendees' do
      it 'returns partial when attendees have mixed statuses' do
        first_attendee.update!(payment_status: :paid)
        second_attendee.update!(payment_status: :payment_pending)
        patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: true }] })
        expect(json['payment_status']).to eq('partial')
      end
    end

    describe 'self-check-in prevention' do
      context 'when the current user is an attendee in the order' do
        before { create(:attendee, event: event, order: order, user: admin) }

        it 'returns 403 when trying to check in attendees' do
          patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: true }] })
          expect(response).to have_http_status(:forbidden)
        end

        it 'returns 403 when trying to update attendee payment status' do
          patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, payment_status: 'paid' }] })
          expect(response).to have_http_status(:forbidden)
        end
      end
    end
  end
end
```

- [ ] **Step 11: Update `spec/requests/api/v1/auth/me/bookings_spec.rb`**

**Change 1** — `create_booking` helper: move `payment_status` from order back to attendee. Find:

```ruby
    order = create(:order, payment_status: payment_status)
```

Replace with:

```ruby
    order = create(:order)
```

And find:

```ruby
    attendee = create(:attendee, event: event, order: order, user: user, ticket: ticket)
```

Replace with:

```ruby
    attendee = create(:attendee, event: event, order: order, user: user,
                                 payment_status: payment_status, ticket: ticket)
```

**Change 2** — `check` action context "with a paid booking": move `payment_status` from order to attendee. Find:

```ruby
    context 'with a paid booking' do
      before do
        order = create(:order, payment_status: :paid)
        create(:attendee, event: event_a, order: order, user: user)
      end
```

Replace with:

```ruby
    context 'with a paid booking' do
      before do
        order = create(:order)
        create(:attendee, event: event_a, order: order, user: user, payment_status: :paid)
      end
```

**Change 3** — "with a payment_pending booking". Find:

```ruby
    context 'with a payment_pending booking' do
      before do
        order = create(:order, payment_status: :payment_pending)
        create(:attendee, event: event_a, order: order, user: user)
      end
```

Replace with:

```ruby
    context 'with a payment_pending booking' do
      before do
        order = create(:order)
        create(:attendee, event: event_a, order: order, user: user, payment_status: :payment_pending)
      end
```

**Change 4** — "with a refunded booking". Find:

```ruby
    context 'with a refunded booking' do
      before do
        order = create(:order, payment_status: :refunded)
        create(:attendee, event: event_a, order: order, user: user)
      end
```

Replace with:

```ruby
    context 'with a refunded booking' do
      before do
        order = create(:order)
        create(:attendee, event: event_a, order: order, user: user, payment_status: :refunded)
      end
```

**Change 5** — "with multiple slugs". Find:

```ruby
    context 'with multiple slugs' do
      before do
        order = create(:order, payment_status: :paid)
        create(:attendee, event: event_a, order: order, user: user)
      end
```

Replace with:

```ruby
    context 'with multiple slugs' do
      before do
        order = create(:order)
        create(:attendee, event: event_a, order: order, user: user, payment_status: :paid)
      end
```

- [ ] **Step 12: Update `spec/services/sendgrid_service_spec.rb`**

Find the "sets is_pending: false when payment is paid" example and move `payment_status` from the order to the attendee. Find:

```ruby
        paid_order = create(:order, payment_status: :paid)
        create(:attendee, event: event, order: paid_order, ticket: ticket,
                          email_address: 'paid@example.com')
```

Replace with:

```ruby
        paid_order = create(:order)
        create(:attendee, event: event, order: paid_order, ticket: ticket,
                          email_address: 'paid@example.com', payment_status: :paid)
```

- [ ] **Step 13: Run the migration**

```bash
bin/rails db:migrate
```

Expected: migration runs without errors.

- [ ] **Step 14: Run the full test suite**

```bash
bundle exec rspec
```

Expected: all examples pass. If failures occur, check that every `create(:order, payment_status: ...)` in specs has been updated to use attendee-level payment_status.

- [ ] **Step 15: Run RuboCop**

```bash
bin/rubocop
```

Expected: no offenses.

- [ ] **Step 16: Commit**

```bash
git add db/migrate app/models/attendee.rb app/models/order.rb \
  app/controllers/concerns/scan_serialisable.rb \
  app/controllers/api/v1/scan/orders_controller.rb \
  app/controllers/api/v1/scan/search_controller.rb \
  app/controllers/api/v1/auth/me/bookings_controller.rb \
  app/services/sendgrid_service.rb \
  spec/factories/orders.rb \
  spec/requests/api/v1/scan/orders_spec.rb \
  spec/requests/api/v1/auth/me/bookings_spec.rb \
  spec/services/sendgrid_service_spec.rb \
  db/schema.rb
git commit -m "Revert payment_status to attendees, add attendee_cancelled, update all consumers"
```

---

## Task 2: Add booking cancellation endpoints (TDD)

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/api/v1/auth/me/bookings_controller.rb`
- Modify: `spec/requests/api/v1/auth/me/bookings_spec.rb`

- [ ] **Step 1: Add routes to `config/routes.rb`**

Inside `scope '/me/bookings'`, add two DELETE routes:

```ruby
      scope '/me/bookings' do
        get  :upcoming, to: 'me/bookings#upcoming'
        get  :past,     to: 'me/bookings#past'
        post :check,    to: 'me/bookings#check'
        delete ':order_reference',                to: 'me/bookings#cancel_order',    as: 'cancel_booking'
        delete ':order_reference/attendees/:id',  to: 'me/bookings#cancel_attendee', as: 'cancel_booking_attendee'
      end
```

- [ ] **Step 2: Add failing tests to `spec/requests/api/v1/auth/me/bookings_spec.rb`**

Add the following two describe blocks at the bottom of the file (before the final `end`):

```ruby
  describe 'DELETE /api/v1/auth/me/bookings/:order_reference' do
    let(:event) { create(:event, start_date: 10.days.from_now, end_date: 13.days.from_now) }
    let!(:order) { create(:order) }
    let!(:attendee) do
      create(:attendee, event: event, order: order, user: user, payment_status: :payment_pending)
    end

    it 'returns 401 without a token' do
      delete "/api/v1/auth/me/bookings/#{order.order_reference}"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 404 for unknown order reference' do
      delete '/api/v1/auth/me/bookings/CT-2026-99999', headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 when the user has no attendees in the order' do
      other_order = create(:order)
      other_user = create(:user, first_name: 'Other', email: 'other@example.com')
      create(:attendee, event: event, order: other_order, user: other_user)
      delete "/api/v1/auth/me/bookings/#{other_order.order_reference}", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 422 when all user attendees are already paid' do
      attendee.update!(payment_status: :paid)
      delete "/api/v1/auth/me/bookings/#{order.order_reference}", headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('bookings.errors.nothing_to_cancel'))
    end

    it 'returns 422 when all user attendees are already cancelled' do
      attendee.update!(payment_status: :attendee_cancelled)
      delete "/api/v1/auth/me/bookings/#{order.order_reference}", headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'cancels all payment_pending attendees and returns the updated booking' do
      delete "/api/v1/auth/me/bookings/#{order.order_reference}", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(attendee.reload.payment_status).to eq('attendee_cancelled')
      expect(json['order_reference']).to eq(order.order_reference)
      expect(json['payment_status']).to eq('attendee_cancelled')
    end

    it 'does not cancel attendees belonging to other users in the same order' do
      other_user = create(:user, first_name: 'Other', email: 'other2@example.com')
      other_attendee = create(:attendee, event: event, order: order, user: other_user,
                                         payment_status: :payment_pending)
      delete "/api/v1/auth/me/bookings/#{order.order_reference}", headers: auth_headers
      expect(other_attendee.reload.payment_status).to eq('payment_pending')
    end

    it 'does not cancel paid attendees belonging to the current user' do
      paid_attendee = create(:attendee, event: event, order: order, user: user,
                                        payment_status: :paid)
      delete "/api/v1/auth/me/bookings/#{order.order_reference}", headers: auth_headers
      expect(paid_attendee.reload.payment_status).to eq('paid')
    end
  end

  describe 'DELETE /api/v1/auth/me/bookings/:order_reference/attendees/:id' do
    let(:event) { create(:event, start_date: 10.days.from_now, end_date: 13.days.from_now) }
    let!(:order) { create(:order) }
    let!(:attendee) do
      create(:attendee, event: event, order: order, user: user, payment_status: :payment_pending)
    end
    let!(:other_attendee) do
      create(:attendee, event: event, order: order, user: user, payment_status: :payment_pending)
    end

    it 'returns 401 without a token' do
      delete "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{attendee.id}"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 404 for unknown order reference' do
      delete "/api/v1/auth/me/bookings/CT-2026-99999/attendees/#{attendee.id}", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 when attendee belongs to another user' do
      other_user = create(:user, first_name: 'Other', email: 'other3@example.com')
      other_attendee_record = create(:attendee, event: event, order: order, user: other_user)
      delete "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{other_attendee_record.id}",
             headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 422 when attendee is already paid' do
      attendee.update!(payment_status: :paid)
      delete "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{attendee.id}",
             headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('bookings.errors.cannot_cancel'))
    end

    it 'returns 422 when attendee is already cancelled' do
      attendee.update!(payment_status: :attendee_cancelled)
      delete "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{attendee.id}",
             headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'cancels the specific attendee and returns the updated booking' do
      delete "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{attendee.id}",
             headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(attendee.reload.payment_status).to eq('attendee_cancelled')
      expect(json['order_reference']).to eq(order.order_reference)
    end

    it 'does not affect other attendees in the same order' do
      delete "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{attendee.id}",
             headers: auth_headers
      expect(other_attendee.reload.payment_status).to eq('payment_pending')
    end
  end
```

- [ ] **Step 3: Run the new tests to confirm they fail**

```bash
bundle exec rspec spec/requests/api/v1/auth/me/bookings_spec.rb -e 'DELETE'
```

Expected: routing errors or action-not-found failures.

- [ ] **Step 4: Add `cancel_order` and `cancel_attendee` actions to `app/controllers/api/v1/auth/me/bookings_controller.rb`**

Add the following two public actions before the `private` keyword:

```ruby
        def cancel_order
          order = Order.find_by(order_reference: params[:order_reference])
          return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless order

          user_attendees = order.attendees.where(user_id: current_user.id)
          return render json: { error: I18n.t('errors.not_found') }, status: :not_found if user_attendees.empty?

          cancellable = user_attendees.where(payment_status: :payment_pending)
          if cancellable.empty?
            return render json: { error: I18n.t('bookings.errors.nothing_to_cancel') },
                          status: :unprocessable_content
          end

          # rubocop:disable Rails/SkipsModelValidations
          cancellable.update_all(payment_status: Attendee.payment_statuses['attendee_cancelled'])
          # rubocop:enable Rails/SkipsModelValidations

          lang = current_user.language || 'ro-RO'
          attendees = order.attendees
                           .includes({ ticket: :tickets_translations }, { event: :events_translations })
                           .where(user_id: current_user.id)
                           .to_a
          render json: serialise_order(order, attendees)
        end

        def cancel_attendee
          order = Order.find_by(order_reference: params[:order_reference])
          return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless order

          attendee = order.attendees.find_by(id: params[:id], user_id: current_user.id)
          return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless attendee

          unless attendee.payment_pending?
            return render json: { error: I18n.t('bookings.errors.cannot_cancel') },
                          status: :unprocessable_content
          end

          attendee.update!(payment_status: :attendee_cancelled)

          attendees = order.attendees
                           .includes({ ticket: :tickets_translations }, { event: :events_translations })
                           .where(user_id: current_user.id)
                           .to_a
          render json: serialise_order(order, attendees)
        end
```

Note: the unused `lang` variable in `cancel_order` should be removed — `serialise_order` uses `current_user.language` internally. The `lang` line is not needed. Only the `attendees` load and `render json: serialise_order(order, attendees)` are needed.

- [ ] **Step 5: Run the cancellation specs**

```bash
bundle exec rspec spec/requests/api/v1/auth/me/bookings_spec.rb -e 'DELETE'
```

Expected: all examples pass.

- [ ] **Step 6: Run the full test suite**

```bash
bundle exec rspec
```

Expected: all examples pass.

- [ ] **Step 7: Run RuboCop**

```bash
bin/rubocop app/controllers/api/v1/auth/me/bookings_controller.rb config/routes.rb
```

Expected: no offenses.

- [ ] **Step 8: Commit**

```bash
git add config/routes.rb \
        app/controllers/api/v1/auth/me/bookings_controller.rb \
        spec/requests/api/v1/auth/me/bookings_spec.rb
git commit -m "Add booking cancellation endpoints for users"
```
