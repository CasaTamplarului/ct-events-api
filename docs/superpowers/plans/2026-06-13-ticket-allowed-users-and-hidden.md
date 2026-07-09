# Ticket Allowed Users & Hidden Flag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `hidden` boolean to tickets (admin-only visibility) and a per-user allowlist M2M that gates whether a logged-in user can book a `for_leaders` ticket.

**Architecture:** Optional JWT decode is added to the public event endpoint so serializers receive `current_user`; `EventSerializer` filters hidden tickets; `TicketSerializer` emits an `allowed` boolean for `for_leaders` tickets based on a new `tickets_allowed_users` junction table. The orders controller guard is extended to enforce the allowlist.

**Tech Stack:** Rails 7.1, PostgreSQL, Alba serializers, RSpec request specs, Directus 10 (metadata registered via migration INSERT).

---

## File Map

| Action | Path |
|--------|------|
| Create | `db/migrate/TIMESTAMP_add_hidden_to_tickets.rb` |
| Create | `db/migrate/TIMESTAMP_create_tickets_allowed_users.rb` |
| Create | `app/models/ticket_allowed_user.rb` |
| Modify | `app/models/ticket.rb` |
| Create | `spec/factories/ticket_allowed_users.rb` |
| Modify | `config/locales/en.yml` |
| Modify | `config/locales/ro.yml` |
| Modify | `app/controllers/concerns/authenticatable.rb` |
| Modify | `app/controllers/api/v1/event_controller.rb` |
| Modify | `app/serializers/event_serializer.rb` |
| Modify | `app/serializers/ticket_serializer.rb` |
| Modify | `app/controllers/api/v1/orders_controller.rb` |
| Modify | `spec/requests/api/v1/event_spec.rb` |
| Modify | `spec/requests/api/v1/orders_spec.rb` |

---

## Task 1: Add `hidden` column to tickets + Directus field

**Files:**
- Create: `db/migrate/20260613100000_add_hidden_to_tickets.rb`

- [ ] **Step 1: Create the migration**

```ruby
# db/migrate/20260613100000_add_hidden_to_tickets.rb
# frozen_string_literal: true

class AddHiddenToTickets < ActiveRecord::Migration[8.1]
  def up
    add_column :tickets, :hidden, :boolean, default: false, null: false

    execute("DELETE FROM directus_fields WHERE collection = 'tickets' AND field = 'hidden'")
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, special, options, width)
      VALUES ('tickets', 'hidden', 'boolean', false, false, 'cast-boolean',
              '{"label":"Hidden (admin only)"}'::json, 'half')
    SQL
  end

  def down
    remove_column :tickets, :hidden
    execute("DELETE FROM directus_fields WHERE collection = 'tickets' AND field = 'hidden'")
  end
end
```

- [ ] **Step 2: Run migration on dev DB (port 5432)**

```bash
bin/rails db:migrate
```

Expected: `AddHiddenToTickets: migrated`

- [ ] **Step 3: Run migration on production DB (port 5433)**

```bash
DATABASE_PORT=5433 DATABASE_PASSWORD=<production-db-password> bin/rails db:migrate
```

Expected: `AddHiddenToTickets: migrated`

- [ ] **Step 4: Verify schema**

```bash
grep "hidden" db/schema.rb | grep tickets
```

Expected: `t.boolean "hidden", default: false, null: false`

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20260613100000_add_hidden_to_tickets.rb db/schema.rb
git commit -m "Add hidden boolean to tickets"
```

---

## Task 2: Create `tickets_allowed_users` junction table + Directus M2M

**Files:**
- Create: `db/migrate/20260613110000_create_tickets_allowed_users.rb`

- [ ] **Step 1: Create the migration**

```ruby
# db/migrate/20260613110000_create_tickets_allowed_users.rb
# frozen_string_literal: true

