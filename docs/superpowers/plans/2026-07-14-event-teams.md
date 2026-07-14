# Event Teams Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow admin and volunteer users to create and manage teams within an event, each with an optional name, emoji icon, and colour, plus a scored history of signed deltas.

**Architecture:** Two new tables — `event_teams` (team metadata + denormalised score) and `event_team_score_entries` (append-only delta log). Two focused controllers under `api/v1/admin`, both gated by a new `can_manage_teams` permission added to the `admin` and `volunteer` roles. Score is kept in sync by `increment!` inside a transaction on every entry insert.

**Tech Stack:** Rails 7.1 API-only, PostgreSQL, RSpec + FactoryBot, existing `Authenticatable` concern + `JwtService`.

## Global Constraints

- Migration version: `ActiveRecord::Migration[7.1]`
- Migration timestamps: `20260714100000` (event_teams), `20260714110000` (event_team_score_entries)
- New permission key: `:can_manage_teams` — must be `true` for `admin` and `volunteer`, `false` for all other roles
- At least one of `name`, `icon`, `colour` required on a team — validated at model layer, error message: `"At least one of name, icon, or colour must be present"`
- `delta` must be a non-zero integer — error: `"Delta must be a non-zero integer"`
- Route param for event: `event_slug`; for team inside score-entries controller: `event_team_id`
- `score` column: integer, not null, default 0 — kept in sync via `increment!(:score, delta)` inside `ActiveRecord::Base.transaction`
- All routes namespaced under `/api/v1/admin/events/:event_slug/teams`
- No production DB credentials in any file

---

### Task 1: Migrations, Models, Permission, Factories, Model Specs

**Files:**
- Create: `db/migrate/20260714100000_create_event_teams.rb`
- Create: `db/migrate/20260714110000_create_event_team_score_entries.rb`
- Create: `app/models/event_team.rb`
- Create: `app/models/event_team_score_entry.rb`
- Modify: `app/models/event.rb` — add `has_many :event_teams`
- Modify: `app/models/user.rb` — add `can_manage_teams` to ROLE_PERMISSIONS
- Create: `spec/factories/event_teams.rb`
- Create: `spec/factories/event_team_score_entries.rb`
- Create: `spec/models/event_team_spec.rb`

**Interfaces:**
- Produces: `EventTeam` model with `belongs_to :event`, `has_many :score_entries`, `at_least_one_field_present` validation, `score` integer default 0
- Produces: `EventTeamScoreEntry` model with `belongs_to :event_team`, `belongs_to :added_by_user, class_name: 'User'`, validates `delta` non-zero integer
- Produces: `User.can?(:can_manage_teams)` returns `true` for admin and volunteer

- [ ] **Step 1: Write failing model spec**

```ruby
# spec/models/event_team_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EventTeam, type: :model do
  let(:event) { create(:event) }

  it 'is valid with only a name' do
    expect(build(:event_team, event: event, name: 'Red', icon: nil, colour: nil)).to be_valid
  end

  it 'is valid with only an icon' do
    expect(build(:event_team, event: event, name: nil, icon: '🔥', colour: nil)).to be_valid
  end

  it 'is valid with only a colour' do
    expect(build(:event_team, event: event, name: nil, icon: nil, colour: '#FF5733')).to be_valid
  end

  it 'is invalid when all fields are blank' do
    team = build(:event_team, event: event, name: nil, icon: nil, colour: nil)
    expect(team).not_to be_valid
    expect(team.errors[:base]).to include('At least one of name, icon, or colour must be present')
  end

  it 'defaults score to 0' do
    team = create(:event_team, event: event, name: 'Red')
    expect(team.score).to eq(0)
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```bash
bundle exec rspec spec/models/event_team_spec.rb
```

Expected: 5 failures — `EventTeam` uninitialized constant / table doesn't exist.

- [ ] **Step 3: Create migration for event_teams**

```ruby
# db/migrate/20260714100000_create_event_teams.rb
# frozen_string_literal: true

class CreateEventTeams < ActiveRecord::Migration[7.1]
  def change
    create_table :event_teams do |t|
      t.references :event, null: false, foreign_key: true
      t.string :name
      t.string :icon
      t.string :colour
      t.integer :score, null: false, default: 0
      t.timestamps
    end
  end
