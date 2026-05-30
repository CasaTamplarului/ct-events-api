# User Bookings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `GET /api/v1/auth/me/bookings/upcoming` and `GET /api/v1/auth/me/bookings/past` so authenticated users can list their own bookings, each containing event details, attendees, payment status, and the order reference (used by the FE to render a QR code).

**Architecture:** A new `Api::V1::Auth::Me::BookingsController` with `upcoming` and `past` actions, nested inside the existing `resource :me` route. Queries join `orders → attendees → events` filtered by `attendee.user_id = current_user.id`. Event/ticket names are fetched from translation tables in the user's language. No new gems, no QR generation — the API returns `order_reference` and the FE renders the QR.

**Tech Stack:** Rails 8.1, PostgreSQL, RSpec.

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `app/controllers/api/v1/auth/me/bookings_controller.rb` | Create | Upcoming + past booking actions with serialisation |
| `config/routes.rb` | Modify | Add `scope '/bookings'` inside `resource :me` |
| `spec/requests/api/v1/auth/me/bookings_spec.rb` | Create | Request tests |

---

### Task 1: BookingsController + routes + request tests + push

**Files:**
- Create: `app/controllers/api/v1/auth/me/bookings_controller.rb`
- Modify: `config/routes.rb`
- Create: `spec/requests/api/v1/auth/me/bookings_spec.rb`

