# Food Stamp Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add opt-in per-meal tracking for multi-day events — kitchen staff scan attendee QR codes to stamp individual meal entitlements, with seconds tracked by count.

**Architecture:** Two new tables (`ticket_meal_slots` and `meal_stamps`) store meal entitlements and stamp events. Two new scan endpoints handle listing slots and creating stamps. Existing `GET /scan/orders/:ref` and `GET /scan/events` responses are extended with meal data. All endpoints reuse the existing `can_check_in_attendees` permission.

**Tech Stack:** Rails 8, PostgreSQL, RSpec + FactoryBot. No new gems.

---

## File Map

| Action | Path |
|--------|------|
| Create | `db/migrate/20260603120000_create_ticket_meal_slots.rb` |
| Create | `db/migrate/20260603120001_create_meal_stamps.rb` |
| Create | `app/models/ticket_meal_slot.rb` |
| Create | `app/models/meal_stamp.rb` |
| Create | `spec/models/ticket_meal_slot_spec.rb` |
| Create | `spec/models/meal_stamp_spec.rb` |
| Create | `spec/factories/ticket_meal_slots.rb` |
| Create | `spec/factories/meal_stamps.rb` |
| Create | `app/controllers/api/v1/scan/meal_slots_controller.rb` |
| Create | `app/controllers/api/v1/scan/meal_stamps_controller.rb` |
| Create | `spec/requests/api/v1/scan/meal_slots_spec.rb` |
| Create | `spec/requests/api/v1/scan/meal_stamps_spec.rb` |
| Modify | `app/models/ticket.rb` — add `has_many :ticket_meal_slots` |
| Modify | `app/models/attendee.rb` — add `has_many :meal_stamps` |
| Modify | `config/routes.rb` — add 2 scan routes |
| Modify | `app/controllers/concerns/scan_serialisable.rb` — add `meal_slots` to attendee |
| Modify | `app/controllers/api/v1/scan/events_controller.rb` — add `has_meal_tracking` |

---

## Task 1: Migrations

**Files:**
- Create: `db/migrate/20260603120000_create_ticket_meal_slots.rb`
- Create: `db/migrate/20260603120001_create_meal_stamps.rb`

- [ ] **Step 1: Create ticket_meal_slots migration**

  ```bash
  cd /home/timo/SynthBit/CasaTamplarului/Events/ct-events-api
  bin/rails generate migration CreateTicketMealSlots
  ```

  Open the generated file and replace its content with:

  ```ruby
  # frozen_string_literal: true

  class CreateTicketMealSlots < ActiveRecord::Migration[8.0]
    def change
      create_table :ticket_meal_slots do |t|
        t.references :ticket, null: false, foreign_key: true
        t.date    :occurs_on, null: false
        t.string  :meal_type, null: false
        t.integer :sort
        t.timestamps
      end
      add_index :ticket_meal_slots, %i[ticket_id occurs_on meal_type]
    end
  end
  ```

- [ ] **Step 2: Create meal_stamps migration**

  ```bash
  bin/rails generate migration CreateMealStamps
  ```

  Replace content with:

  ```ruby
  # frozen_string_literal: true

  class CreateMealStamps < ActiveRecord::Migration[8.0]
    def change
      create_table :meal_stamps do |t|
        t.references :attendee,          null: false, foreign_key: true
        t.references :ticket_meal_slot,  null: false, foreign_key: true
        t.bigint     :stamped_by_user_id, null: false
        t.datetime   :created_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      end
      add_foreign_key :meal_stamps, :users, column: :stamped_by_user_id
      add_index :meal_stamps, %i[attendee_id ticket_meal_slot_id]
    end
  end
  ```

- [ ] **Step 3: Run migrations**

  ```bash
  bin/rails db:migrate
  ```

  Expected: two `up` migrations complete, no errors.

- [ ] **Step 4: Commit**

  ```bash
  git add db/migrate/ db/schema.rb
  git commit -m "Add ticket_meal_slots and meal_stamps tables"
  ```

---

## Task 2: Models (TDD)