end
```

- [ ] **Step 4: Create migration for event_team_score_entries**

```ruby
# db/migrate/20260714110000_create_event_team_score_entries.rb
# frozen_string_literal: true

class CreateEventTeamScoreEntries < ActiveRecord::Migration[7.1]
  def change
    create_table :event_team_score_entries do |t|
      t.references :event_team, null: false, foreign_key: true
      t.integer :delta, null: false
      t.references :added_by_user, null: false, foreign_key: { to_table: :users }
      t.datetime :created_at, null: false
    end
  end
end
```

- [ ] **Step 5: Run migrations**

```bash
bin/rails db:migrate
```

Expected: two new tables created.

- [ ] **Step 6: Create factories**

```ruby
# spec/factories/event_teams.rb
# frozen_string_literal: true

FactoryBot.define do
  factory :event_team do
    association :event
    name { 'Team Red' }
    icon { nil }
    colour { nil }
    score { 0 }
  end
end
```

```ruby
# spec/factories/event_team_score_entries.rb
# frozen_string_literal: true

FactoryBot.define do
  factory :event_team_score_entry do
    association :event_team
    association :added_by_user, factory: :user
    delta { 5 }
  end
end
```

- [ ] **Step 7: Create EventTeam model**

```ruby
# app/models/event_team.rb
# frozen_string_literal: true

class EventTeam < ApplicationRecord
  belongs_to :event
  has_many :score_entries, class_name: 'EventTeamScoreEntry', dependent: :destroy

  validate :at_least_one_field_present

  private

    def at_least_one_field_present
      return if name.present? || icon.present? || colour.present?

      errors.add(:base, 'At least one of name, icon, or colour must be present')
    end
end
```

- [ ] **Step 8: Create EventTeamScoreEntry model**

```ruby
# app/models/event_team_score_entry.rb
# frozen_string_literal: true

class EventTeamScoreEntry < ApplicationRecord
  belongs_to :event_team
  belongs_to :added_by_user, class_name: 'User'

  validates :delta, presence: true, numericality: { only_integer: true, other_than: 0 }
end
```

- [ ] **Step 9: Add has_many to Event model**

In `app/models/event.rb`, add after `has_many :qa_sessions, dependent: :destroy`:

```ruby
has_many :event_teams, dependent: :destroy
```

- [ ] **Step 10: Add can_manage_teams to ROLE_PERMISSIONS in User model**

In `app/models/user.rb`, update `ROLE_PERMISSIONS`:

```ruby
ROLE_PERMISSIONS = {
  'admin' => { can_check_in_attendees: true, can_scan_food_stamp: true, can_send_push_notifications: true,
               can_manage_bracelets: true, can_send_emails: true, can_send_whatsapp: true,
               can_manage_teams: true }.freeze,
  'volunteer' => { can_check_in_attendees: true, can_scan_food_stamp: true, can_send_push_notifications: false,
                   can_manage_bracelets: false, can_send_emails: false, can_send_whatsapp: false,
                   can_manage_teams: true }.freeze,
  'attendee' => { can_check_in_attendees: false, can_scan_food_stamp: false, can_send_push_notifications: false,
                  can_manage_bracelets: false, can_send_emails: false, can_send_whatsapp: false,
                  can_manage_teams: false }.freeze,
  'leader' => { can_check_in_attendees: false, can_scan_food_stamp: false, can_send_push_notifications: false,
                can_manage_bracelets: false, can_send_emails: false, can_send_whatsapp: false,
                can_manage_teams: false }.freeze,
  'staff' => { can_check_in_attendees: false, can_scan_food_stamp: false, can_send_push_notifications: false,
               can_manage_bracelets: false, can_send_emails: false, can_send_whatsapp: false,
               can_manage_teams: false }.freeze
}.freeze
```

- [ ] **Step 11: Run spec to verify it passes**

```bash
bundle exec rspec spec/models/event_team_spec.rb
```

Expected: 5 examples, 0 failures.

- [ ] **Step 12: Run rubocop**

```bash
bundle exec rubocop app/models/event_team.rb app/models/event_team_score_entry.rb app/models/event.rb app/models/user.rb
```

Fix any offenses.

- [ ] **Step 13: Commit**

```bash
git add db/migrate/20260714100000_create_event_teams.rb \
        db/migrate/20260714110000_create_event_team_score_entries.rb \
        db/schema.rb \
        app/models/event_team.rb \
        app/models/event_team_score_entry.rb \
        app/models/event.rb \
        app/models/user.rb \
        spec/factories/event_teams.rb \
        spec/factories/event_team_score_entries.rb \
        spec/models/event_team_spec.rb
