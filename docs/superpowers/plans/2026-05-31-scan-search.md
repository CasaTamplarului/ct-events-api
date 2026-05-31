# Scan Search Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `GET /api/v1/scan/search` that lets staff find orders by partial order reference, attendee name, email, or phone number, returning a list of matching orders in the same shape as the existing scan endpoint.

**Architecture:** Extract the shared order/attendee serialisation logic from `OrdersController` into a `ScanSerialisable` concern, then build `SearchController` (one `index` action, four private query methods) that includes it. The route lives inside the existing `namespace :scan` block.

**Tech Stack:** Rails 8.1, PostgreSQL ILIKE, RSpec, FactoryBot

---

## File Map

| Action | File | Purpose |
|--------|------|---------|
| Create | `app/controllers/concerns/scan_serialisable.rb` | Shared `serialise_order(order)` and `serialise_attendee(attendee)` |
| Modify | `app/controllers/api/v1/scan/orders_controller.rb` | Include `ScanSerialisable`; remove private serialise methods; update calls to pass `@order` |
| Modify | `config/routes.rb` | Add `get 'search', to: 'search#index'` inside `namespace :scan` |
| Create | `app/controllers/api/v1/scan/search_controller.rb` | `index` action + four query methods |
| Create | `spec/requests/api/v1/scan/search_spec.rb` | Request specs for all search cases |

---

## Task 1: Extract ScanSerialisable concern

Pull `serialise_order` and `serialise_attendee` out of `OrdersController` into a shared concern so `SearchController` can reuse them without duplication. The concern is named `ScanSerialisable` (not `Scan::Serialisable`) to avoid a Ruby constant lookup collision with the `Api::V1::Scan` module namespace.

**Files:**
- Create: `app/controllers/concerns/scan_serialisable.rb`
- Modify: `app/controllers/api/v1/scan/orders_controller.rb`

- [ ] **Step 1: Create `app/controllers/concerns/scan_serialisable.rb`**

```ruby
# frozen_string_literal: true

module ScanSerialisable
  private

    def serialise_order(order)
      attendees = order.attendees
                       .includes(:checked_in_by, ticket: :tickets_translations)
                       .order(:id)
      {
        order_reference: order.order_reference,
        payment_status: order.payment_status,
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
```

- [ ] **Step 2: Update `app/controllers/api/v1/scan/orders_controller.rb`**

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

        def show
          render json: serialise_order(@order)
        end

        def update
          update_params = params.permit(:payment_status, attendees: %i[id checked_in])

          if update_params[:payment_status].blank? && update_params[:attendees].blank?
            return render json: { error: 'Nothing to update' }, status: :unprocessable_content
          end

          if update_params[:payment_status].present? &&
             !Order.payment_statuses.key?(update_params[:payment_status].to_s)
            return render json: { error: "Invalid payment_status: #{update_params[:payment_status]}" },
                          status: :unprocessable_content
          end

          ActiveRecord::Base.transaction do
            @order.update!(payment_status: update_params[:payment_status]) if update_params[:payment_status].present?
            update_attendee_checkins(update_params)
          end

          render json: serialise_order(@order)
        end

        private

          def set_order
            @order = Order.find_by(order_reference: params[:order_reference])
            render json: { error: 'Not found' }, status: :not_found unless @order
          end

          def update_attendee_checkins(update_params)
            return if update_params[:attendees].blank?

            order_attendees = @order.attendees.index_by(&:id)
            Array(update_params[:attendees]).each do |entry|
              attendee = order_attendees[entry[:id].to_i]
              next unless attendee

              if ActiveModel::Type::Boolean.new.cast(entry[:checked_in])
                attendee.update!(checked_in: true, checked_in_at: Time.current,
                                 checked_in_by_user_id: current_user.id)
              else
                attendee.update!(checked_in: false, checked_in_at: nil, checked_in_by_user_id: nil)
              end
            end
          end
      end
    end
  end