**Files:**
- Create: `app/models/ticket_meal_slot.rb`
- Create: `app/models/meal_stamp.rb`
- Create: `spec/models/ticket_meal_slot_spec.rb`
- Create: `spec/models/meal_stamp_spec.rb`
- Modify: `app/models/ticket.rb`
- Modify: `app/models/attendee.rb`

- [ ] **Step 1: Write failing model specs**

  Create `spec/models/ticket_meal_slot_spec.rb`:

  ```ruby
  # frozen_string_literal: true

  require 'rails_helper'

  RSpec.describe TicketMealSlot, type: :model do
    let(:ticket) { create(:ticket) }

    it 'is valid with ticket, occurs_on, and meal_type' do
      slot = described_class.new(ticket: ticket, occurs_on: Date.today, meal_type: 'lunch')
      expect(slot).to be_valid
    end

    it 'is invalid without occurs_on' do
      slot = described_class.new(ticket: ticket, meal_type: 'lunch')
      expect(slot).not_to be_valid
    end

    it 'is invalid without meal_type' do
      slot = described_class.new(ticket: ticket, occurs_on: Date.today)
      expect(slot).not_to be_valid
    end

    it 'is invalid with an unknown meal_type' do
      slot = described_class.new(ticket: ticket, occurs_on: Date.today, meal_type: 'brunch')
      expect(slot).not_to be_valid
    end

    it 'accepts all valid meal types' do
      %w[breakfast lunch dinner snack].each do |type|
        slot = described_class.new(ticket: ticket, occurs_on: Date.today, meal_type: type)
        expect(slot).to be_valid, "expected #{type} to be valid"
      end
    end
  end
  ```

  Create `spec/models/meal_stamp_spec.rb`:

  ```ruby
  # frozen_string_literal: true

  require 'rails_helper'

  RSpec.describe MealStamp, type: :model do
    let(:event)    { create(:event, start_date: 2.days.from_now, end_date: 3.days.from_now) }
    let(:ticket)   { create(:ticket, event: event) }
    let(:order)    { create(:order) }
    let(:attendee) { create(:attendee, event: event, order: order, ticket: ticket) }
    let(:slot)     { create(:ticket_meal_slot, ticket: ticket, occurs_on: 2.days.from_now, meal_type: 'lunch') }
    let(:stamper)  { create(:user) }

    it 'is valid with attendee, ticket_meal_slot, and stamped_by_user_id' do
      stamp = described_class.new(attendee: attendee, ticket_meal_slot: slot, stamped_by_user_id: stamper.id)
      expect(stamp).to be_valid
    end

    it 'is invalid without stamped_by_user_id' do
      stamp = described_class.new(attendee: attendee, ticket_meal_slot: slot)
      expect(stamp).not_to be_valid
    end

    it 'allows duplicate attendee + slot (seconds)' do
      create(:meal_stamp, attendee: attendee, ticket_meal_slot: slot, stamped_by_user_id: stamper.id)
      second = described_class.new(attendee: attendee, ticket_meal_slot: slot, stamped_by_user_id: stamper.id)
      expect(second).to be_valid
    end
  end
  ```

- [ ] **Step 2: Run specs to confirm they fail**

  ```bash
  bundle exec rspec spec/models/ticket_meal_slot_spec.rb spec/models/meal_stamp_spec.rb --no-color 2>&1 | head -10
  ```

  Expected: `NameError: uninitialized constant TicketMealSlot`

- [ ] **Step 3: Create TicketMealSlot model**

  Create `app/models/ticket_meal_slot.rb`:

  ```ruby
  # frozen_string_literal: true

  class TicketMealSlot < ApplicationRecord
    MEAL_TYPES = %w[breakfast lunch dinner snack].freeze

    belongs_to :ticket
    has_many :meal_stamps, dependent: :destroy

    validates :occurs_on, :meal_type, presence: true
    validates :meal_type, inclusion: { in: MEAL_TYPES }
  end
  ```

- [ ] **Step 4: Create MealStamp model**

  Create `app/models/meal_stamp.rb`:

  ```ruby
  # frozen_string_literal: true

  class MealStamp < ApplicationRecord
    belongs_to :attendee
    belongs_to :ticket_meal_slot
    belongs_to :stamped_by, class_name: 'User', foreign_key: :stamped_by_user_id

    validates :stamped_by_user_id, presence: true
  end
  ```