git commit -m "feat: event_teams + score_entries tables, models, can_manage_teams permission"
```

---

### Task 2: Teams CRUD Controller, Routes, Request Specs

**Files:**
- Create: `app/controllers/api/v1/admin/event_teams_controller.rb`
- Modify: `config/routes.rb`
- Create: `spec/requests/api/v1/admin/event_teams_spec.rb`

**Interfaces:**
- Consumes: `EventTeam` model from Task 1; `Event.find_by(slug:)`; `require_permission!(:can_manage_teams)` from `Authenticatable`
- Produces: `GET/POST/PATCH/DELETE /api/v1/admin/events/:event_slug/teams(/:id)` endpoints returning `{ id, name, icon, colour, score }`

- [ ] **Step 1: Write failing request spec**

```ruby
# spec/requests/api/v1/admin/event_teams_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Event Teams' do
  let(:admin)     { create(:user, role: 'admin') }
  let(:volunteer) { create(:user, role: 'volunteer') }
  let(:attendee)  { create(:user, role: 'attendee') }
  let(:event)     { create(:event) }

  def headers(user)
    { 'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{JwtService.encode(user.id)}" }
  end

  describe 'POST /api/v1/admin/events/:event_slug/teams' do
    it 'creates a team with name only' do
      post "/api/v1/admin/events/#{event.slug}/teams",
           params: { name: 'Echipa Roșie' }.to_json,
           headers: headers(admin)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['name']).to eq('Echipa Roșie')
      expect(body['icon']).to be_nil
      expect(body['colour']).to be_nil
      expect(body['score']).to eq(0)
    end

    it 'creates a team with icon only' do
      post "/api/v1/admin/events/#{event.slug}/teams",
           params: { icon: '🔥' }.to_json,
           headers: headers(admin)
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)['icon']).to eq('🔥')
    end

    it 'creates a team with all fields' do
      post "/api/v1/admin/events/#{event.slug}/teams",
           params: { name: 'Red', icon: '🔥', colour: '#FF5733' }.to_json,
           headers: headers(admin)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['name']).to eq('Red')
      expect(body['colour']).to eq('#FF5733')
    end

    it 'returns 422 when all fields are blank' do
      post "/api/v1/admin/events/#{event.slug}/teams",
           params: {}.to_json,
           headers: headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to include('At least one of name, icon, or colour')
    end

    it 'allows volunteers' do
      post "/api/v1/admin/events/#{event.slug}/teams",
           params: { name: 'Blue' }.to_json,
           headers: headers(volunteer)
      expect(response).to have_http_status(:created)
    end

    it 'rejects attendees with 403' do
      post "/api/v1/admin/events/#{event.slug}/teams",
           params: { name: 'Blue' }.to_json,
           headers: headers(attendee)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 404 for unknown event slug' do
      post '/api/v1/admin/events/no-such-event/teams',
           params: { name: 'X' }.to_json,
           headers: headers(admin)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v1/admin/events/:event_slug/teams' do
    it 'returns all teams ordered by created_at ascending' do
      create(:event_team, event: event, name: 'Red',  score: 5)
      create(:event_team, event: event, name: 'Blue', score: 12)

      get "/api/v1/admin/events/#{event.slug}/teams",
          headers: headers(admin)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.size).to eq(2)
      expect(body.map { |t| t['name'] }).to eq(%w[Red Blue])
      expect(body.first['score']).to eq(5)
    end

    it 'returns empty array when event has no teams' do
      get "/api/v1/admin/events/#{event.slug}/teams",
          headers: headers(admin)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end
  end

  describe 'PATCH /api/v1/admin/events/:event_slug/teams/:id' do
    let(:team) { create(:event_team, event: event, name: 'Red') }

    it 'updates name and icon' do
      patch "/api/v1/admin/events/#{event.slug}/teams/#{team.id}",
            params: { name: 'Blue', icon: '💧' }.to_json,
            headers: headers(admin)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['name']).to eq('Blue')
      expect(body['icon']).to eq('💧')
    end

    it 'returns 404 for a team belonging to another event' do
      other_team = create(:event_team, name: 'Other')
      patch "/api/v1/admin/events/#{event.slug}/teams/#{other_team.id}",
            params: { name: 'X' }.to_json,
            headers: headers(admin)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /api/v1/admin/events/:event_slug/teams/:id' do
    let!(:team) { create(:event_team, event: event, name: 'Red') }

    it 'deletes the team and returns 204' do
      delete "/api/v1/admin/events/#{event.slug}/teams/#{team.id}",
             headers: headers(admin)
      expect(response).to have_http_status(:no_content)
      expect(EventTeam.exists?(team.id)).to be false
    end

    it 'deletes associated score entries' do
      create(:event_team_score_entry, event_team: team, delta: 5, added_by_user: admin)
      delete "/api/v1/admin/events/#{event.slug}/teams/#{team.id}",
             headers: headers(admin)
      expect(EventTeamScoreEntry.where(event_team_id: team.id)).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```bash
bundle exec rspec spec/requests/api/v1/admin/event_teams_spec.rb
```