class CreateTicketsAllowedUsers < ActiveRecord::Migration[8.1]
  def up
    create_table :tickets_allowed_users do |t|
      t.references :ticket, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
    end

    add_index :tickets_allowed_users, %i[ticket_id user_id], unique: true

    # Register junction collection (hidden from nav)
    execute(<<~SQL)
      INSERT INTO directus_collections (collection, hidden, singleton, icon)
      VALUES ('tickets_allowed_users', true, false, 'import_export')
      ON CONFLICT DO NOTHING
    SQL

    # Register junction fields (hidden in UI — they are FK columns)
    execute("DELETE FROM directus_fields WHERE collection = 'tickets_allowed_users'")
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, hidden, readonly)
      VALUES
        ('tickets_allowed_users', 'id', true, true),
        ('tickets_allowed_users', 'ticket_id', true, true),
        ('tickets_allowed_users', 'user_id', true, true)
    SQL

    # Register M2M alias field on tickets (the user-picker that appears in the Directus form)
    execute("DELETE FROM directus_fields WHERE collection = 'tickets' AND field = 'allowed_users'")
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, special, options, width)
      VALUES ('tickets', 'allowed_users', 'list-m2m', false, false, 'm2m',
              '{"template":"{{first_name}} {{last_name}} ({{email}})"}'::json, 'full')
    SQL

    # Register M2M relations
    execute("DELETE FROM directus_relations WHERE many_collection = 'tickets_allowed_users'")
    execute(<<~SQL)
      INSERT INTO directus_relations (many_collection, many_field, one_collection, one_field, junction_field)
      VALUES
        ('tickets_allowed_users', 'ticket_id', 'tickets', 'allowed_users', 'user_id'),
        ('tickets_allowed_users', 'user_id', 'users', null, 'ticket_id')
    SQL
  end

  def down
    execute("DELETE FROM directus_relations WHERE many_collection = 'tickets_allowed_users'")
    execute("DELETE FROM directus_fields WHERE collection = 'tickets_allowed_users'")
    execute("DELETE FROM directus_fields WHERE collection = 'tickets' AND field = 'allowed_users'")
    execute("DELETE FROM directus_collections WHERE collection = 'tickets_allowed_users'")
    drop_table :tickets_allowed_users
  end
end
```

- [ ] **Step 2: Run migration on dev DB**

```bash
bin/rails db:migrate
```

Expected: `CreateTicketsAllowedUsers: migrated`

- [ ] **Step 3: Run migration on production DB**

```bash
DATABASE_PORT=5433 DATABASE_PASSWORD=<production-db-password> bin/rails db:migrate
```

Expected: `CreateTicketsAllowedUsers: migrated`

- [ ] **Step 4: Verify schema**

```bash
grep -A5 "create_table \"tickets_allowed_users\"" db/schema.rb
```

Expected: table with `ticket_id` and `user_id` bigint columns.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20260613110000_create_tickets_allowed_users.rb db/schema.rb
git commit -m "Create tickets_allowed_users junction table with Directus M2M registration"
```

---

## Task 3: Models and factories

**Files:**
- Create: `app/models/ticket_allowed_user.rb`
- Modify: `app/models/ticket.rb`
- Create: `spec/factories/ticket_allowed_users.rb`

- [ ] **Step 1: Create `TicketAllowedUser` model**

```ruby
# app/models/ticket_allowed_user.rb
# frozen_string_literal: true

class TicketAllowedUser < ApplicationRecord
  belongs_to :ticket
  belongs_to :user
end
```

- [ ] **Step 2: Add associations to `Ticket`**

Open `app/models/ticket.rb` and add two lines after the existing `has_many :ticket_meal_slots` line:

```ruby
  has_many :ticket_allowed_users, dependent: :destroy
  has_many :allowed_users, through: :ticket_allowed_users, source: :user
```

The file should now read:

```ruby
# frozen_string_literal: true

class Ticket < ApplicationRecord
  has_many :tickets_translations, foreign_key: 'tickets_id', dependent: :destroy, inverse_of: :ticket
  has_many :ticket_meal_slots, dependent: :destroy
  has_many :ticket_allowed_users, dependent: :destroy
  has_many :allowed_users, through: :ticket_allowed_users, source: :user

  belongs_to :event

  before_validation :fill_valid_date_range
  validate :valid_to_not_before_valid_from

  def translations(language_code)
    tickets_translations.find_by(languages_code: language_code)
  end

  private

    def fill_valid_date_range
      self.valid_to   = valid_from if valid_from && valid_to.nil?
      self.valid_from = valid_to   if valid_to   && valid_from.nil?
    end

    def valid_to_not_before_valid_from
      return unless valid_from && valid_to
      errors.add(:valid_to, 'must be on or after valid_from') if valid_to < valid_from
    end
end
```

- [ ] **Step 3: Create factory**

```ruby
# spec/factories/ticket_allowed_users.rb
# frozen_string_literal: true

FactoryBot.define do
  factory :ticket_allowed_user do
    ticket
    user
  end
end
```

- [ ] **Step 4: Verify models load**

```bash
bin/rails runner "puts TicketAllowedUser.count; puts Ticket.first&.ticket_allowed_users&.count"
```

Expected: no errors, prints `0` twice (or whatever the actual counts are).

- [ ] **Step 5: Commit**

```bash
git add app/models/ticket_allowed_user.rb app/models/ticket.rb spec/factories/ticket_allowed_users.rb
git commit -m "Add TicketAllowedUser model and Ticket associations"
```

---

## Task 4: I18n — add `not_allowed_for_ticket` error key

**Files:**
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ro.yml`

- [ ] **Step 1: Add key to `en.yml`**

Find the `orders: errors:` block in `config/locales/en.yml` and add the new key after `leader_ticket_required`:

```yaml
      not_allowed_for_ticket: "You are not on the allowed list for this ticket"
```

- [ ] **Step 2: Add key to `ro.yml`**

Find the `orders: errors:` block in `config/locales/ro.yml` and add after `leader_ticket_required`:

```yaml
      not_allowed_for_ticket: "Nu ești pe lista de permisiuni pentru acest bilet"
```

- [ ] **Step 3: Verify keys load**

```bash
bin/rails runner "puts I18n.t('orders.errors.not_allowed_for_ticket', locale: :en); puts I18n.t('orders.errors.not_allowed_for_ticket', locale: :ro)"
```

Expected:
```
You are not on the allowed list for this ticket
Nu ești pe lista de permisiuni pentru acest bilet
```

- [ ] **Step 4: Commit**

```bash
git add config/locales/en.yml config/locales/ro.yml
git commit -m "Add not_allowed_for_ticket I18n error key"
```

---

## Task 5: Optional auth + hidden ticket filtering on the event endpoint

**Files:**
- Modify: `app/controllers/concerns/authenticatable.rb`
- Modify: `app/controllers/api/v1/event_controller.rb`
- Modify: `app/serializers/event_serializer.rb`
- Modify: `spec/requests/api/v1/event_spec.rb`

- [ ] **Step 1: Write failing tests**

Add a new context block at the bottom of `spec/requests/api/v1/event_spec.rb`, before the final `end`:

```ruby
  context 'hidden tickets' do
    let!(:ticket) { create(:ticket, event: event, hidden: false) }
    let!(:hidden_ticket) { create(:ticket, event: event, hidden: true) }

    before do
      create(:tickets_translation, tickets_id: ticket.id, languages_code: language_code, name: 'Standard')
      create(:tickets_translation, tickets_id: hidden_ticket.id, languages_code: language_code, name: 'Hidden Ticket')
    end

    def get_event_with_token(user)
      get "/api/v1/#{language_code}/event/#{event.slug}",
          headers: { 'Authorization' => "Bearer #{JwtService.encode(user.id)}" }
    end

    it 'does not show hidden tickets to unauthenticated users' do
      get_event

      ticket_names = json['tickets'].map { |t| t['name'] }
      expect(ticket_names).to include('Standard')
      expect(ticket_names).not_to include('Hidden Ticket')
    end

    it 'does not show hidden tickets to attendee-role users' do
      user = create(:user, role: 'attendee')
      get_event_with_token(user)

      ticket_names = json['tickets'].map { |t| t['name'] }
      expect(ticket_names).not_to include('Hidden Ticket')
    end

    it 'does not show hidden tickets to leader-role users' do
      user = create(:user, role: 'leader')
      get_event_with_token(user)

      ticket_names = json['tickets'].map { |t| t['name'] }
      expect(ticket_names).not_to include('Hidden Ticket')
    end

    it 'shows hidden tickets to admin-role users' do
      user = create(:user, role: 'admin')
      get_event_with_token(user)

      ticket_names = json['tickets'].map { |t| t['name'] }
      expect(ticket_names).to include('Standard')
      expect(ticket_names).to include('Hidden Ticket')
    end
  end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rspec spec/requests/api/v1/event_spec.rb -e "hidden tickets" --format documentation
