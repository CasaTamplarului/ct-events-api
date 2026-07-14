# Event Teams Real-Time Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Broadcast all team mutations (create, update, delete, score change) over Action Cable so every connected admin/volunteer sees the scoreboard update in real time.

**Architecture:** Follows the existing `QaQuestionsChannel` + `QaBroadcastable` pattern exactly — one channel that streams from a key named `event_teams_#{event_slug}`, one broadcastable concern included in both team controllers, broadcast calls added after each successful write.

**Tech Stack:** Rails 7.1 Action Cable (test adapter in test env), RSpec with `ActionCable::TestHelper`

## Global Constraints

- `# frozen_string_literal: true` on every new Ruby file
- Stream key format: `event_teams_#{event_slug}` — exact string, used in channel, concern, and specs
- Channel rejects on: blank `event_slug`, unknown event slug, nil `current_user`, user without `can_manage_teams`
- Broadcast payload keys are symbols (test adapter stores them as-is — no JSON round-trip in test env)
- `score_after` does NOT appear in the broadcast entry payload — only in the REST response
- No changes to `config/cable.yml`, `ApplicationCable::Connection`, or routes
- TDD: write failing test first, implement, verify pass
- Commits in imperative mood, English

---

### Task 1: Channel + Broadcastable Concern

**Files:**
- Create: `app/channels/event_teams_channel.rb`
- Create: `app/controllers/concerns/event_team_broadcastable.rb`
- Create: `spec/channels/event_teams_channel_spec.rb`

**Interfaces:**
- Produces:
  - `EventTeamsChannel` — Action Cable channel, subscribes with `{ event_slug: }` param
  - `EventTeamBroadcastable` — concern with four private methods:
    - `broadcast_team_created(team)` — broadcasts `{ type: :team_created, team: {...} }`
    - `broadcast_team_updated(team)` — broadcasts `{ type: :team_updated, team: {...} }`
    - `broadcast_team_deleted(team)` — broadcasts `{ type: :team_deleted, team_id: team.id }`
    - `broadcast_score_updated(team, entry)` — broadcasts `{ type: :score_updated, team: {...}, entry: {...} }`

---

- [ ] **Step 1: Write the failing channel spec**

Create `spec/channels/event_teams_channel_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EventTeamsChannel, type: :channel do
  let(:admin) { create(:user, role: 'admin') }
  let(:volunteer) { create(:user, role: 'volunteer') }
  let(:attendee) { create(:user, role: 'attendee') }
  let(:event) { create(:event, slug: 'test-event-teams') }

  context 'when user is admin' do
    before { stub_connection current_user: admin }

    it 'subscribes and streams from the event channel' do
      subscribe event_slug: event.slug
      expect(subscription).to be_confirmed
      expect(streams).to include("event_teams_#{event.slug}")
    end
  end

  context 'when user is volunteer' do
    before { stub_connection current_user: volunteer }

    it 'subscribes successfully' do
      subscribe event_slug: event.slug
      expect(subscription).to be_confirmed
    end
  end

  context 'rejection cases' do
    before { stub_connection current_user: admin }

    it 'rejects when event_slug is blank' do
      subscribe event_slug: ''
      expect(subscription).to be_rejected
    end

    it 'rejects when event does not exist' do
      subscribe event_slug: 'no-such-event'
      expect(subscription).to be_rejected
    end
  end

  context 'when user lacks permission' do
    it 'rejects when current_user is nil' do
      stub_connection current_user: nil
      subscribe event_slug: event.slug
      expect(subscription).to be_rejected
    end

    it 'rejects when role is attendee' do
      stub_connection current_user: attendee
      subscribe event_slug: event.slug
      expect(subscription).to be_rejected
    end
  end
end
```

- [ ] **Step 2: Run the spec — verify it fails**

```bash
bundle exec rspec spec/channels/event_teams_channel_spec.rb
```

Expected: all examples fail with `uninitialized constant EventTeamsChannel`.

- [ ] **Step 3: Create the channel**