Expected: routing errors — routes and controller not yet defined.

- [ ] **Step 3: Create EventTeamsController**

```ruby
# app/controllers/api/v1/admin/event_teams_controller.rb
# frozen_string_literal: true

module Api
  module V1
    module Admin
      class EventTeamsController < ActionController::API
        include Authenticatable

        before_action :authenticate_user!
        before_action { require_permission!(:can_manage_teams) }
        before_action :load_event
        before_action :load_team, only: %i[update destroy]

        def index
          teams = @event.event_teams.order(created_at: :asc)
          render json: teams.map { |t| team_json(t) }
        end

        def create
          team = @event.event_teams.new(team_params)
          if team.save
            render json: team_json(team), status: :created
          else
            render json: { error: team.errors.full_messages.first }, status: :unprocessable_content
          end
        end

        def update
          if @team.update(team_params)
            render json: team_json(@team)
          else
            render json: { error: @team.errors.full_messages.first }, status: :unprocessable_content
          end
        end

        def destroy
          @team.destroy!
          head :no_content
        end

        private

          def load_event
            @event = Event.find_by(slug: params[:event_slug])
            render json: { error: 'Event not found' }, status: :not_found unless @event
          end

          def load_team
            @team = @event.event_teams.find_by(id: params[:id])
            render json: { error: 'Team not found' }, status: :not_found unless @team
          end

          def team_params
            params.permit(:name, :icon, :colour)
          end

          def team_json(team)
            {
              id: team.id,
              name: team.name,
              icon: team.icon,
              colour: team.colour,
              score: team.score
            }
          end
      end
    end
  end
end
```

- [ ] **Step 4: Add routes for event_teams (without score_entries — Task 3 adds the nesting)**

In `config/routes.rb`, inside the `namespace :admin` block, add a new `scope '/events/:event_slug'` block after the existing one:

```ruby
scope '/events/:event_slug' do
  resources :event_teams, path: 'teams', only: %i[index create update destroy]
end
```

The full `namespace :admin` block now looks like:

```ruby
namespace :admin do
  resources :push_notifications, only: :create
  resources :emails, only: %i[index create show] do
    collection { get :variables }
  end
  resources :whatsapp_templates,  only: %i[index create]
  resources :whatsapp_broadcasts, only: %i[index create]
  scope '/events/:event_slug' do
    get  'qa_sessions', to: 'qa_sessions#index', as: 'admin_event_qa_sessions'
    post 'qa_sessions', to: 'qa_sessions#create'
  end
  scope '/qa_sessions/:code' do
    patch  '/',             to: 'qa_sessions#update', as: 'admin_qa_session'
    delete '/',             to: 'qa_sessions#destroy'
    get    'questions',     to: 'qa_questions#index',   as: 'admin_qa_session_questions'
    delete 'questions/:id', to: 'qa_questions#destroy', as: 'admin_qa_session_question'
  end
  scope '/events/:event_slug' do
    resources :event_teams, path: 'teams', only: %i[index create update destroy]
  end
end
```