```

Expected: 4 failures (hidden filtering not yet implemented).

- [ ] **Step 3: Add `try_authenticate_user` to `Authenticatable`**

Open `app/controllers/concerns/authenticatable.rb` and add after `authenticate_user!`:

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

- [ ] **Step 4: Update `EventController#show`**

Replace the full `show` method in `app/controllers/api/v1/event_controller.rb` with:

```ruby
      def show
        try_authenticate_user

        event = Event
          .includes(:events_translations, :attendees, :event_attendee_fields, :event_gallery_items,
                    tickets: [:tickets_translations, :ticket_meal_slots, :ticket_allowed_users],
                    event_speakers: :event_speakers_translations,
                    event_description_sections: :event_description_section_translations)
          .find_by!(slug: params[:slug])

        if event.is_private && params[:token] != event.access_token.to_s
          return render json: { error: I18n.t('errors.not_found') }, status: :not_found
        end

        render json:
          EventSerializer.new(event, params: { languages_code: params[:languages_code],
                                               current_user: current_user }).serialize,
               status: :ok
      end
```

- [ ] **Step 5: Update `EventSerializer` tickets attribute**

In `app/serializers/event_serializer.rb`, replace the `tickets` attribute block:

```ruby
  attribute :tickets do |object|
    next nil if object.past? || object.tickets.empty?

    visible = object.tickets.reject do |t|
      t.hidden && params[:current_user]&.role != 'admin'
    end

    next nil if visible.empty?

    TicketSerializer.new(visible, params: { languages_code: params[:languages_code],
                                            current_user: params[:current_user] })
  end
```

- [ ] **Step 6: Run tests to confirm they pass**

```bash
bin/rspec spec/requests/api/v1/event_spec.rb -e "hidden tickets" --format documentation
```

Expected: 4 examples, 0 failures.

- [ ] **Step 7: Run full event spec to check for regressions**

```bash
bin/rspec spec/requests/api/v1/event_spec.rb --format documentation
```

Expected: all green.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/concerns/authenticatable.rb \
        app/controllers/api/v1/event_controller.rb \
        app/serializers/event_serializer.rb \
        spec/requests/api/v1/event_spec.rb
