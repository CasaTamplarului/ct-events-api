# Booking Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `POST /api/v1/auth/me/bookings/check` so the FE can check in one call whether the authenticated user already has a `paid` or `payment_pending` booking for one or more events.

**Architecture:** New `check` action on the existing `Api::V1::Auth::Me::BookingsController`. A single DB query joins attendees → events → orders filtered by user, payment status, and slugs. Returns a slug-keyed map so the FE can look up results by event slug. i18n key added for the 422 case.

**Tech Stack:** Rails 8.1, PostgreSQL, RSpec.

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `config/locales/en.yml` | Modify | Add `slugs_required` error key |
| `config/locales/ro.yml` | Modify | Add `slugs_required` error key (Romanian) |
| `config/routes.rb` | Modify | Add `post :check` to the `me/bookings` scope |
| `app/controllers/api/v1/auth/me/bookings_controller.rb` | Modify | Add `check` action |
| `spec/requests/api/v1/auth/me/bookings_spec.rb` | Modify | Add `POST /check` tests |

---

### Task 1: i18n + route + check action + tests + push

**Files:**
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ro.yml`
- Modify: `config/routes.rb`
- Modify: `app/controllers/api/v1/auth/me/bookings_controller.rb`
- Modify: `spec/requests/api/v1/auth/me/bookings_spec.rb`

- [ ] **Step 1: Add `slugs_required` to `config/locales/en.yml`**

Find `passkey_already_registered` (last key in `auth.errors`) and add immediately after it:

```yaml
      slugs_required: "slugs is required"
```

Resulting block:
```yaml
      passkey_already_registered: "Passkey already registered"
      slugs_required: "slugs is required"
```

- [ ] **Step 2: Add `slugs_required` to `config/locales/ro.yml`**

Find `passkey_already_registered` in the Romanian file and add immediately after it:

```yaml
      slugs_required: "slugs este obligatoriu"
```

- [ ] **Step 3: Add the route to `config/routes.rb`**

Find the `scope '/me/bookings'` block (around line 18):

```ruby
        scope '/me/bookings' do
          get :upcoming, to: 'me/bookings#upcoming'
          get :past,     to: 'me/bookings#past'
        end
```

Add the check route:

```ruby
        scope '/me/bookings' do
          get  :upcoming, to: 'me/bookings#upcoming'
          get  :past,     to: 'me/bookings#past'
          post :check,    to: 'me/bookings#check'
        end