- [ ] **Step 5: Run spec to verify it passes**

```bash
bundle exec rspec spec/requests/api/v1/admin/event_teams_spec.rb
```

Expected: all examples pass, 0 failures.

- [ ] **Step 6: Run rubocop**

```bash
bundle exec rubocop app/controllers/api/v1/admin/event_teams_controller.rb config/routes.rb
```

Fix any offenses.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/api/v1/admin/event_teams_controller.rb \
        config/routes.rb \
        spec/requests/api/v1/admin/event_teams_spec.rb
git commit -m "feat: event teams CRUD — index, create, update, destroy"
```

---

### Task 3: Score Entries Controller, Routes, Request Specs

**Files:**
- Create: `app/controllers/api/v1/admin/event_team_score_entries_controller.rb`
- Modify: `config/routes.rb` — nest `score_entries` under `event_teams`
- Create: `spec/requests/api/v1/admin/event_team_score_entries_spec.rb`

**Interfaces:**
- Consumes: `EventTeam` (Task 1), `EventTeamScoreEntry` (Task 1); route param `event_team_id` (from nested resource); `EventTeam#increment!(:score, delta)` to keep score in sync
- Produces: `POST /api/v1/admin/events/:event_slug/teams/:event_team_id/score_entries` → `{ id, delta, score_after, added_by: { first_name, last_name }, created_at }`
- Produces: `GET /api/v1/admin/events/:event_slug/teams/:event_team_id/score_entries` → array of `{ id, delta, added_by, created_at }` (no `score_after`)

- [ ] **Step 1: Write failing request spec**

```ruby
# spec/requests/api/v1/admin/event_team_score_entries_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Event Team Score Entries' do
  let(:admin)   { create(:user, role: 'admin') }
  let(:event)   { create(:event) }
  let(:team)    { create(:event_team, event: event, name: 'Red', score: 10) }
  let(:headers) do
    { 'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{JwtService.encode(admin.id)}" }
  end

  describe 'POST /api/v1/admin/events/:event_slug/teams/:event_team_id/score_entries' do
    it 'adds a positive delta and reflects it in score_after and team score' do
      post "/api/v1/admin/events/#{event.slug}/teams/#{team.id}/score_entries",
           params: { delta: 5 }.to_json,
           headers: headers
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['delta']).to eq(5)
      expect(body['score_after']).to eq(15)
      expect(team.reload.score).to eq(15)
    end

    it 'subtracts with a negative delta' do
      post "/api/v1/admin/events/#{event.slug}/teams/#{team.id}/score_entries",
           params: { delta: -3 }.to_json,
           headers: headers
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['delta']).to eq(-3)
      expect(body['score_after']).to eq(7)
      expect(team.reload.score).to eq(7)
    end

    it 'returns 422 for a zero delta' do
      post "/api/v1/admin/events/#{event.slug}/teams/#{team.id}/score_entries",
           params: { delta: 0 }.to_json,
           headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to eq('Delta must be a non-zero integer')
    end

    it 'returns 422 when delta is missing' do
      post "/api/v1/admin/events/#{event.slug}/teams/#{team.id}/score_entries",
           params: {}.to_json,
           headers: headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'records the current user as added_by' do
      post "/api/v1/admin/events/#{event.slug}/teams/#{team.id}/score_entries",
           params: { delta: 1 }.to_json,
           headers: headers
      body = JSON.parse(response.body)
      expect(body['added_by']['first_name']).to eq(admin.first_name)
      expect(body['added_by']['last_name']).to eq(admin.last_name)
    end

    it 'returns 404 for unknown team' do
      post "/api/v1/admin/events/#{event.slug}/teams/99999/score_entries",
           params: { delta: 1 }.to_json,
           headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it 'rejects attendees with 403' do
      attendee = create(:user, role: 'attendee')
      post "/api/v1/admin/events/#{event.slug}/teams/#{team.id}/score_entries",
           params: { delta: 1 }.to_json,
           headers: { 'Content-Type' => 'application/json',
                      'Authorization' => "Bearer #{JwtService.encode(attendee.id)}" }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /api/v1/admin/events/:event_slug/teams/:event_team_id/score_entries' do
    it 'returns score history in chronological order without score_after' do
      create(:event_team_score_entry, event_team: team, delta: 10, added_by_user: admin)
      create(:event_team_score_entry, event_team: team, delta: -4, added_by_user: admin)

      get "/api/v1/admin/events/#{event.slug}/teams/#{team.id}/score_entries",
          headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.size).to eq(2)
      expect(body.map { |e| e['delta'] }).to eq([10, -4])
      expect(body.first.key?('score_after')).to be false
      expect(body.first['added_by']['first_name']).to eq(admin.first_name)
    end

    it 'returns empty array when no entries exist' do
      get "/api/v1/admin/events/#{event.slug}/teams/#{team.id}/score_entries",
          headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end
  end
end
```