- [ ] **Step 5: Add associations to Ticket and Attendee**

  In `app/models/ticket.rb`, add after `has_many :tickets_translations`:

  ```ruby
  has_many :ticket_meal_slots, dependent: :destroy
  ```

  In `app/models/attendee.rb`, add after the `belongs_to` lines:

  ```ruby
  has_many :meal_stamps, dependent: :destroy
  ```

- [ ] **Step 6: Run model specs**

  ```bash
  bundle exec rspec spec/models/ticket_meal_slot_spec.rb spec/models/meal_stamp_spec.rb --no-color
  ```

  Expected: all examples pass, 0 failures.

- [ ] **Step 7: Commit**

  ```bash
  git add app/models/ticket_meal_slot.rb app/models/meal_stamp.rb \
          app/models/ticket.rb app/models/attendee.rb \
          spec/models/ticket_meal_slot_spec.rb spec/models/meal_stamp_spec.rb
  git commit -m "Add TicketMealSlot and MealStamp models"
  ```

---

## Task 3: Factories

**Files:**
- Create: `spec/factories/ticket_meal_slots.rb`
- Create: `spec/factories/meal_stamps.rb`

- [ ] **Step 1: Create factories**

  Create `spec/factories/ticket_meal_slots.rb`:

  ```ruby
  # frozen_string_literal: true

  FactoryBot.define do
    factory :ticket_meal_slot do
      ticket
      occurs_on { Date.today }
      meal_type { 'lunch' }
      sort      { 1 }
    end
  end
  ```

  Create `spec/factories/meal_stamps.rb`:

  ```ruby
  # frozen_string_literal: true

  FactoryBot.define do
    factory :meal_stamp do
      attendee
      ticket_meal_slot
      stamped_by_user_id { create(:user).id }
    end
  end
  ```

- [ ] **Step 2: Verify factories work**

  ```bash
  bundle exec rspec spec/models/meal_stamp_spec.rb --no-color
  ```

  Expected: all examples pass.

- [ ] **Step 3: Commit**

  ```bash
  git add spec/factories/ticket_meal_slots.rb spec/factories/meal_stamps.rb
  git commit -m "Add ticket_meal_slot and meal_stamp factories"
  ```

---

## Task 4: Routes

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Add routes**

  In `config/routes.rb`, find the `namespace :scan` block:

  ```ruby
  namespace :scan do
    get 'events', to: 'events#index'
    get 'search', to: 'search#index'
    scope '/orders/:order_reference' do
  ```

  Add the two new routes after `get 'search'`:

  ```ruby
  namespace :scan do
    get  'events',      to: 'events#index'
    get  'search',      to: 'search#index'
    get  'meal_slots',  to: 'meal_slots#index'
    post 'meal_stamps', to: 'meal_stamps#create'
    scope '/orders/:order_reference' do
      get   '/', to: 'orders#show',   as: 'scan_order'
      patch '/', to: 'orders#update', as: 'scan_order_update'
    end
  end
  ```

- [ ] **Step 2: Verify routes registered**

  ```bash
  bin/rails routes | grep "meal"
  ```

  Expected: two lines — `meal_slots` GET and `meal_stamps` POST.

- [ ] **Step 3: Commit**

  ```bash
  git add config/routes.rb
  git commit -m "Add meal_slots and meal_stamps scan routes"
  ```

---

## Task 5: GET /api/v1/scan/meal_slots (TDD)

**Files:**
- Create: `spec/requests/api/v1/scan/meal_slots_spec.rb`
- Create: `app/controllers/api/v1/scan/meal_slots_controller.rb`

