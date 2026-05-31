# Scan: Self-Check-in Guard & Events List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a self-check-in guard to the PATCH scan order endpoint, and add a new `GET /api/v1/scan/events` endpoint that returns upcoming live events for the scan FE.

**Architecture:** Task 1 adds a single `before_action` to `OrdersController`. Task 2 adds a new route and `EventsController` inside the existing `scan` namespace; event name is resolved inline from `current_user.language` with a `ro-RO` fallback using the already-included `events_translations` association.

**Tech Stack:** Rails 8.1, RSpec, FactoryBot

---

## File Map

| Action | File | Purpose |
|--------|------|---------|
| Modify | `app/controllers/api/v1/scan/orders_controller.rb` | Add `prevent_self_checkin!` before_action and private method |
| Modify | `spec/requests/api/v1/scan/orders_spec.rb` | Add self-check-in guard test cases |
| Modify | `config/routes.rb` | Add `get 'events'` inside `namespace :scan` |
| Create | `app/controllers/api/v1/scan/events_controller.rb` | New controller with `index` action |
| Create | `spec/requests/api/v1/scan/events_spec.rb` | New spec |

---

## Task 1: Self-check-in guard on PATCH scan order

**Files:**
- Modify: `app/controllers/api/v1/scan/orders_controller.rb`
- Modify: `spec/requests/api/v1/scan/orders_spec.rb`

- [ ] **Step 1: Add failing tests to `spec/requests/api/v1/scan/orders_spec.rb`**

Inside the existing `describe 'PATCH /api/v1/scan/orders/:order_reference'` block, add a new context before the closing `end`:

```ruby
    describe 'self-check-in prevention' do
      context 'when the current user is an attendee in the order' do
        before { create(:attendee, event: event, order: order, user: admin) }

        it 'returns 403 when trying to check in attendees' do
          patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: true }] })
          expect(response).to have_http_status(:forbidden)
        end

        it 'returns 403 when trying to change payment status' do
          patch_order(order.order_reference, { payment_status: 'paid' })
          expect(response).to have_http_status(:forbidden)
        end
      end
    end
```

Also add inside the existing `describe 'GET /api/v1/scan/orders/:order_reference'` block:

```ruby
    describe 'self-check-in prevention' do
      context 'when the current user is an attendee in the order' do
        before { create(:attendee, event: event, order: order, user: admin) }

        it 'still returns 200 for GET' do
          get_order(order.order_reference)
          expect(response).to have_http_status(:ok)
        end
      end
    end
```

- [ ] **Step 2: Run the new tests to verify they fail**

```bash
bundle exec rspec spec/requests/api/v1/scan/orders_spec.rb -e 'self-check-in'
```

Expected: the two PATCH tests fail (403 not returned), the GET test passes (200 already works).

- [ ] **Step 3: Implement the guard in `app/controllers/api/v1/scan/orders_controller.rb`**

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

          def prevent_self_checkin!
            return unless current_user.attendees.exists?(order: @order)

            render json: { error: I18n.t('auth.errors.forbidden') }, status: :forbidden
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

- [ ] **Step 4: Run all scan order specs**

```bash
bundle exec rspec spec/requests/api/v1/scan/orders_spec.rb
```

Expected: all examples pass.

- [ ] **Step 5: Run RuboCop**

```bash
bin/rubocop app/controllers/api/v1/scan/orders_controller.rb
```

Expected: no offenses.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/api/v1/scan/orders_controller.rb \
        spec/requests/api/v1/scan/orders_spec.rb
git commit -m "Prevent self-check-in on PATCH scan order endpoint"
```

---

## Task 2: Scan events list endpoint

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/api/v1/scan/events_controller.rb`
- Create: `spec/requests/api/v1/scan/events_spec.rb`

- [ ] **Step 1: Add route to `config/routes.rb`**

Inside `namespace :scan`, add `get 'events'` before the search route:

```ruby
      namespace :scan do
        get 'events', to: 'events#index'
        get 'search', to: 'search#index'
        scope '/orders/:order_reference' do
          get  '/', to: 'orders#show',   as: 'scan_order'
          patch '/', to: 'orders#update', as: 'scan_order_update'
        end
      end
```

- [ ] **Step 2: Verify route is registered**

```bash
bin/rails routes | grep 'scan/events'
```

Expected: `GET /api/v1/scan/events(.:format) api/v1/scan/events#index`

- [ ] **Step 3: Create `app/controllers/api/v1/scan/events_controller.rb` with a stub index action**

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Scan
      class EventsController < ActionController::API
        include Authenticatable

        before_action :authenticate_user!
        before_action { require_permission!(:can_check_in_attendees) }

        def index; end
      end
    end
  end