- [ ] **Step 2: Run spec to verify it fails**

```bash
bundle exec rspec spec/requests/api/v1/admin/event_team_score_entries_spec.rb
```

Expected: routing errors — controller and nested routes not yet defined.

- [ ] **Step 3: Create EventTeamScoreEntriesController**

```ruby
# app/controllers/api/v1/admin/event_team_score_entries_controller.rb
# frozen_string_literal: true

module Api
  module V1
    module Admin
      class EventTeamScoreEntriesController < ActionController::API
        include Authenticatable

        before_action :authenticate_user!
        before_action { require_permission!(:can_manage_teams) }
        before_action :load_team

        def index
          entries = @team.score_entries
                         .includes(:added_by_user)
                         .order(created_at: :asc)
          render json: entries.map { |e| entry_json(e) }
        end

        def create
          delta = params[:delta].to_i

          if delta.zero?
            return render json: { error: 'Delta must be a non-zero integer' },
                          status: :unprocessable_content
          end

          entry = nil
          ActiveRecord::Base.transaction do
            entry = @team.score_entries.create!(delta: delta, added_by_user: current_user)
            @team.increment!(:score, delta)
          end

          render json: entry_json(entry, score_after: @team.reload.score), status: :created
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.message }, status: :unprocessable_content
        end

        private

          def load_team
            event = Event.find_by(slug: params[:event_slug])
            return render json: { error: 'Event not found' }, status: :not_found unless event

            @team = event.event_teams.find_by(id: params[:event_team_id])
            render json: { error: 'Team not found' }, status: :not_found unless @team
          end

          def entry_json(entry, score_after: nil)
            hash = {
              id: entry.id,
              delta: entry.delta,
              added_by: {
                first_name: entry.added_by_user.first_name,
                last_name: entry.added_by_user.last_name
              },
              created_at: entry.created_at
            }
            hash[:score_after] = score_after unless score_after.nil?
            hash
          end
      end
    end
  end
end
```

- [ ] **Step 4: Update routes — nest score_entries under event_teams**

Replace the `scope '/events/:event_slug'` block added in Task 2 with:

```ruby
scope '/events/:event_slug' do
  resources :event_teams, path: 'teams', only: %i[index create update destroy] do
    resources :score_entries, only: %i[index create],
                              controller: 'event_team_score_entries'
  end
end
```

- [ ] **Step 5: Run spec to verify it passes**

```bash
bundle exec rspec spec/requests/api/v1/admin/event_team_score_entries_spec.rb
```

Expected: all examples pass, 0 failures.

- [ ] **Step 6: Run full test suite**

```bash
bundle exec rspec
```

Expected: 0 new failures (2 pre-existing `push_notification` failures are unrelated).

- [ ] **Step 7: Run rubocop**

```bash
bundle exec rubocop app/controllers/api/v1/admin/event_team_score_entries_controller.rb config/routes.rb
```

Fix any offenses.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/api/v1/admin/event_team_score_entries_controller.rb \
        config/routes.rb \
        spec/requests/api/v1/admin/event_team_score_entries_spec.rb
git commit -m "feat: event team score entries — create and list, delta keeps team score in sync"
```

Also run both DB migrations in production after deployment:
```bash
DATABASE_PORT=5433 bin/rails db:migrate
```