end
```

The only changes from the previous version: `include ScanSerialisable` added, `serialise_order` and `serialise_attendee` private methods removed, and both calls to `serialise_order` now pass `@order` as an argument.

- [ ] **Step 3: Run the existing scan specs to confirm nothing broke**

```bash
bundle exec rspec spec/requests/api/v1/scan/orders_spec.rb
```

Expected: 25 examples, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add app/controllers/concerns/scan_serialisable.rb \
        app/controllers/api/v1/scan/orders_controller.rb
git commit -m "Extract ScanSerialisable concern from OrdersController"
```

---

## Task 2: Add search route and SearchController scaffold

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/api/v1/scan/search_controller.rb`

- [ ] **Step 1: Add search route to `config/routes.rb`**

Inside the `namespace :scan` block, add the search route before the orders scope:

```ruby
      namespace :scan do
        get 'search', to: 'search#index'
        scope '/orders/:order_reference' do
          get  '/', to: 'orders#show',   as: 'scan_order'
          patch '/', to: 'orders#update', as: 'scan_order_update'
        end
      end
```

- [ ] **Step 2: Verify the route is registered**

```bash
bin/rails routes | grep scan
```

Expected output includes:

```
GET /api/v1/scan/search(.:format)  api/v1/scan/search#index
```

- [ ] **Step 3: Create `app/controllers/api/v1/scan/search_controller.rb`**

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Scan
      class SearchController < ActionController::API
        include Authenticatable
        include ScanSerialisable

        VALID_TYPES = %w[order_ref name email phone].freeze
        REQUIRES_EVENT_SLUG = %w[name email phone].freeze

        before_action :authenticate_user!
        before_action { require_permission!(:can_check_in_attendees) }

        def index
        end
      end
    end
  end
end
```

- [ ] **Step 4: Commit**

```bash
git add config/routes.rb app/controllers/api/v1/scan/search_controller.rb
git commit -m "Add scan search route and SearchController scaffold"
```

---

## Task 3: Implement GET /api/v1/scan/search (TDD)

**Files:**
- Create: `spec/requests/api/v1/scan/search_spec.rb`
- Modify: `app/controllers/api/v1/scan/search_controller.rb`