- [ ] **Step 1: Write failing spec**

  Create `spec/requests/api/v1/scan/meal_slots_spec.rb`:

  ```ruby
  # frozen_string_literal: true

  require 'rails_helper'

  RSpec.describe 'GET /api/v1/scan/meal_slots' do
    let(:admin)         { create(:user, role: 'admin') }
    let(:attendee_user) { create(:user, role: 'attendee') }
    let(:event)         { create(:event, slug: 'tabara-2026', start_date: 7.days.from_now, end_date: 10.days.from_now) }
    let(:ticket)        { create(:ticket, event: event) }
    let(:date)          { 8.days.from_now.to_date }

    def auth_header(user)
      { 'Authorization' => "Bearer #{JwtService.encode(user.id)}", 'Content-Type' => 'application/json' }
    end

    def get_slots(event_slug: event.slug, date: self.date, user: admin)
      get '/api/v1/scan/meal_slots', params: { event_slug: event_slug, date: date.to_s },
                                     headers: auth_header(user)
    end

    it 'returns 401 without a token' do
      get '/api/v1/scan/meal_slots', params: { event_slug: event.slug, date: date.to_s }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 for attendee role' do
      get_slots(user: attendee_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 404 for unknown event_slug' do
      get_slots(event_slug: 'unknown-event')
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 422 when date param is missing' do
      get '/api/v1/scan/meal_slots', params: { event_slug: event.slug }, headers: auth_header(admin)
      expect(response).to have_http_status(:unprocessable_content)
    end

    context 'with meal slots on the requested date' do
      let!(:lunch_slot)  { create(:ticket_meal_slot, ticket: ticket, occurs_on: date, meal_type: 'lunch',  sort: 1) }
      let!(:dinner_slot) { create(:ticket_meal_slot, ticket: ticket, occurs_on: date, meal_type: 'dinner', sort: 2) }
      let!(:other_date)  { create(:ticket_meal_slot, ticket: ticket, occurs_on: date + 1, meal_type: 'lunch', sort: 1) }

      it 'returns 200 with slots for that date only' do
        get_slots
        expect(response).to have_http_status(:ok)
        expect(json.length).to eq(2)
        expect(json.pluck('meal_type')).to contain_exactly('lunch', 'dinner')
      end

      it 'returns id, meal_type, occurs_on, and sort for each slot' do
        get_slots
        slot = json.find { |s| s['meal_type'] == 'lunch' }
        expect(slot.keys).to contain_exactly('id', 'meal_type', 'occurs_on', 'sort')
        expect(slot['id']).to eq(lunch_slot.id)
      end
    end

    it 'returns empty array when no slots on that date' do
      get_slots
      expect(response).to have_http_status(:ok)
      expect(json).to eq([])
    end

    context 'deduplication across tickets' do
      let(:ticket2) { create(:ticket, event: event) }
      let!(:slot_t1) { create(:ticket_meal_slot, ticket: ticket,  occurs_on: date, meal_type: 'lunch', sort: 1) }
      let!(:slot_t2) { create(:ticket_meal_slot, ticket: ticket2, occurs_on: date, meal_type: 'lunch', sort: 1) }

      it 'returns only one entry per meal_type when multiple tickets share it' do
        get_slots
        expect(json.select { |s| s['meal_type'] == 'lunch' }.length).to eq(1)
      end
    end

    context 'slots from a different event' do
      let(:other_event)  { create(:event, slug: 'other-event', start_date: 7.days.from_now, end_date: 10.days.from_now) }
      let(:other_ticket) { create(:ticket, event: other_event) }
      let!(:other_slot)  { create(:ticket_meal_slot, ticket: other_ticket, occurs_on: date, meal_type: 'lunch', sort: 1) }

      it 'does not include slots from other events' do
        get_slots
        expect(json).to eq([])
      end
    end
  end
  ```

- [ ] **Step 2: Run to confirm failure**

  ```bash
  bundle exec rspec spec/requests/api/v1/scan/meal_slots_spec.rb --no-color 2>&1 | tail -5
  ```

  Expected: routing error or `AbstractController::ActionNotFound`.