git commit -m "Add optional auth to event endpoint and filter hidden tickets by role"
```

---

## Task 6: `allowed` field in `TicketSerializer`

**Files:**
- Modify: `app/serializers/ticket_serializer.rb`
- Modify: `spec/requests/api/v1/event_spec.rb`

- [ ] **Step 1: Write failing tests**

Add another context block at the bottom of `spec/requests/api/v1/event_spec.rb`:

```ruby
  context 'for_leaders ticket allowed field' do
    let!(:leader_ticket) { create(:ticket, event: event, for_leaders: true) }
    let!(:public_ticket) { create(:ticket, event: event, for_leaders: false) }

    before do
      create(:tickets_translation, tickets_id: leader_ticket.id, languages_code: language_code, name: 'Leader Ticket')
      create(:tickets_translation, tickets_id: public_ticket.id, languages_code: language_code, name: 'Public Ticket')
    end

    def get_event_with_token(user)
      get "/api/v1/#{language_code}/event/#{event.slug}",
          headers: { 'Authorization' => "Bearer #{JwtService.encode(user.id)}" }
    end

    def ticket_json(name)
      json['tickets'].find { |t| t['name'] == name }
    end

    it 'does not include allowed field on public tickets' do
      get_event

      expect(ticket_json('Public Ticket')).not_to have_key('allowed')
    end

    it 'returns allowed: false for unauthenticated users on for_leaders tickets' do
      get_event

      expect(ticket_json('Leader Ticket')['allowed']).to be false
    end

    it 'returns allowed: true when no allowed_users list and user is leader' do
      user = create(:user, role: 'leader')
      get_event_with_token(user)

      expect(ticket_json('Leader Ticket')['allowed']).to be true
    end

    it 'returns allowed: true when user is in the allowed_users list' do
      user = create(:user, role: 'leader')
      create(:ticket_allowed_user, ticket: leader_ticket, user: user)
      get_event_with_token(user)

      expect(ticket_json('Leader Ticket')['allowed']).to be true
    end

    it 'returns allowed: false when allowed_users list exists and user is not in it' do
      user = create(:user, role: 'leader')
      other_user = create(:user, role: 'leader')
      create(:ticket_allowed_user, ticket: leader_ticket, user: other_user)
      get_event_with_token(user)

      expect(ticket_json('Leader Ticket')['allowed']).to be false
    end

    it 'returns allowed: false for unauthenticated when allowed_users list exists' do
      other_user = create(:user, role: 'leader')
      create(:ticket_allowed_user, ticket: leader_ticket, user: other_user)
      get_event

      expect(ticket_json('Leader Ticket')['allowed']).to be false
    end
  end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rspec spec/requests/api/v1/event_spec.rb -e "for_leaders ticket allowed field" --format documentation
```

Expected: multiple failures (allowed field not yet implemented).

- [ ] **Step 3: Add `allowed` attribute to `TicketSerializer`**

Open `app/serializers/ticket_serializer.rb`. Replace the entire file:

```ruby
# frozen_string_literal: true

class TicketSerializer < ApplicationSerializer
  attributes :id, :food_included, :for_leaders, :valid_from, :valid_to

  attribute :price do |object|
    params[:show_price] == false ? nil : object.price
  end

  attribute :name do |object|
    object.translations(params[:languages_code])&.name
  end

  attribute :description do |object|
    object.translations(params[:languages_code])&.description
  end

  attribute :meal_slots do |object|
    object.ticket_meal_slots
          .sort_by { |s| [s.occurs_on, s.sort || 0] }
          .map { |s| { meal_type: s.meal_type, occurs_on: s.occurs_on } }
  end

  attribute :allowed, if: proc { |object, _| object.for_leaders } do |object|
    user = params[:current_user]
    next false if user.nil?

    if object.ticket_allowed_users.any?
      object.ticket_allowed_users.any? { |tau| tau.user_id == user.id }
    else
      true
    end
  end
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bin/rspec spec/requests/api/v1/event_spec.rb -e "for_leaders ticket allowed field" --format documentation
```

Expected: 6 examples, 0 failures.

- [ ] **Step 5: Run full event spec to check for regressions**

```bash
bin/rspec spec/requests/api/v1/event_spec.rb --format documentation
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add app/serializers/ticket_serializer.rb spec/requests/api/v1/event_spec.rb
git commit -m "Add allowed field to TicketSerializer for for_leaders tickets"
```

---

## Task 7: Orders controller — enforce allowed_users list

**Files:**
- Modify: `app/controllers/api/v1/orders_controller.rb`
- Modify: `spec/requests/api/v1/orders_spec.rb`

- [ ] **Step 1: Write failing tests**

Find the for_leaders section in `spec/requests/api/v1/orders_spec.rb` (or add it if absent). Add the following context block. It lives at the same level as the existing `describe 'success'` block:

```ruby
  context 'for_leaders ticket with allowed_users list' do
    let(:leader_user) { create(:user, role: 'leader') }
    let(:other_leader) { create(:user, role: 'leader') }
    let(:leader_ticket) { create(:ticket, event: event, for_leaders: true) }
    let!(:leader_ticket_translation) do
      create(:tickets_translation, tickets_id: leader_ticket.id, languages_code: language_code, name: 'Leader')
    end

    def leader_item(user_id: leader_user.id)
      {
        event_slug: event.slug,
        ticket_id: leader_ticket.id,
        attendee: {
          first_name: 'Ion',
          last_name: 'Popescu',
          email_address: "leader#{user_id}@example.com",
          phone_number: '0722000000'
        }
      }
    end

    def post_order_as(user, item)
      post "/api/v1/#{language_code}/orders",
           params: { items: [item] }.to_json,
           headers: {
             'Content-Type' => 'application/json',
             'Authorization' => "Bearer #{JwtService.encode(user.id)}"
           }
    end

    context 'when no allowed_users are assigned' do
      it 'allows any non-attendee role to create an order' do
        post_order_as(leader_user, leader_item)

        expect(response).to have_http_status(:created)
      end
    end

    context 'when allowed_users list is non-empty' do
      before { create(:ticket_allowed_user, ticket: leader_ticket, user: leader_user) }

      it 'allows the user who is in the list to create an order' do
        post_order_as(leader_user, leader_item)

        expect(response).to have_http_status(:created)
      end

      it 'returns 403 for a user who is not in the list' do
        post_order_as(other_leader, leader_item(user_id: other_leader.id))

        expect(response).to have_http_status(:forbidden)
        expect(json['error']).to eq(I18n.t('orders.errors.not_allowed_for_ticket', locale: :en))
      end
    end
  end