Create `app/channels/event_teams_channel.rb`:

```ruby
# frozen_string_literal: true

class EventTeamsChannel < ApplicationCable::Channel
  def subscribed
    event_slug = params[:event_slug].to_s.strip
    return reject if event_slug.blank?
    return reject unless Event.exists?(slug: event_slug)
    return reject unless current_user&.can?(:can_manage_teams)

    stream_from "event_teams_#{event_slug}"
  end
end
```

- [ ] **Step 4: Run the channel spec — verify it passes**

```bash
bundle exec rspec spec/channels/event_teams_channel_spec.rb
```

Expected: 6 examples, 0 failures.

- [ ] **Step 5: Create the broadcastable concern**

Create `app/controllers/concerns/event_team_broadcastable.rb`:

```ruby
# frozen_string_literal: true

module EventTeamBroadcastable
  extend ActiveSupport::Concern

  private

    def broadcast_team_created(team)
      ActionCable.server.broadcast(
        "event_teams_#{team.event.slug}",
        { type: :team_created, team: broadcast_team_json(team) }
      )
    end

    def broadcast_team_updated(team)
      ActionCable.server.broadcast(
        "event_teams_#{team.event.slug}",
        { type: :team_updated, team: broadcast_team_json(team) }
      )
    end

    def broadcast_team_deleted(team)
      ActionCable.server.broadcast(
        "event_teams_#{team.event.slug}",
        { type: :team_deleted, team_id: team.id }
      )
    end

    def broadcast_score_updated(team, entry)
      ActionCable.server.broadcast(
        "event_teams_#{team.event.slug}",
        {
          type: :score_updated,
          team: broadcast_team_json(team),
          entry: broadcast_entry_json(entry)
        }
      )
    end

    def broadcast_team_json(team)
      { id: team.id, name: team.name, icon: team.icon, colour: team.colour, score: team.score }
    end

    def broadcast_entry_json(entry)
      {
        id: entry.id,
        delta: entry.delta,
        added_by: {
          first_name: entry.added_by_user.first_name,
          last_name: entry.added_by_user.last_name
        },
        created_at: entry.created_at
      }
    end
end
```

- [ ] **Step 6: Commit**

```bash
git add app/channels/event_teams_channel.rb \
        app/controllers/concerns/event_team_broadcastable.rb \
        spec/channels/event_teams_channel_spec.rb
git commit -m "feat: EventTeamsChannel and EventTeamBroadcastable concern"
```

---

### Task 2: Wire Broadcasts into Controllers + Request Spec Assertions

**Files:**
- Modify: `app/controllers/api/v1/admin/event_teams_controller.rb`
- Modify: `app/controllers/api/v1/admin/event_team_score_entries_controller.rb`
- Modify: `spec/rails_helper.rb`
- Modify: `spec/requests/api/v1/admin/event_teams_spec.rb`
- Modify: `spec/requests/api/v1/admin/event_team_score_entries_spec.rb`

**Interfaces:**
- Consumes:
  - `EventTeamBroadcastable` from Task 1 — `broadcast_team_created`, `broadcast_team_updated`, `broadcast_team_deleted`, `broadcast_score_updated`
  - Stream key: `event_teams_#{event.slug}`

---

- [ ] **Step 1: Add ActionCable::TestHelper to rails_helper**

In `spec/rails_helper.rb`, add this line inside the `RSpec.configure do |config|` block, after the existing `config.include` lines:

```ruby
config.include ActionCable::TestHelper
```

- [ ] **Step 2: Write failing broadcast assertions for EventTeamsController**

In `spec/requests/api/v1/admin/event_teams_spec.rb`, add the following new `it` blocks — do not remove existing examples. Place each one inside the appropriate existing context block (e.g. alongside the existing create/update/destroy success examples).

```ruby
it 'creates a team and broadcasts team_created' do
  expect {
    post "/api/v1/admin/events/#{event.slug}/teams",
         params: { name: 'Echipa Roșie', icon: '🔥', colour: '#FF5733' },
         headers: headers
  }.to have_broadcasted_to("event_teams_#{event.slug}")
    .with(a_hash_including(type: :team_created))
  expect(response).to have_http_status(:created)
end
```