- [ ] **Step 3: Implement the controller**

  Create `app/controllers/api/v1/scan/meal_slots_controller.rb`:

  ```ruby
  # frozen_string_literal: true

  module Api
    module V1
      module Scan
        class MealSlotsController < ActionController::API
          include Authenticatable

          before_action :authenticate_user!
          before_action { require_permission!(:can_check_in_attendees) }

          def index
            event = Event.find_by(slug: params[:event_slug])
            return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless event

            if params[:date].blank?
              return render json: { error: 'date is required' }, status: :unprocessable_content
            end

            date = begin
                     Date.parse(params[:date])
                   rescue ArgumentError, TypeError
                     nil
                   end
            return render json: { error: 'invalid date' }, status: :unprocessable_content unless date

            slots = TicketMealSlot
                      .joins(:ticket)
                      .where(tickets: { event_id: event.id })
                      .where(occurs_on: date)
                      .order(:sort, :id)

            seen = {}
            deduplicated = slots.each_with_object([]) do |slot, arr|
              next if seen[slot.meal_type]

              seen[slot.meal_type] = true
              arr << slot
            end

            render json: deduplicated.map { |s|
              { id: s.id, meal_type: s.meal_type, occurs_on: s.occurs_on, sort: s.sort }
            }
          end
        end
      end
    end
  end
  ```

- [ ] **Step 4: Run specs**

  ```bash
  bundle exec rspec spec/requests/api/v1/scan/meal_slots_spec.rb --no-color
  ```

  Expected: all examples pass, 0 failures.

- [ ] **Step 5: Commit**

  ```bash
  git add app/controllers/api/v1/scan/meal_slots_controller.rb \
          spec/requests/api/v1/scan/meal_slots_spec.rb
  git commit -m "Add GET /scan/meal_slots endpoint"
  ```

---

## Task 6: POST /api/v1/scan/meal_stamps (TDD)

**Files:**
- Create: `spec/requests/api/v1/scan/meal_stamps_spec.rb`
- Create: `app/controllers/api/v1/scan/meal_stamps_controller.rb`

- [ ] **Step 1: Write failing spec**

  Create `spec/requests/api/v1/scan/meal_stamps_spec.rb`:

  ```ruby
  # frozen_string_literal: true

  require 'rails_helper'

  RSpec.describe 'POST /api/v1/scan/meal_stamps' do
    let(:admin)         { create(:user, role: 'admin', first_name: 'Ana', last_name: 'Ionescu') }
    let(:attendee_user) { create(:user, role: 'attendee') }
    let(:event)         { create(:event, start_date: 2.days.from_now, end_date: 5.days.from_now) }
    let(:ticket)        { create(:ticket, event: event) }
    let(:order)         { create(:order) }
    let!(:attendee)     { create(:attendee, event: event, order: order, ticket: ticket, first_name: 'Ion', last_name: 'Popescu') }
    let(:slot_date)     { 3.days.from_now.to_date }
    let!(:slot)         { create(:ticket_meal_slot, ticket: ticket, occurs_on: slot_date, meal_type: 'lunch', sort: 1) }

    def auth_header(user)
      { 'Authorization' => "Bearer #{JwtService.encode(user.id)}", 'Content-Type' => 'application/json' }
    end

    def post_stamp(qr_code: attendee.qr_code, meal_type: 'lunch', occurs_on: slot_date.to_s, user: admin)
      post '/api/v1/scan/meal_stamps',
           params: { qr_code: qr_code, meal_type: meal_type, occurs_on: occurs_on }.to_json,
           headers: auth_header(user)
    end

    it 'returns 401 without a token' do
      post '/api/v1/scan/meal_stamps',
           params: { qr_code: attendee.qr_code, meal_type: 'lunch', occurs_on: slot_date.to_s }.to_json,
           headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 for attendee role' do
      post_stamp(user: attendee_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 422 when qr_code is missing' do
      post '/api/v1/scan/meal_stamps',
           params: { meal_type: 'lunch', occurs_on: slot_date.to_s }.to_json,
           headers: auth_header(admin)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns 404 for an unknown QR code' do
      post_stamp(qr_code: 'CT-2026-XXXXXX-99999')
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 422 when the attendee is not entitled to that meal' do
      post_stamp(meal_type: 'breakfast')
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('Not entitled')
    end

    context 'first stamp' do
      it 'returns 200 with already_stamped: false and total_stamps: 1' do
        post_stamp
        expect(response).to have_http_status(:ok)
        expect(json['already_stamped']).to be(false)
        expect(json['total_stamps']).to eq(1)
      end

      it 'creates a MealStamp record' do
        expect { post_stamp }.to change(MealStamp, :count).by(1)
      end

      it 'returns stamp with stamped_at and stamped_by' do
        post_stamp
        expect(json['stamp']['stamped_at']).to be_present
        expect(json['stamp']['stamped_by']).to eq('Ana Ionescu')
      end

      it 'returns attendee first_name and last_name' do
        post_stamp
        expect(json['attendee']).to include('first_name' => 'Ion', 'last_name' => 'Popescu')
      end
    end

    context 'second stamp (seconds)' do
      before { create(:meal_stamp, attendee: attendee, ticket_meal_slot: slot, stamped_by_user_id: admin.id) }

      it 'returns 200 with already_stamped: true and total_stamps: 2' do
        post_stamp
        expect(response).to have_http_status(:ok)
        expect(json['already_stamped']).to be(true)
        expect(json['total_stamps']).to eq(2)
      end

      it 'creates another MealStamp record' do
        expect { post_stamp }.to change(MealStamp, :count).by(1)
      end
    end
  end
  ```