- [ ] **Step 1: Create `spec/requests/api/v1/scan/search_spec.rb`**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/scan/search' do
  let(:admin)         { create(:user, role: 'admin') }
  let(:volunteer)     { create(:user, role: 'volunteer') }
  let(:attendee_user) { create(:user, role: 'attendee') }
  let(:event)         { create(:event, slug: 'conferinta-2026') }
  let(:other_event)   { create(:event, slug: 'tabara-2026') }
  let(:first_order)   { create(:order, payment_status: :paid) }
  let(:second_order)  { create(:order, payment_status: :payment_pending) }

  let!(:first_attendee) do
    create(:attendee, event: event, order: first_order,
                      first_name: 'Ion', last_name: 'Popescu',
                      email_address: 'ion@example.com', phone_number: '0722111222')
  end
  let!(:second_attendee) do
    create(:attendee, event: event, order: second_order,
                      first_name: 'Maria', last_name: 'Ionescu',
                      email_address: 'maria@example.com', phone_number: '0733444555')
  end
  let!(:other_event_attendee) do
    create(:attendee, event: other_event, order: first_order,
                      first_name: 'Vasile', last_name: 'Popa',
                      email_address: 'vasile@example.com', phone_number: '0744666777')
  end

  def auth_header(user)
    { 'Authorization' => "Bearer #{JwtService.encode(user.id)}", 'Content-Type' => 'application/json' }
  end

  def search(params, user: admin)
    get '/api/v1/scan/search', params: params, headers: auth_header(user)
  end

  context 'authentication and authorisation' do
    it 'returns 401 without a token' do
      get '/api/v1/scan/search', params: { type: 'order_ref', query: 'CT' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 for attendee role' do
      search({ type: 'order_ref', query: 'CT' }, user: attendee_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 200 for volunteer role' do
      search({ type: 'order_ref', query: 'CT' }, user: volunteer)
      expect(response).to have_http_status(:ok)
    end
  end

  context 'param validation' do
    it 'returns 422 when type is missing' do
      search({ query: 'Ion', event_slug: 'conferinta-2026' })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('type and query are required')
    end

    it 'returns 422 when query is missing' do
      search({ type: 'name', event_slug: 'conferinta-2026' })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('type and query are required')
    end

    it 'returns 422 for an invalid type' do
      search({ type: 'fax', query: 'Ion' })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('Invalid type')
    end

    it 'returns 422 when query is shorter than 2 characters' do
      search({ type: 'order_ref', query: 'C' })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('query must be at least 2 characters')
    end

    it 'returns 422 when event_slug is missing for name type' do
      search({ type: 'name', query: 'Ion' })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('event_slug is required for this search type')
    end

    it 'returns 422 when event_slug is missing for email type' do
      search({ type: 'email', query: 'ion@' })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('event_slug is required for this search type')
    end

    it 'returns 422 when event_slug is missing for phone type' do
      search({ type: 'phone', query: '072' })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('event_slug is required for this search type')
    end

    it 'returns 404 when event_slug does not match any event' do
      search({ type: 'name', query: 'Ion', event_slug: 'no-such-event' })
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'order_ref search' do
    it 'returns matching orders for a partial ref' do
      search({ type: 'order_ref', query: first_order.order_reference[0..9] })
      expect(response).to have_http_status(:ok)
      expect(json.pluck('order_reference')).to include(first_order.order_reference)
    end

    it 'returns an empty array when no orders match' do
      search({ type: 'order_ref', query: 'CT-9999' })
      expect(response).to have_http_status(:ok)
      expect(json).to eq([])
    end

    it 'returns orders with attendees in the expected shape' do
      search({ type: 'order_ref', query: first_order.order_reference })
      order_json = json.find { |o| o['order_reference'] == first_order.order_reference }
      expect(order_json.keys).to include('order_reference', 'payment_status', 'attendees')
      expect(order_json['attendees'].first.keys).to include(
        'id', 'first_name', 'last_name', 'email_address',
        'ticket_name', 'checked_in', 'checked_in_at', 'checked_in_by'
      )
    end
  end

  context 'name search' do
    it 'finds by partial first name' do
      search({ type: 'name', query: 'Io', event_slug: 'conferinta-2026' })
      expect(response).to have_http_status(:ok)
      expect(json.pluck('order_reference')).to include(first_order.order_reference)
    end

    it 'finds by partial last name' do
      search({ type: 'name', query: 'Popes', event_slug: 'conferinta-2026' })
      expect(json.pluck('order_reference')).to include(first_order.order_reference)
    end

    it 'finds by full name' do
      search({ type: 'name', query: 'Ion Popescu', event_slug: 'conferinta-2026' })
      expect(json.pluck('order_reference')).to include(first_order.order_reference)
    end

    it 'does not return orders from other events' do
      search({ type: 'name', query: 'Vasile', event_slug: 'conferinta-2026' })
      expect(json).to eq([])
    end

    it 'returns empty array when no name matches' do
      search({ type: 'name', query: 'Gheorghe', event_slug: 'conferinta-2026' })
      expect(json).to eq([])
    end
  end

  context 'email search' do
    it 'finds by partial email' do
      search({ type: 'email', query: 'ion@', event_slug: 'conferinta-2026' })
      expect(response).to have_http_status(:ok)
      expect(json.pluck('order_reference')).to include(first_order.order_reference)
    end

    it 'does not return orders where the matching attendee is in another event' do
      search({ type: 'email', query: 'vasile@', event_slug: 'conferinta-2026' })
      expect(json).to eq([])
    end
  end

  context 'phone search' do
    it 'finds by partial phone number' do
      search({ type: 'phone', query: '07221', event_slug: 'conferinta-2026' })
      expect(response).to have_http_status(:ok)
      expect(json.pluck('order_reference')).to include(first_order.order_reference)
    end

    it 'does not return orders where the matching attendee is in another event' do
      search({ type: 'phone', query: '07446', event_slug: 'conferinta-2026' })
      expect(json).to eq([])
    end
  end

  context 'result cap' do
    it 'returns at most 20 results' do
      21.times do |i|
        o = create(:order)
        create(:attendee, event: event, order: o,
                          first_name: 'TestUser', last_name: "Num#{i}",
                          email_address: "testuser#{i}@example.com",
                          phone_number: "0700#{i.to_s.rjust(6, '0')}")
      end
      search({ type: 'name', query: 'TestUser', event_slug: 'conferinta-2026' })
      expect(response).to have_http_status(:ok)
      expect(json.length).to eq(20)
    end
  end
end
```

- [ ] **Step 2: Run the spec to confirm it fails (index action is a stub)**

```bash
bundle exec rspec spec/requests/api/v1/scan/search_spec.rb
```

Expected: many failures — the index action is empty, so all non-auth examples fail.

- [ ] **Step 3: Implement the full `index` action in `app/controllers/api/v1/scan/search_controller.rb`**

Replace the entire file with:

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Scan
      class SearchController < ActionController::API
        include Authenticatable
        include ScanSerialisable

        VALID_TYPES = %w[order_ref name email phone].freeze
        REQUIRES_EVENT_SLUG = %w[name email phone].freeze

        before_action :authenticate_user!
        before_action { require_permission!(:can_check_in_attendees) }

        def index
          type  = params[:type].to_s
          query = params[:query].to_s

          if type.blank? || query.blank?
            return render json: { error: 'type and query are required' }, status: :unprocessable_content
          end

          unless VALID_TYPES.include?(type)
            return render json: { error: 'Invalid type' }, status: :unprocessable_content
          end

          if query.length < 2
            return render json: { error: 'query must be at least 2 characters' }, status: :unprocessable_content
          end

          if REQUIRES_EVENT_SLUG.include?(type)
            if params[:event_slug].blank?
              return render json: { error: 'event_slug is required for this search type' },
                            status: :unprocessable_content
            end

            @event = Event.find_by(slug: params[:event_slug])
            return render json: { error: 'Not found' }, status: :not_found unless @event
          end

          orders = case type
                   when 'order_ref' then search_by_order_ref(query)
                   when 'name'      then search_by_name(query)
                   when 'email'     then search_by_email(query)
                   when 'phone'     then search_by_phone(query)
                   end

          render json: orders.map { |o| serialise_order(o) }
        end

        private

          def search_by_order_ref(query)
            Order.where('order_reference ILIKE ?', "%#{query}%")
                 .order(:order_reference)
                 .limit(20)
          end

          def search_by_name(query)
            Order.joins(attendees: :event)
                 .where(events: { id: @event.id })
                 .where(
                   'attendees.first_name ILIKE :q OR attendees.last_name ILIKE :q OR ' \
                   "CONCAT(attendees.first_name, ' ', attendees.last_name) ILIKE :q",
                   q: "%#{query}%"
                 )
                 .distinct
                 .order(:order_reference)
                 .limit(20)
          end

          def search_by_email(query)
            Order.joins(attendees: :event)
                 .where(events: { id: @event.id })
                 .where('attendees.email_address ILIKE ?', "%#{query}%")
                 .distinct
                 .order(:order_reference)
                 .limit(20)
          end

          def search_by_phone(query)
            Order.joins(attendees: :event)
                 .where(events: { id: @event.id })
                 .where('attendees.phone_number ILIKE ?', "%#{query}%")
                 .distinct
                 .order(:order_reference)
                 .limit(20)
          end
      end
    end
  end
end
```

- [ ] **Step 4: Run the search specs**

```bash
bundle exec rspec spec/requests/api/v1/scan/search_spec.rb
```

Expected: all examples pass.

- [ ] **Step 5: Run the full test suite**

```bash
bundle exec rspec
```

Expected: all examples pass, no regressions.

- [ ] **Step 6: Run RuboCop**

```bash
bin/rubocop app/controllers/concerns/scan_serialisable.rb \
            app/controllers/api/v1/scan/search_controller.rb \
            spec/requests/api/v1/scan/search_spec.rb
```

Expected: no offenses. Fix any before committing.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/api/v1/scan/search_controller.rb \
        spec/requests/api/v1/scan/search_spec.rb
git commit -m "Implement GET /api/v1/scan/search with order_ref, name, email, phone types"
```