```

- [ ] **Step 2: Run new tests to confirm they fail**

```bash
bin/rspec spec/requests/api/v1/orders_spec.rb -e "for_leaders ticket with allowed_users list" --format documentation
```

Expected: failures — the 403 case likely passes through or returns the wrong error; the allowed case should pass if the existing for_leaders guard lets leaders through.

- [ ] **Step 3: Update ticket lookup to eager-load `ticket_allowed_users`**

In `app/controllers/api/v1/orders_controller.rb`, in the `resolve_items` private method, find the ticket lookup (lines ~52–60) and update both branches to include `:ticket_allowed_users`:

```ruby
            ticket = if item[:ticket_id].present?
                       event.tickets.includes(:ticket_allowed_users).find_by(id: item[:ticket_id])
                     else
                       event.tickets
                            .includes(:ticket_allowed_users)
                            .joins(:tickets_translations)
                            .where(tickets_translations: { name: item[:ticket_name],
                                                           languages_code: params[:languages_code] })
                            .first
                     end
```

- [ ] **Step 4: Extend the `for_leaders` guard**

In `resolve_items`, find the existing guard (around line 67):

```ruby
            if ticket.for_leaders && !%w[leader admin volunteer].include?(@current_user&.role)
              render json: { error: t('orders.errors.leader_ticket_required') }, status: :forbidden
              break
            end
```

Replace it with:

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

- [ ] **Step 5: Run new tests to confirm they pass**

```bash
bin/rspec spec/requests/api/v1/orders_spec.rb -e "for_leaders ticket with allowed_users list" --format documentation
```

Expected: all green.

- [ ] **Step 6: Run full orders spec to check for regressions**

```bash
bin/rspec spec/requests/api/v1/orders_spec.rb --format documentation
```

Expected: all green.

- [ ] **Step 7: Run the full test suite**

```bash
bin/rspec --format progress
```

Expected: all green (or only pre-existing failures).

- [ ] **Step 8: Commit**

```bash
git add app/controllers/api/v1/orders_controller.rb spec/requests/api/v1/orders_spec.rb
git commit -m "Enforce allowed_users list in orders controller for_leaders guard"
```

---

## Task 8: Rubocop + push

- [ ] **Step 1: Run rubocop**

```bash
bin/rubocop
```

- [ ] **Step 2: Auto-fix any offenses**

```bash
bin/rubocop -a
```

- [ ] **Step 3: Commit any rubocop fixes (if any)**

```bash
git add -p
git commit -m "Rubocop fixes for ticket allowed-users and hidden feature"
```

- [ ] **Step 4: Push to main**

```bash
git push origin master
```