- [ ] **Step 2: Run to confirm failure**

  ```bash
  bundle exec rspec spec/requests/api/v1/scan/meal_stamps_spec.rb --no-color 2>&1 | tail -5
  ```

  Expected: routing error or `AbstractController::ActionNotFound`.

- [ ] **Step 3: Implement the controller**

  Create `app/controllers/api/v1/scan/meal_stamps_controller.rb`:

  ```ruby
  # frozen_string_literal: true

  module Api
    module V1
      module Scan
        class MealStampsController < ActionController::API
          include Authenticatable

          before_action :authenticate_user!
          before_action { require_permission!(:can_check_in_attendees) }

          def create
            qr_code   = params[:qr_code]
            meal_type = params[:meal_type]
            occurs_on = params[:occurs_on]

            if qr_code.blank? || meal_type.blank? || occurs_on.blank?
              return render json: { error: 'qr_code, meal_type, and occurs_on are required' },
                            status: :unprocessable_content
            end

            attendee = resolve_attendee(qr_code)
            return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless attendee

            slot = attendee.ticket&.ticket_meal_slots&.find do |s|
              s.meal_type == meal_type && s.occurs_on.to_s == occurs_on.to_s
            end

            return render json: { error: 'Not entitled' }, status: :unprocessable_content unless slot

            stamp  = MealStamp.create!(attendee: attendee, ticket_meal_slot: slot,
                                       stamped_by_user_id: current_user.id)
            total  = MealStamp.where(attendee: attendee, ticket_meal_slot: slot).count

            render json: {
              stamp: {
                id:         stamp.id,
                stamped_at: stamp.created_at,
                stamped_by: "#{current_user.first_name} #{current_user.last_name}".strip
              },
              already_stamped: total > 1,
              total_stamps:    total,
              attendee: { id: attendee.id, first_name: attendee.first_name, last_name: attendee.last_name }
            }
          end

          private

            def resolve_attendee(qr_code)
              attendee_id = qr_code.split('-').last.to_i
              attendee    = Attendee.includes(ticket: :ticket_meal_slots).find_by(id: attendee_id)
              return nil unless attendee
              return nil unless attendee.qr_code == qr_code

              attendee
            end
        end
      end
    end
  end
  ```

- [ ] **Step 4: Run specs**

  ```bash
  bundle exec rspec spec/requests/api/v1/scan/meal_stamps_spec.rb --no-color
  ```

  Expected: all examples pass, 0 failures.

- [ ] **Step 5: Commit**

  ```bash
  git add app/controllers/api/v1/scan/meal_stamps_controller.rb \
          spec/requests/api/v1/scan/meal_stamps_spec.rb
  git commit -m "Add POST /scan/meal_stamps endpoint"
  ```

---

## Task 7: Add meal_slots to scan orders response (TDD)

**Files:**
- Modify: `app/controllers/concerns/scan_serialisable.rb`
- Modify: `spec/requests/api/v1/scan/orders_spec.rb`