end
```

- [ ] **Step 4: Create `spec/requests/api/v1/scan/events_spec.rb`**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/scan/events' do
  let(:admin)         { create(:user, role: 'admin', language: 'ro-RO') }
  let(:attendee_user) { create(:user, role: 'attendee') }

  def auth_header(user)
    { 'Authorization' => "Bearer #{JwtService.encode(user.id)}", 'Content-Type' => 'application/json' }
  end

  before do
    Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }
    Language.find_or_create_by!(code: 'en-US') { |l| l.name = 'English' }
  end

  describe 'authentication and authorisation' do
    it 'returns 401 without a token' do
      get '/api/v1/scan/events'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 for attendee role' do
      get '/api/v1/scan/events', headers: auth_header(attendee_user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'filtering and sorting' do
    let!(:upcoming_event) do
      create(:event, status: :live, start_date: 7.days.from_now, end_date: 9.days.from_now)
    end
    let!(:further_event) do
      create(:event, status: :live, start_date: 30.days.from_now, end_date: 32.days.from_now)
    end
    let!(:past_event) do
      create(:event, status: :live, start_date: 7.days.ago, end_date: 5.days.ago)
    end
    let!(:draft_event) do
      create(:event, status: :draft, start_date: 3.days.from_now, end_date: 5.days.from_now)
    end

    before do
      create(:events_translation, event: upcoming_event, languages_code: 'ro-RO', name: 'Conferința 2026')
      create(:events_translation, event: further_event,  languages_code: 'ro-RO', name: 'Tabăra 2026')
    end

    it 'returns only live future events' do
      get '/api/v1/scan/events', headers: auth_header(admin)
      expect(response).to have_http_status(:ok)
      slugs = json.pluck('slug')
      expect(slugs).to include(upcoming_event.slug, further_event.slug)
      expect(slugs).not_to include(past_event.slug, draft_event.slug)
    end

    it 'returns name and slug only' do
      get '/api/v1/scan/events', headers: auth_header(admin)
      event_json = json.find { |e| e['slug'] == upcoming_event.slug }
      expect(event_json.keys).to contain_exactly('name', 'slug')
      expect(event_json['name']).to eq('Conferința 2026')
    end

    it 'sorts by start_date ascending (soonest first)' do
      get '/api/v1/scan/events', headers: auth_header(admin)
      slugs = json.pluck('slug')
      expect(slugs.index(upcoming_event.slug)).to be < slugs.index(further_event.slug)
    end
  end

  describe 'empty result' do
    it 'returns empty array when no upcoming live events exist' do
      get '/api/v1/scan/events', headers: auth_header(admin)
      expect(response).to have_http_status(:ok)
      expect(json).to eq([])
    end
  end

  describe 'translation resolution' do
    let!(:event) do
      create(:event, status: :live, start_date: 7.days.from_now, end_date: 9.days.from_now)
    end

    before do
      create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Conferința RO')
    end

    it 'returns name in the user language when translation exists' do
      en_user = create(:user, role: 'admin', language: 'en-US')
      create(:events_translation, event: event, languages_code: 'en-US', name: 'Conference EN')
      get '/api/v1/scan/events', headers: auth_header(en_user)
      expect(json.first['name']).to eq('Conference EN')
    end

    it 'falls back to ro-RO when user language translation is absent' do
      en_user = create(:user, role: 'admin', language: 'en-US')
      get '/api/v1/scan/events', headers: auth_header(en_user)
      expect(json.first['name']).to eq('Conferința RO')
    end
  end
end
```

- [ ] **Step 5: Run the spec to confirm it fails**

```bash
bundle exec rspec spec/requests/api/v1/scan/events_spec.rb
```

Expected: auth tests pass (401/403 work), all other tests fail because `index` returns nil.

- [ ] **Step 6: Implement `app/controllers/api/v1/scan/events_controller.rb`**

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Scan
      class EventsController < ActionController::API
        include Authenticatable

        before_action :authenticate_user!
        before_action { require_permission!(:can_check_in_attendees) }

        def index
          lang   = current_user.language || 'ro-RO'
          events = Event.upcoming.order(:start_date).includes(:events_translations)
          render json: events.map { |e| serialise_event(e, lang) }
        end

        private

          def serialise_event(event, lang)
            translation = event.events_translations.find { |t| t.languages_code == lang } ||
                          event.events_translations.find { |t| t.languages_code == 'ro-RO' } ||
                          event.events_translations.first
            {
              name: translation&.name,
              slug: event.slug
            }
          end
      end
    end
  end
end
```

Note: `Event.upcoming` is already defined as `where(start_date: Time.zone.now..).where(status: 'live')` — no need to duplicate the scope.

- [ ] **Step 7: Run the events spec**

```bash
bundle exec rspec spec/requests/api/v1/scan/events_spec.rb
```

Expected: all examples pass.

- [ ] **Step 8: Run the full test suite**

```bash
bundle exec rspec
```

Expected: all examples pass, no regressions.

- [ ] **Step 9: Run RuboCop**

```bash
bin/rubocop app/controllers/api/v1/scan/events_controller.rb \
            spec/requests/api/v1/scan/events_spec.rb
```

Expected: no offenses. Fix any before committing.

- [ ] **Step 10: Commit**

```bash
git add config/routes.rb \
        app/controllers/api/v1/scan/events_controller.rb \
        spec/requests/api/v1/scan/events_spec.rb
git commit -m "Add GET /api/v1/scan/events for scan FE event picker"
```