- [ ] **Step 1: Create `spec/requests/api/v1/auth/me/bookings_spec.rb`**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/auth/me/bookings' do
  let(:user)         { create(:user, email: 'ion@example.com', language: 'ro-RO') }
  let(:token)        { JwtService.encode(user.id) }
  let(:auth_headers) { { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{token}" } }

  # Creates a complete booking: event + order + attendee linked to the given user.
  def create_booking(user:, start_date:, end_date:, payment_status: :paid, with_ticket: false)
    event = create(:event, start_date: start_date, end_date: end_date)
    create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Conferința Test')
    order = create(:order)
    ticket = nil
    if with_ticket
      ticket = create(:ticket, event: event)
      create(:tickets_translation, tickets_id: ticket.id, languages_code: 'ro-RO', name: 'Adult')
    end
    attendee = create(:attendee, event: event, order: order, user: user,
                                 payment_status: payment_status, ticket: ticket)
    { event: event, order: order, attendee: attendee }
  end

  # ── GET /api/v1/auth/me/bookings/upcoming ────────────────────────────────────

  describe 'GET /api/v1/auth/me/bookings/upcoming' do
    context 'with a valid JWT' do
      it 'returns 200' do
        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers
        expect(response).to have_http_status(:ok)
      end

      it 'returns empty array when user has no upcoming bookings' do
        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers
        expect(json).to eq([])
      end

      it 'returns upcoming bookings ordered by start_date ASC' do
        create_booking(user: user, start_date: 30.days.from_now, end_date: 33.days.from_now)
        create_booking(user: user, start_date: 10.days.from_now, end_date: 13.days.from_now)

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        start_dates = json.map { |b| b['event']['start_date'] }
        expect(start_dates).to eq(start_dates.sort)
      end

      it 'includes the order_reference' do
        booking = create_booking(user: user, start_date: 10.days.from_now, end_date: 13.days.from_now)

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        expect(json.first['order_reference']).to eq(booking[:order].order_reference)
      end

      it 'includes all three payment statuses' do
        create_booking(user: user, start_date: 10.days.from_now, end_date: 13.days.from_now,
                       payment_status: :paid)
        create_booking(user: user, start_date: 20.days.from_now, end_date: 23.days.from_now,
                       payment_status: :payment_pending)
        create_booking(user: user, start_date: 30.days.from_now, end_date: 33.days.from_now,
                       payment_status: :refunded)

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        statuses = json.map { |b| b['payment_status'] }
        expect(statuses).to contain_exactly('paid', 'payment_pending', 'refunded')
      end

      it 'includes all expected event fields' do # rubocop:disable RSpec/ExampleLength
        event = create(:event,
                       start_date: 10.days.from_now,
                       end_date: 13.days.from_now,
                       slug: 'test-event',
                       location_name: 'Casa Tâmplarului',
                       address: 'Str. Test 1')
        create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Conferința Test')
        order = create(:order)
        create(:attendee, event: event, order: order, user: user)

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        e = json.first['event']
        expect(e['name']).to eq('Conferința Test')
        expect(e['slug']).to eq('test-event')
        expect(e['location_name']).to eq('Casa Tâmplarului')
        expect(e['address']).to eq('Str. Test 1')
        expect(e['start_date']).to be_present
        expect(e['end_date']).to be_present
      end

      it 'returns event name in the user language' do
        user.update!(language: 'en-US')
        event = create(:event, start_date: 10.days.from_now, end_date: 13.days.from_now)
        create(:events_translation, event: event, languages_code: 'en-US', name: 'Test Conference')
        create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Conferința Test')
        order = create(:order)
        create(:attendee, event: event, order: order, user: user)

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        expect(json.first['event']['name']).to eq('Test Conference')
      end

      it 'falls back to ro-RO event name when user language has no translation' do
        user.update!(language: 'en-US')
        event = create(:event, start_date: 10.days.from_now, end_date: 13.days.from_now)
        create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Conferința Test')
        order = create(:order)
        create(:attendee, event: event, order: order, user: user)

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        expect(json.first['event']['name']).to eq('Conferința Test')
      end

      it 'includes attendee fields with ticket_name' do
        booking = create_booking(user: user, start_date: 10.days.from_now,
                                 end_date: 13.days.from_now, with_ticket: true)

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        a = json.first['attendees'].first
        expect(a['first_name']).to eq(booking[:attendee].first_name)
        expect(a['last_name']).to eq(booking[:attendee].last_name)
        expect(a['ticket_name']).to eq('Adult')
        expect(a['dietary_preference']).to eq('no_preference')
      end

      it 'only returns the current user attendees, not other users on the same order' do
        other_user = create(:user, email: 'other@example.com')
        event = create(:event, start_date: 10.days.from_now, end_date: 13.days.from_now)
        order = create(:order)
        create(:attendee, event: event, order: order, user: user,     first_name: 'Ion')
        create(:attendee, event: event, order: order, user: other_user, first_name: 'Maria')

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        expect(json.first['attendees'].length).to eq(1)
        expect(json.first['attendees'].first['first_name']).to eq('Ion')
      end

      it 'does not return past bookings' do
        create_booking(user: user, start_date: 10.days.ago, end_date: 7.days.ago)

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        expect(json).to eq([])
      end
    end

    context 'with no JWT' do
      it 'returns 401' do
        get '/api/v1/auth/me/bookings/upcoming',
            headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # ── GET /api/v1/auth/me/bookings/past ────────────────────────────────────────

  describe 'GET /api/v1/auth/me/bookings/past' do
    context 'with a valid JWT' do
      it 'returns empty array when user has no past bookings' do
        get '/api/v1/auth/me/bookings/past', headers: auth_headers
        expect(json).to eq([])
      end

      it 'returns past bookings ordered by start_date DESC' do
        create_booking(user: user, start_date: 30.days.ago, end_date: 27.days.ago)
        create_booking(user: user, start_date: 10.days.ago, end_date: 7.days.ago)

        get '/api/v1/auth/me/bookings/past', headers: auth_headers

        start_dates = json.map { |b| b['event']['start_date'] }
        expect(start_dates).to eq(start_dates.sort.reverse)
      end

      it 'does not return upcoming bookings' do
        create_booking(user: user, start_date: 10.days.from_now, end_date: 13.days.from_now)

        get '/api/v1/auth/me/bookings/past', headers: auth_headers

        expect(json).to eq([])
      end

      it 'returns 200 with booking data' do
        booking = create_booking(user: user, start_date: 10.days.ago, end_date: 7.days.ago)

        get '/api/v1/auth/me/bookings/past', headers: auth_headers

        expect(response).to have_http_status(:ok)
        expect(json.first['order_reference']).to eq(booking[:order].order_reference)
      end
    end

    context 'with no JWT' do
      it 'returns 401' do
        get '/api/v1/auth/me/bookings/past',
            headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
```

- [ ] **Step 2: Run the spec to confirm it fails**

```bash
bundle exec rspec spec/requests/api/v1/auth/me/bookings_spec.rb --format documentation 2>&1 | head -10
```

Expected: routing error — `No route matches [GET] "/api/v1/auth/me/bookings/upcoming"`

- [ ] **Step 3: Update `config/routes.rb`**

Find this line (around line 15):

```ruby
        resource :me, only: %i[show update destroy], controller: 'me' do
          patch :password, on: :member
        end
```

Change it to:

```ruby
        resource :me, only: %i[show update destroy], controller: 'me' do
          patch :password, on: :member
          scope '/bookings' do
            get :upcoming, to: 'me/bookings#upcoming'
            get :past,     to: 'me/bookings#past'
          end
        end
```

- [ ] **Step 4: Create `app/controllers/api/v1/auth/me/` directory and controller**

First create the directory:

```bash
mkdir -p app/controllers/api/v1/auth/me
```

Then create `app/controllers/api/v1/auth/me/bookings_controller.rb`:

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Auth
      module Me
        class BookingsController < ActionController::API
          include Authenticatable
          include LocaleSetter

          before_action :authenticate_user!
          before_action :set_locale

          def upcoming
            orders = Order.joins(attendees: :event)
                          .where(attendees: { user_id: current_user.id })
                          .where('events.start_date > ?', Time.current)
                          .distinct
                          .order('events.start_date ASC')
            render json: serialise_orders(orders)
          end

          def past
            orders = Order.joins(attendees: :event)
                          .where(attendees: { user_id: current_user.id })
                          .where('events.end_date <= ?', Time.current)
                          .distinct
                          .order('events.start_date DESC')
            render json: serialise_orders(orders)
          end

          private

            def serialise_orders(orders)
              orders.map { |order| serialise_order(order) }
            end

            def serialise_order(order)
              attendees = order.attendees
                               .where(user_id: current_user.id)
                               .includes({ ticket: :tickets_translations }, { event: :events_translations })
              event = attendees.first.event
              lang  = current_user.language || 'ro-RO'

              {
                order_reference: order.order_reference,
                payment_status:  attendees.first.payment_status,
                event:           serialise_event(event, lang),
                attendees:       attendees.map { |a| serialise_attendee(a, lang) }
              }
            end

            def serialise_event(event, lang)
              name = event.events_translations.find { |t| t.languages_code == lang }&.name ||
                     event.events_translations.find { |t| t.languages_code == 'ro-RO' }&.name
              {
                name:          name,
                slug:          event.slug,
                start_date:    event.start_date,
                end_date:      event.end_date,
                location_name: event.location_name,
                address:       event.address
              }
            end

            def serialise_attendee(attendee, lang)
              ticket_name = attendee.ticket&.tickets_translations
                                    &.find { |t| t.languages_code == lang }&.name ||
                            attendee.ticket&.tickets_translations
                                    &.find { |t| t.languages_code == 'ro-RO' }&.name
              {
                first_name:         attendee.first_name,
                last_name:          attendee.last_name,
                ticket_name:        ticket_name,
                dietary_preference: attendee.dietary_preference
              }
            end
        end
      end
    end
  end
end
```

**Note on translation lookup:** `serialise_event` and `serialise_attendee` use `Array#find` on the already-eager-loaded `events_translations` / `tickets_translations` associations instead of calling `find_by` (which would hit the DB again). This keeps queries minimal — one query per order for the attendees, then no extra DB calls for translations.

- [ ] **Step 5: Run the spec to confirm it passes**

```bash
bundle exec rspec spec/requests/api/v1/auth/me/bookings_spec.rb --format documentation
```

Expected: all examples pass.

- [ ] **Step 6: Run the full suite**

```bash
bundle exec rspec
```

Expected: 0 failures.

- [ ] **Step 7: Run RuboCop**

```bash
bundle exec rubocop app/controllers/api/v1/auth/me/bookings_controller.rb \
                    config/routes.rb \
                    spec/requests/api/v1/auth/me/bookings_spec.rb
```

Fix any offenses.

- [ ] **Step 8: Commit and push**

```bash
git add app/controllers/api/v1/auth/me/bookings_controller.rb \
        config/routes.rb \
        spec/requests/api/v1/auth/me/bookings_spec.rb
git commit -m "Add GET /api/v1/auth/me/bookings/upcoming and /past endpoints"
git push origin main
```