Find the `PATCH .../teams/:id` success example and add:

```ruby
it 'updates the team and broadcasts team_updated' do
  expect {
    patch "/api/v1/admin/events/#{event.slug}/teams/#{team.id}",
          params: { colour: '#E63946' },
          headers: headers
  }.to have_broadcasted_to("event_teams_#{event.slug}")
    .with(a_hash_including(type: :team_updated))
  expect(response).to have_http_status(:ok)
end
```

Find the `DELETE .../teams/:id` success example and add:

```ruby
it 'deletes the team and broadcasts team_deleted' do
  expect {
    delete "/api/v1/admin/events/#{event.slug}/teams/#{team.id}",
           headers: headers
  }.to have_broadcasted_to("event_teams_#{event.slug}")
    .with(a_hash_including(type: :team_deleted, team_id: team.id))
  expect(response).to have_http_status(:no_content)
end
```

In `spec/requests/api/v1/admin/event_team_score_entries_spec.rb`, find the `POST .../score_entries` success example and add:

```ruby
it 'creates a score entry and broadcasts score_updated' do
  expect {
    post "/api/v1/admin/events/#{event.slug}/teams/#{team.id}/score_entries",
         params: { delta: 5 },
         headers: headers
  }.to have_broadcasted_to("event_teams_#{event.slug}")
    .with(a_hash_including(type: :score_updated))
  expect(response).to have_http_status(:created)
end
```

- [ ] **Step 3: Run the new specs — verify they fail**

```bash
bundle exec rspec spec/requests/api/v1/admin/event_teams_spec.rb \
                  spec/requests/api/v1/admin/event_team_score_entries_spec.rb \
                  --tag '~@skip'
```

Expected: the new broadcast examples fail with `expected to have broadcasted ... but no broadcasts were made`.

- [ ] **Step 4: Include the concern and add broadcast calls to EventTeamsController**

Replace the full file `app/controllers/api/v1/admin/event_teams_controller.rb`:

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Admin
      class EventTeamsController < ActionController::API
        include Authenticatable
        include EventTeamBroadcastable

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
            broadcast_team_created(team)
          else
            render json: { error: team.errors.full_messages.first }, status: :unprocessable_content
          end
        end

        def update
          if @team.update(team_params)
            render json: team_json(@team)
            broadcast_team_updated(@team)
          else
            render json: { error: @team.errors.full_messages.first }, status: :unprocessable_content
          end
        end

        def destroy
          @team.destroy!
          head :no_content
          broadcast_team_deleted(@team)
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

- [ ] **Step 5: Include the concern and add broadcast call to EventTeamScoreEntriesController**

Replace the full file `app/controllers/api/v1/admin/event_team_score_entries_controller.rb`:

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Admin
      class EventTeamScoreEntriesController < ActionController::API
        include Authenticatable
        include EventTeamBroadcastable

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
            @team.increment!(:score, delta) # rubocop:disable Rails/SkipsModelValidations
          end

          render json: entry_json(entry, score_after: @team.reload.score), status: :created
          broadcast_score_updated(@team, entry)
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

- [ ] **Step 6: Run all event teams specs — verify they pass**

```bash
bundle exec rspec spec/channels/event_teams_channel_spec.rb \
                  spec/requests/api/v1/admin/event_teams_spec.rb \
                  spec/requests/api/v1/admin/event_team_score_entries_spec.rb
```

Expected: all examples pass, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add spec/rails_helper.rb \
        app/controllers/api/v1/admin/event_teams_controller.rb \
        app/controllers/api/v1/admin/event_team_score_entries_controller.rb \
        spec/requests/api/v1/admin/event_teams_spec.rb \
        spec/requests/api/v1/admin/event_team_score_entries_spec.rb
git commit -m "feat: broadcast team mutations over Action Cable"
```