- [ ] **Step 1: Write failing tests**

  Open `spec/requests/api/v1/scan/orders_spec.rb`. Find the `describe 'GET ...'` block. Add these examples inside it (after the existing examples):

  ```ruby
  context 'meal slots' do
    let(:ticket)    { create(:ticket, event: event) }
    let(:slot_date) { 1.day.from_now.to_date }
    let!(:slot)     { create(:ticket_meal_slot, ticket: ticket, occurs_on: slot_date, meal_type: 'lunch', sort: 1) }

    before do
      first_attendee.update!(ticket: ticket)
    end

    it 'includes meal_slots on each attendee' do
      get_order(order.order_reference)
      attendee_json = json['attendees'].find { |a| a['id'] == first_attendee.id }
      expect(attendee_json['meal_slots']).to be_an(Array)
    end

    it 'includes slot fields and stamp_count: 0 when not yet stamped' do
      get_order(order.order_reference)
      attendee_json = json['attendees'].find { |a| a['id'] == first_attendee.id }
      slot_json = attendee_json['meal_slots'].first
      expect(slot_json).to include(
        'id'          => slot.id,
        'meal_type'   => 'lunch',
        'occurs_on'   => slot_date.to_s,
        'sort'        => 1,
        'stamp_count' => 0
      )
    end

    it 'returns stamp_count: 1 after one stamp' do
      create(:meal_stamp, attendee: first_attendee, ticket_meal_slot: slot, stamped_by_user_id: admin.id)
      get_order(order.order_reference)
      attendee_json = json['attendees'].find { |a| a['id'] == first_attendee.id }
      expect(attendee_json['meal_slots'].first['stamp_count']).to eq(1)
    end

    it 'returns stamp_count: 2 after seconds' do
      create(:meal_stamp, attendee: first_attendee, ticket_meal_slot: slot, stamped_by_user_id: admin.id)
      create(:meal_stamp, attendee: first_attendee, ticket_meal_slot: slot, stamped_by_user_id: admin.id)
      get_order(order.order_reference)
      attendee_json = json['attendees'].find { |a| a['id'] == first_attendee.id }
      expect(attendee_json['meal_slots'].first['stamp_count']).to eq(2)
    end

    it 'returns meal_slots: [] for attendees with no meal slots on their ticket' do
      get_order(order.order_reference)
      attendee_json = json['attendees'].find { |a| a['id'] == second_attendee.id }
      expect(attendee_json['meal_slots']).to eq([])
    end
  end
  ```

- [ ] **Step 2: Run to confirm failure**

  ```bash
  bundle exec rspec spec/requests/api/v1/scan/orders_spec.rb --no-color 2>&1 | grep "Failure\|meal_slots" | head -10
  ```

  Expected: failures — `meal_slots` key missing from attendee JSON.

- [ ] **Step 3: Update ScanSerialisable**

  Open `app/controllers/concerns/scan_serialisable.rb`. Replace the entire file with:

  ```ruby
  # frozen_string_literal: true

  module ScanSerialisable
    private

      def serialise_order(order)
        attendees = if order.association(:attendees).loaded?
                      order.attendees.sort_by(&:id)
                    else
                      order.attendees
                           .includes(:checked_in_by, :meal_stamps,
                                     ticket: [:tickets_translations, :ticket_meal_slots])
                           .order(:id)
                    end
        {
          order_reference: order.order_reference,
          payment_status:  order.payment_status(attendees),
          attendees:       attendees.map { |a| serialise_attendee(a) }
        }
      end

      def serialise_attendee(attendee)
        by = attendee.checked_in_by
        {
          id:            attendee.id,
          first_name:    attendee.first_name,
          last_name:     attendee.last_name,
          email_address: attendee.email_address,
          ticket_name:   attendee.ticket
                         &.tickets_translations
                                 &.find { |t| t.languages_code == 'ro-RO' }
                                 &.name,
          payment_status: attendee.payment_status,
          checked_in:     attendee.checked_in,
          checked_in_at:  attendee.checked_in_at,
          checked_in_by:  by ? "#{by.first_name} #{by.last_name}".strip : nil,
          meal_slots:     serialise_meal_slots(attendee)
        }
      end

      def serialise_meal_slots(attendee)
        slots = attendee.ticket&.ticket_meal_slots || []
        slots.sort_by { |s| [s.occurs_on, s.sort || 0] }.map do |slot|
          stamp_count = attendee.meal_stamps.count { |s| s.ticket_meal_slot_id == slot.id }
          { id: slot.id, meal_type: slot.meal_type, occurs_on: slot.occurs_on, sort: slot.sort,
            stamp_count: stamp_count }
        end
      end
  end
  ```