```

- [ ] **Step 4: Add the tests to `spec/requests/api/v1/auth/me/bookings_spec.rb`**

Append a new `describe` block at the bottom of the file, before the final `end`:

```ruby
  # ── POST /api/v1/auth/me/bookings/check ──────────────────────────────────────

  describe 'POST /api/v1/auth/me/bookings/check' do
    let(:event_a) do
      create(:event, slug: 'conf-2026', start_date: 10.days.from_now, end_date: 13.days.from_now)
    end
    let(:event_b) do
      create(:event, slug: 'tabara-2026', start_date: 20.days.from_now, end_date: 23.days.from_now)
    end

    def post_check(slugs)
      post '/api/v1/auth/me/bookings/check',
           params: { slugs: slugs }.to_json,
           headers: auth_headers
    end

    context 'with a paid booking' do
      before do
        order = create(:order)
        create(:attendee, event: event_a, order: order, user: user, payment_status: :paid)
      end

      it 'returns has_booking true with the order_reference' do
        post_check(['conf-2026'])
        expect(response).to have_http_status(:ok)
        expect(json['conf-2026']['has_booking']).to be true
        expect(json['conf-2026']['order_reference']).to match(/\ACT-\d{4}-\d{5}\z/)
      end
    end

    context 'with a payment_pending booking' do
      before do
        order = create(:order)
        create(:attendee, event: event_a, order: order, user: user, payment_status: :payment_pending)
      end

      it 'returns has_booking true' do
        post_check(['conf-2026'])
        expect(json['conf-2026']['has_booking']).to be true
      end
    end

    context 'with a refunded booking' do
      before do
        order = create(:order)
        create(:attendee, event: event_a, order: order, user: user, payment_status: :refunded)
      end

      it 'returns has_booking false' do
        post_check(['conf-2026'])
        expect(json['conf-2026']['has_booking']).to be false
        expect(json['conf-2026']['order_reference']).to be_nil
      end
    end

    context 'with no booking for the event' do
      it 'returns has_booking false' do
        post_check(['conf-2026'])
        expect(json['conf-2026']['has_booking']).to be false
        expect(json['conf-2026']['order_reference']).to be_nil
      end
    end

    context 'with an unknown slug' do
      it 'returns has_booking false for unknown slugs' do
        post_check(['does-not-exist'])
        expect(json['does-not-exist']['has_booking']).to be false
        expect(json['does-not-exist']['order_reference']).to be_nil
      end
    end

    context 'with multiple slugs' do
      before do
        order = create(:order)
        create(:attendee, event: event_a, order: order, user: user, payment_status: :paid)
      end

      it 'returns correct result for each slug in one call' do
        post_check(['conf-2026', 'tabara-2026'])
        expect(json['conf-2026']['has_booking']).to be true
        expect(json['tabara-2026']['has_booking']).to be false
      end
    end

    context 'with missing slugs param' do
      it 'returns 422' do
        post '/api/v1/auth/me/bookings/check',
             params: {}.to_json,
             headers: auth_headers
        expect(response).to have_http_status(:unprocessable_entity)
        expect(json['error']).to eq('slugs is required')
      end
    end

    context 'with no JWT' do
      it 'returns 401' do
        post '/api/v1/auth/me/bookings/check',
             params: { slugs: ['conf-2026'] }.to_json,
             headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
```

- [ ] **Step 5: Run the tests to confirm they fail**

```bash
bundle exec rspec spec/requests/api/v1/auth/me/bookings_spec.rb --format documentation 2>&1 | grep -A 2 "check"
```

Expected: `ActionController::RoutingError` or `AbstractController::ActionNotFound`

- [ ] **Step 6: Add the `check` action to `app/controllers/api/v1/auth/me/bookings_controller.rb`**

Add after the `past` action, before `private`:

```ruby
          def check
            slugs = params[:slugs]
            if slugs.blank?
              render json: { error: I18n.t('auth.errors.slugs_required') },
                     status: :unprocessable_content
              return
            end

            result = slugs.index_with { { has_booking: false, order_reference: nil } }

            Attendee
              .joins(:event, :order)
              .where(user_id: current_user.id)
              .where(payment_status: %i[paid payment_pending])
              .where(events: { slug: slugs })
              .select('attendees.id, events.slug AS event_slug, orders.order_reference')
              .each do |row|
                result[row.event_slug] = { has_booking: true, order_reference: row.order_reference }
              end

            render json: result
          end
```

- [ ] **Step 7: Run the tests to confirm they pass**

```bash
bundle exec rspec spec/requests/api/v1/auth/me/bookings_spec.rb --format documentation
```

Expected: all examples pass.

- [ ] **Step 8: Run the full suite**

```bash
bundle exec rspec
```

Expected: 0 failures.

- [ ] **Step 9: Run RuboCop**

```bash
bundle exec rubocop app/controllers/api/v1/auth/me/bookings_controller.rb \
                    config/routes.rb \
                    config/locales/en.yml \
                    config/locales/ro.yml \
                    spec/requests/api/v1/auth/me/bookings_spec.rb
```

Fix any offenses.

- [ ] **Step 10: Commit and push**

```bash
git add app/controllers/api/v1/auth/me/bookings_controller.rb \
        config/routes.rb \
        config/locales/en.yml \
        config/locales/ro.yml \
        spec/requests/api/v1/auth/me/bookings_spec.rb
git commit -m "Add POST /api/v1/auth/me/bookings/check endpoint"
git push origin main
```