- [ ] **Step 4: Run the orders spec**

  ```bash
  bundle exec rspec spec/requests/api/v1/scan/orders_spec.rb --no-color
  ```

  Expected: all examples pass, 0 failures.

- [ ] **Step 5: Commit**

  ```bash
  git add app/controllers/concerns/scan_serialisable.rb \
          spec/requests/api/v1/scan/orders_spec.rb
  git commit -m "Add meal_slots with stamp counts to scan orders response"
  ```

---

## Task 8: Add has_meal_tracking to scan events response (TDD)

**Files:**
- Modify: `app/controllers/api/v1/scan/events_controller.rb`
- Modify: `spec/requests/api/v1/scan/events_spec.rb`

- [ ] **Step 1: Write failing tests**

  Open `spec/requests/api/v1/scan/events_spec.rb`. Add this context inside the `describe 'filtering and sorting'` block (or at the end of the top-level describe):

  ```ruby
  describe 'has_meal_tracking field' do
    let!(:tracked_event) do
      create(:event, status: :live, start_date: 3.days.from_now, end_date: 5.days.from_now)
    end
    let!(:untracked_event) do
      create(:event, status: :live, start_date: 4.days.from_now, end_date: 6.days.from_now)
    end

    before do
      ticket_with_slots = create(:ticket, event: tracked_event)
      create(:ticket_meal_slot, ticket: ticket_with_slots, occurs_on: 3.days.from_now, meal_type: 'lunch')
    end

    it 'returns has_meal_tracking: true for events with meal slots' do
      get '/api/v1/scan/events', headers: auth_header(admin)
      event_json = json.find { |e| e['slug'] == tracked_event.slug }
      expect(event_json['has_meal_tracking']).to be(true)
    end

    it 'returns has_meal_tracking: false for events without meal slots' do
      get '/api/v1/scan/events', headers: auth_header(admin)
      event_json = json.find { |e| e['slug'] == untracked_event.slug }
      expect(event_json['has_meal_tracking']).to be(false)
    end
  end
  ```

- [ ] **Step 2: Run to confirm failure**

  ```bash
  bundle exec rspec spec/requests/api/v1/scan/events_spec.rb --no-color 2>&1 | grep "Failure\|has_meal" | head -5
  ```

  Expected: `has_meal_tracking` key missing.

- [ ] **Step 3: Update the events controller**

  Replace `app/controllers/api/v1/scan/events_controller.rb` with:

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
            events = Event.upcoming.order(:start_date)
                          .includes(:events_translations, tickets: :ticket_meal_slots)
            render json: events.map { |e| serialise_event(e, lang) }
          end

          private

            def serialise_event(event, lang)
              translation = event.events_translations.find { |t| t.languages_code == lang } ||
                            event.events_translations.find { |t| t.languages_code == 'ro-RO' } ||
                            event.events_translations.first
              {
                name:              translation&.name,
                slug:              event.slug,
                has_meal_tracking: event.tickets.any? { |t| t.ticket_meal_slots.any? }
              }
            end
        end
      end
    end
  end
  ```

- [ ] **Step 4: Run events spec**

  ```bash
  bundle exec rspec spec/requests/api/v1/scan/events_spec.rb --no-color
  ```

  Expected: all examples pass, 0 failures.

- [ ] **Step 5: Run full suite**

  ```bash
  bundle exec rspec --no-color 2>&1 | grep -E "examples|failures"
  ```

  Expected: 0 failures.

- [ ] **Step 6: Commit**

  ```bash
  git add app/controllers/api/v1/scan/events_controller.rb \
          spec/requests/api/v1/scan/events_spec.rb
  git commit -m "Add has_meal_tracking to scan events response"
  ```

---

## Implementation Complete

```bash
bundle exec rspec --no-color 2>&1 | grep -E "examples|failures"
```

Expected: 0 failures.

**Directus setup (manual):** Expose `ticket_meal_slots` as a related collection on `tickets` in Directus so admins can add/edit meal slots when configuring a ticket. No Directus changes needed for `meal_stamps`.
