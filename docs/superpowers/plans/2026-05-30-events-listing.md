# Events Listing Endpoint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a paginated, filterable `/events/listing` endpoint and bump the homepage upcoming/past endpoints from 6 to 10 events with explicit ordering.

**Architecture:** Five new scopes on `Event` (`by_filter`, `by_keyword`, `by_year`, `by_pricing`, `sorted_for`) are chained in a new `ListingController`. Pagination is implemented inline with `offset`/`limit` and a subquery count. The response wraps the existing `ThumbnailEventSerializer` output with a `meta` object.

**Tech Stack:** Rails 7.1 API, PostgreSQL, Alba serializer, RSpec.

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `app/controllers/api/v1/events/upcoming_controller.rb` | Modify | `limit(6)` → `limit(10)`, add `order(start_date: :asc)` |
| `app/controllers/api/v1/events/past_controller.rb` | Modify | `limit(6)` → `limit(10)`, add `order(start_date: :desc)` |
| `spec/requests/api/v1/events/upcoming_spec.rb` | Create | Request specs for homepage upcoming |
| `spec/requests/api/v1/events/past_spec.rb` | Create | Request specs for homepage past |
| `app/models/event.rb` | Modify | Add `by_filter`, `by_keyword`, `by_year`, `by_pricing`, `sorted_for` scopes |
| `spec/models/event_spec.rb` | Modify | Unit tests for each new scope |
| `app/controllers/api/v1/events/listing_controller.rb` | Create | Listing endpoint: parse params, chain scopes, paginate, render |
| `config/routes.rb` | Modify | Add `resources :listing, only: :index` inside `namespace :events` |
| `spec/requests/api/v1/events/listing_spec.rb` | Create | Request specs for listing endpoint |

---

### Task 1: Bump homepage limits and add explicit ordering

**Files:**
- Modify: `app/controllers/api/v1/events/upcoming_controller.rb`
- Modify: `app/controllers/api/v1/events/past_controller.rb`
- Create: `spec/requests/api/v1/events/upcoming_spec.rb`
- Create: `spec/requests/api/v1/events/past_spec.rb`

- [ ] **Step 1: Write failing specs for upcoming and past**

Create `spec/requests/api/v1/events/upcoming_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/:lang/events/upcoming' do
  let(:lang) { 'ro-RO' }

  def create_upcoming(start_days_from_now, name: 'Event')
    event = create(:event, status: :live, start_date: start_days_from_now.days.from_now,
                           end_date: (start_days_from_now + 3).days.from_now)
    create(:events_translation, event: event, languages_code: lang, name: name)
    event
  end

  it 'returns 200' do
    get "/api/v1/#{lang}/events/upcoming"
    expect(response).to have_http_status(:ok)
  end

  it 'returns at most 10 events' do
    11.times { |i| create_upcoming(i + 1) }
    get "/api/v1/#{lang}/events/upcoming"
    expect(json.length).to eq(10)
  end

  it 'returns events sorted by start_date ascending' do
    near  = create_upcoming(2, name: 'Near')
    far   = create_upcoming(20, name: 'Far')

    get "/api/v1/#{lang}/events/upcoming"

    names = json.pluck('name')
    expect(names.index('Near')).to be < names.index('Far')
  end

  it 'returns the next 10 upcoming (not old ones)' do
    past_event = create(:event, status: :live, start_date: 5.days.ago, end_date: 2.days.ago)
    create(:events_translation, event: past_event, languages_code: lang, name: 'Past')
    create_upcoming(5, name: 'Future')

    get "/api/v1/#{lang}/events/upcoming"

    expect(json.pluck('name')).to include('Future')
    expect(json.pluck('name')).not_to include('Past')
  end
end
```

Create `spec/requests/api/v1/events/past_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/:lang/events/past' do
  let(:lang) { 'ro-RO' }

  def create_past(days_ago, name: 'Event')
    event = create(:event, status: :live, start_date: days_ago.days.ago,
                           end_date: (days_ago - 3).days.ago)
    create(:events_translation, event: event, languages_code: lang, name: name)
    event
  end

  it 'returns 200' do
    get "/api/v1/#{lang}/events/past"
    expect(response).to have_http_status(:ok)
  end

  it 'returns at most 10 events' do
    11.times { |i| create_past(i + 5) }
    get "/api/v1/#{lang}/events/past"
    expect(json.length).to eq(10)
  end

  it 'returns events sorted by start_date descending (most recent first)' do
    older  = create_past(30, name: 'Older')
    recent = create_past(5, name: 'Recent')

    get "/api/v1/#{lang}/events/past"

    names = json.pluck('name')
    expect(names.index('Recent')).to be < names.index('Older')
  end

  it 'does not return upcoming events' do
    create_past(5, name: 'Past')
    future = create(:event, status: :live, start_date: 5.days.from_now, end_date: 8.days.from_now)
    create(:events_translation, event: future, languages_code: lang, name: 'Future')

    get "/api/v1/#{lang}/events/past"

    expect(json.pluck('name')).to include('Past')
    expect(json.pluck('name')).not_to include('Future')
  end
end
```

- [ ] **Step 2: Run specs to confirm they fail**

```bash
bundle exec rspec spec/requests/api/v1/events/upcoming_spec.rb spec/requests/api/v1/events/past_spec.rb --format documentation 2>&1 | grep -E "FAILED|returns at most 10|sorted"
```

Expected: the `returns at most 10` and `sorted` tests fail (currently limit is 6, no ordering).

- [ ] **Step 3: Update upcoming controller**

Replace the contents of `app/controllers/api/v1/events/upcoming_controller.rb`:

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Events
      class UpcomingController < ActionController::API
        def index
          events = Event.upcoming.order(start_date: :asc).limit(10)

          render json:
            ThumbnailEventSerializer.new(events, params: { languages_code: params[:languages_code] }).serialize,
                 status: :ok
        end
      end
    end
  end
end
```

- [ ] **Step 4: Update past controller**

Replace the contents of `app/controllers/api/v1/events/past_controller.rb`:

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Events
      class PastController < ActionController::API
        def index
          events = Event.past.order(start_date: :desc).limit(10)

          render json:
            ThumbnailEventSerializer.new(events,
                                         params: { languages_code: params[:languages_code],
                                                   show_price: false }).serialize,
                 status: :ok
        end
      end
    end
  end
end
```

- [ ] **Step 5: Run specs to confirm they pass**

```bash
bundle exec rspec spec/requests/api/v1/events/upcoming_spec.rb spec/requests/api/v1/events/past_spec.rb --format documentation
```

Expected: all examples pass.

- [ ] **Step 6: Run full suite**

```bash
bundle exec rspec
```

Expected: 0 failures.

- [ ] **Step 7: Run RuboCop**

```bash
bundle exec rubocop app/controllers/api/v1/events/upcoming_controller.rb \
                    app/controllers/api/v1/events/past_controller.rb \
                    spec/requests/api/v1/events/upcoming_spec.rb \
                    spec/requests/api/v1/events/past_spec.rb
```

Fix any offenses.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/api/v1/events/upcoming_controller.rb \
        app/controllers/api/v1/events/past_controller.rb \
        spec/requests/api/v1/events/upcoming_spec.rb \
        spec/requests/api/v1/events/past_spec.rb
git commit -m "Bump homepage event limits to 10 with explicit ordering"
```

---

### Task 2: Event model scopes + unit tests

**Files:**
- Modify: `app/models/event.rb`
- Modify: `spec/models/event_spec.rb`

- [ ] **Step 1: Write failing scope tests**

Append the following describe blocks to `spec/models/event_spec.rb` (before the final `end`):

```ruby
  describe '.by_filter' do
    let!(:upcoming_event) { create(:event, status: :live, start_date: 5.days.from_now, end_date: 8.days.from_now) }
    let!(:past_event)     { create(:event, status: :live, start_date: 5.days.ago,      end_date: 2.days.ago) }
    let!(:draft_event)    { create(:event, status: :draft, start_date: 5.days.from_now, end_date: 8.days.from_now) }

    it 'upcoming returns only future live events' do
      result = Event.by_filter('upcoming')
      expect(result).to include(upcoming_event)
      expect(result).not_to include(past_event, draft_event)
    end

    it 'past returns only past live events' do
      result = Event.by_filter('past')
      expect(result).to include(past_event)
      expect(result).not_to include(upcoming_event, draft_event)
    end

    it 'all returns all live events regardless of date' do
      result = Event.by_filter('all')
      expect(result).to include(upcoming_event, past_event)
      expect(result).not_to include(draft_event)
    end

    it 'unknown filter falls back to all live events' do
      result = Event.by_filter('garbage')
      expect(result).to include(upcoming_event, past_event)
      expect(result).not_to include(draft_event)
    end
  end

  describe '.by_keyword' do
    let!(:event_a) do
      e = create(:event, status: :live, start_date: 5.days.from_now, end_date: 8.days.from_now)
      create(:events_translation, event: e, languages_code: 'ro-RO', name: 'Conferinta anuala', tag_line: 'O intalnire')
      e
    end
    let!(:event_b) do
      e = create(:event, status: :live, start_date: 5.days.from_now, end_date: 8.days.from_now)
      create(:events_translation, event: e, languages_code: 'ro-RO', name: 'Tabara copii', tag_line: 'Multa distractie')
      e
    end

    it 'matches by name' do
      expect(Event.by_keyword('conferinta', 'ro-RO')).to include(event_a)
      expect(Event.by_keyword('conferinta', 'ro-RO')).not_to include(event_b)
    end

    it 'matches by tag_line' do
      expect(Event.by_keyword('distractie', 'ro-RO')).to include(event_b)
      expect(Event.by_keyword('distractie', 'ro-RO')).not_to include(event_a)
    end

    it 'is case-insensitive' do
      expect(Event.by_keyword('TABARA', 'ro-RO')).to include(event_b)
    end

    it 'returns all events when search is blank' do
      expect(Event.by_keyword('', 'ro-RO')).to include(event_a, event_b)
    end

    it 'returns all events when search is nil' do
      expect(Event.by_keyword(nil, 'ro-RO')).to include(event_a, event_b)
    end
  end

  describe '.by_year' do
    let!(:event_2026) do
      create(:event, status: :live, start_date: Time.zone.parse('2026-06-01 10:00'),
                     end_date: Time.zone.parse('2026-06-04 18:00'))
    end
    let!(:event_2025) do
      create(:event, status: :live, start_date: Time.zone.parse('2025-03-01 10:00'),
                     end_date: Time.zone.parse('2025-03-04 18:00'))
    end

    it 'returns only events in the given year' do
      expect(Event.by_year(2026)).to include(event_2026)
      expect(Event.by_year(2026)).not_to include(event_2025)
    end

    it 'returns all events when year is nil' do
      expect(Event.by_year(nil)).to include(event_2026, event_2025)
    end

    it 'returns all events when year is blank string' do
      expect(Event.by_year('')).to include(event_2026, event_2025)
    end
  end

  describe '.by_pricing' do
    let!(:free_event)      { create(:event, status: :live, start_date: 5.days.from_now, end_date: 8.days.from_now) }
    let!(:paid_event)      { create(:event, status: :live, start_date: 5.days.from_now, end_date: 8.days.from_now) }
    let!(:no_ticket_event) { create(:event, status: :live, start_date: 5.days.from_now, end_date: 8.days.from_now) }

    before do
      create(:ticket, event: free_event, price: 0)
      create(:ticket, event: paid_event, price: 150)
    end

    it 'free returns events with zero-price tickets' do
      expect(Event.by_pricing('free')).to include(free_event)
      expect(Event.by_pricing('free')).not_to include(paid_event)
    end

    it 'free returns events with no tickets at all' do
      expect(Event.by_pricing('free')).to include(no_ticket_event)
    end

    it 'paid returns events with priced tickets only' do
      expect(Event.by_pricing('paid')).to include(paid_event)
      expect(Event.by_pricing('paid')).not_to include(free_event, no_ticket_event)
    end

    it 'both returns all events regardless of pricing' do
      expect(Event.by_pricing('both')).to include(free_event, paid_event, no_ticket_event)
    end

    it 'nil / blank returns all events' do
      expect(Event.by_pricing(nil)).to include(free_event, paid_event, no_ticket_event)
    end
  end

  describe '.sorted_for' do
    let!(:event_near) { create(:event, start_date: 2.days.from_now, end_date: 5.days.from_now) }
    let!(:event_far)  { create(:event, start_date: 30.days.from_now, end_date: 33.days.from_now) }

    it 'upcoming sorts start_date ascending (nearest first)' do
      result = Event.sorted_for('upcoming').where(id: [event_near.id, event_far.id])
      expect(result.first).to eq(event_near)
    end

    it 'past sorts start_date descending (most recent first)' do
      result = Event.sorted_for('past').where(id: [event_near.id, event_far.id])
      expect(result.first).to eq(event_far)
    end

    it 'all sorts start_date descending' do
      result = Event.sorted_for('all').where(id: [event_near.id, event_far.id])
      expect(result.first).to eq(event_far)
    end
  end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bundle exec rspec spec/models/event_spec.rb --format documentation 2>&1 | grep -E "FAILED|by_filter|by_keyword|by_year|by_pricing|sorted_for"
```

Expected: `NoMethodError` for each new scope.

- [ ] **Step 3: Add scopes to `app/models/event.rb`**

Add the following scopes after the existing `scope :hero` definition:

```ruby
  scope :by_filter, ->(filter) {
    base = where(status: 'live')
    case filter.to_s
    when 'upcoming' then base.where(start_date: Time.zone.now..)
    when 'past'     then base.where(start_date: ...Time.zone.now)
    else                 base
    end
  }

  scope :by_keyword, ->(search, lang) {
    return all if search.blank?

    joins(:events_translations)
      .where(events_translations: { languages_code: lang })
      .where(
        'events_translations.name ILIKE :q OR events_translations.tag_line ILIKE :q',
        q: "%#{sanitize_sql_like(search)}%"
      )
  }

  scope :by_year, ->(year) {
    return all if year.blank?

    where('EXTRACT(YEAR FROM start_date) = ?', year.to_i)
  }

  scope :by_pricing, ->(pricing) {
    return all if pricing.blank? || pricing.to_s == 'both'

    case pricing.to_s
    when 'free'
      left_joins(:tickets)
        .group('events.id')
        .having('MIN(tickets.price) IS NULL OR MIN(tickets.price) = 0')
    when 'paid'
      left_joins(:tickets)
        .group('events.id')
        .having('MIN(tickets.price) > 0')
    else
      all
    end
  }

  scope :sorted_for, ->(filter) {
    case filter.to_s
    when 'upcoming' then order(start_date: :asc)
    else                 order(start_date: :desc)
    end
  }
```

- [ ] **Step 4: Run scope tests to confirm they pass**

```bash
bundle exec rspec spec/models/event_spec.rb --format documentation
```

Expected: all examples pass.

- [ ] **Step 5: Run full suite**

```bash
bundle exec rspec
```

Expected: 0 failures.

- [ ] **Step 6: Run RuboCop**

```bash
bundle exec rubocop app/models/event.rb spec/models/event_spec.rb
```

Fix any offenses.

- [ ] **Step 7: Commit**

```bash
git add app/models/event.rb spec/models/event_spec.rb
git commit -m "Add listing scopes to Event: by_filter, by_keyword, by_year, by_pricing, sorted_for"
```

---

### Task 3: Listing controller, route, and request spec

**Files:**
- Create: `app/controllers/api/v1/events/listing_controller.rb`
- Modify: `config/routes.rb`
- Create: `spec/requests/api/v1/events/listing_spec.rb`

- [ ] **Step 1: Add route**

In `config/routes.rb`, inside the `namespace :events` block, add `resources :listing, only: :index`:

```ruby
        namespace :events do
          resources :upcoming, only: :index
          resources :past, only: :index
          resources :hero, only: :index
          resources :listing, only: :index
        end
```

- [ ] **Step 2: Write failing request spec**

Create `spec/requests/api/v1/events/listing_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/:lang/events/listing' do
  let(:lang) { 'ro-RO' }

  def get_listing(params = {})
    get "/api/v1/#{lang}/events/listing", params: params
  end

  def create_live_event(start_date:, name: 'Event', tag_line: 'Tagline')
    event = create(:event, status: :live, start_date: start_date,
                           end_date: start_date + 3.days)
    create(:events_translation, event: event, languages_code: lang, name: name,
                                tag_line: tag_line)
    event
  end

  it 'returns 200 with events and meta keys' do
    get_listing
    expect(response).to have_http_status(:ok)
    expect(json.keys).to contain_exactly('events', 'meta')
  end

  it 'returns only live events' do
    live_event  = create_live_event(start_date: 5.days.from_now, name: 'Live Event')
    draft_event = create(:event, status: :draft, start_date: 5.days.from_now, end_date: 8.days.from_now)
    create(:events_translation, event: draft_event, languages_code: lang, name: 'Draft Event')

    get_listing

    slugs = json['events'].pluck('slug')
    expect(slugs).to include(live_event.slug)
    expect(slugs).not_to include(draft_event.slug)
  end

  describe 'filter param' do
    let!(:upcoming_event) { create_live_event(start_date: 5.days.from_now,  name: 'Upcoming') }
    let!(:past_event)     { create_live_event(start_date: 5.days.ago,       name: 'Past') }

    it 'filter=upcoming returns only future events sorted ASC' do
      future_near = create_live_event(start_date: 2.days.from_now,  name: 'Near')
      future_far  = create_live_event(start_date: 20.days.from_now, name: 'Far')

      get_listing(filter: 'upcoming')

      names = json['events'].pluck('name')
      expect(names).not_to include('Past')
      expect(names.index('Near')).to be < names.index('Far')
    end

    it 'filter=past returns only past events sorted DESC (most recent first)' do
      recent = create_live_event(start_date: 2.days.ago,  name: 'Recent')
      older  = create_live_event(start_date: 20.days.ago, name: 'Older')

      get_listing(filter: 'past')

      names = json['events'].pluck('name')
      expect(names).not_to include('Upcoming')
      expect(names.index('Recent')).to be < names.index('Older')
    end

    it 'filter=all returns both upcoming and past sorted DESC' do
      get_listing(filter: 'all')

      names = json['events'].pluck('name')
      expect(names).to include('Upcoming', 'Past')
    end

    it 'unknown filter defaults to all' do
      get_listing(filter: 'invalid')

      names = json['events'].pluck('name')
      expect(names).to include('Upcoming', 'Past')
    end
  end

  describe 'search param' do
    let!(:event_a) { create_live_event(start_date: 5.days.from_now, name: 'Conferinta anuala',  tag_line: 'O intalnire') }
    let!(:event_b) { create_live_event(start_date: 5.days.from_now, name: 'Tabara copii',        tag_line: 'Multa distractie') }

    it 'filters by name (case-insensitive)' do
      get_listing(search: 'conferinta')

      slugs = json['events'].pluck('slug')
      expect(slugs).to include(event_a.slug)
      expect(slugs).not_to include(event_b.slug)
    end

    it 'filters by tag_line' do
      get_listing(search: 'distractie')

      slugs = json['events'].pluck('slug')
      expect(slugs).to include(event_b.slug)
      expect(slugs).not_to include(event_a.slug)
    end

    it 'matches case-insensitively' do
      get_listing(search: 'TABARA')

      expect(json['events'].pluck('slug')).to include(event_b.slug)
    end

    it 'returns all events when search is blank' do
      get_listing(search: '')

      slugs = json['events'].pluck('slug')
      expect(slugs).to include(event_a.slug, event_b.slug)
    end
  end

  describe 'year param' do
    let!(:event_2026) do
      e = create(:event, status: :live, start_date: Time.zone.parse('2026-06-01 10:00'),
                         end_date: Time.zone.parse('2026-06-04 18:00'))
      create(:events_translation, event: e, languages_code: lang, name: '2026 Event')
      e
    end
    let!(:event_2025) do
      e = create(:event, status: :live, start_date: Time.zone.parse('2025-03-01 10:00'),
                         end_date: Time.zone.parse('2025-03-04 18:00'))
      create(:events_translation, event: e, languages_code: lang, name: '2025 Event')
      e
    end

    it 'returns only events from the given year' do
      get_listing(year: 2026)

      slugs = json['events'].pluck('slug')
      expect(slugs).to include(event_2026.slug)
      expect(slugs).not_to include(event_2025.slug)
    end

    it 'returns all events when year is absent' do
      get_listing

      slugs = json['events'].pluck('slug')
      expect(slugs).to include(event_2026.slug, event_2025.slug)
    end
  end

  describe 'pricing param' do
    let!(:free_event) do
      e = create_live_event(start_date: 5.days.from_now, name: 'Free Event')
      create(:ticket, event: e, price: 0)
      e
    end
    let!(:paid_event) do
      e = create_live_event(start_date: 5.days.from_now, name: 'Paid Event')
      create(:ticket, event: e, price: 100)
      e
    end
    let!(:no_ticket_event) { create_live_event(start_date: 5.days.from_now, name: 'No Ticket Event') }

    it 'pricing=free returns free and no-ticket events' do
      get_listing(pricing: 'free')

      slugs = json['events'].pluck('slug')
      expect(slugs).to include(free_event.slug, no_ticket_event.slug)
      expect(slugs).not_to include(paid_event.slug)
    end

    it 'pricing=paid returns only paid events' do
      get_listing(pricing: 'paid')

      slugs = json['events'].pluck('slug')
      expect(slugs).to include(paid_event.slug)
      expect(slugs).not_to include(free_event.slug, no_ticket_event.slug)
    end

    it 'pricing=both returns all events' do
      get_listing(pricing: 'both')

      slugs = json['events'].pluck('slug')
      expect(slugs).to include(free_event.slug, paid_event.slug, no_ticket_event.slug)
    end

    it 'unknown pricing defaults to both' do
      get_listing(pricing: 'invalid')

      slugs = json['events'].pluck('slug')
      expect(slugs).to include(free_event.slug, paid_event.slug, no_ticket_event.slug)
    end
  end

  describe 'pagination' do
    before { 15.times { |i| create_live_event(start_date: (i + 1).days.from_now) } }

    it 'returns correct meta for page 1' do
      get_listing(per_page: 5, page: 1)

      meta = json['meta']
      expect(meta['current_page']).to eq(1)
      expect(meta['per_page']).to eq(5)
      expect(meta['total_count']).to eq(15)
      expect(meta['total_pages']).to eq(3)
    end

    it 'returns the correct slice for page 2' do
      get_listing(per_page: 5, page: 1, filter: 'upcoming')
      page1_slugs = json['events'].pluck('slug')

      get_listing(per_page: 5, page: 2, filter: 'upcoming')
      page2_slugs = json['events'].pluck('slug')

      expect(page2_slugs.length).to eq(5)
      expect((page1_slugs & page2_slugs)).to be_empty
    end

    it 'clamps per_page to 100' do
      get_listing(per_page: 9999)
      expect(json['meta']['per_page']).to eq(100)
    end

    it 'clamps per_page minimum to 1' do
      get_listing(per_page: 0)
      expect(json['meta']['per_page']).to eq(1)
    end

    it 'defaults per_page to 12' do
      get_listing
      expect(json['meta']['per_page']).to eq(12)
    end
  end

  describe 'empty result' do
    it 'returns empty events array with zero meta' do
      get_listing(search: 'xyzzy_nomatch')

      expect(json['events']).to eq([])
      expect(json['meta']['total_count']).to eq(0)
      expect(json['meta']['total_pages']).to eq(1)
      expect(json['meta']['current_page']).to eq(1)
    end
  end
end
```

- [ ] **Step 3: Run spec to confirm it fails**

```bash
bundle exec rspec spec/requests/api/v1/events/listing_spec.rb 2>&1 | tail -5
```

Expected: routing error — `No route matches [GET] "/api/v1/ro-RO/events/listing"`.

- [ ] **Step 4: Create the listing controller**

Create `app/controllers/api/v1/events/listing_controller.rb`:

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Events
      class ListingController < ActionController::API
        VALID_FILTERS  = %w[all upcoming past].freeze
        VALID_PRICINGS = %w[both free paid].freeze
        DEFAULT_PER_PAGE = 12
        MAX_PER_PAGE     = 100

        def index
          scope = Event
                    .by_filter(filter_param)
                    .by_keyword(params[:search], params[:languages_code])
                    .by_year(params[:year])
                    .by_pricing(pricing_param)
                    .distinct
                    .sorted_for(filter_param)

          total_count = Event.where(id: scope.unscope(:order).select('events.id')).count
          per_page    = per_page_param
          page        = page_param
          total_pages = [(total_count.to_f / per_page).ceil, 1].max

          events = scope.limit(per_page).offset((page - 1) * per_page)

          render json: {
            events: ThumbnailEventSerializer.new(
              events,
              params: { languages_code: params[:languages_code] }
            ).serialize,
            meta: {
              current_page: page,
              total_pages: total_pages,
              total_count: total_count,
              per_page: per_page
            }
          }
        end

        private

          def filter_param
            VALID_FILTERS.include?(params[:filter].to_s) ? params[:filter].to_s : 'all'
          end

          def pricing_param
            VALID_PRICINGS.include?(params[:pricing].to_s) ? params[:pricing].to_s : 'both'
          end

          def per_page_param
            [[(params[:per_page] || DEFAULT_PER_PAGE).to_i, 1].max, MAX_PER_PAGE].min
          end

          def page_param
            [(params[:page] || 1).to_i, 1].max
          end
      end
    end
  end
end
```

- [ ] **Step 5: Run spec to confirm it passes**

```bash
bundle exec rspec spec/requests/api/v1/events/listing_spec.rb --format documentation
```

Expected: all examples pass.

- [ ] **Step 6: Run full suite**

```bash
bundle exec rspec
```

Expected: 0 failures.

- [ ] **Step 7: Run RuboCop**

```bash
bundle exec rubocop app/controllers/api/v1/events/listing_controller.rb \
                    config/routes.rb \
                    spec/requests/api/v1/events/listing_spec.rb
```

Fix any offenses.

- [ ] **Step 8: Commit and push**

```bash
git add app/controllers/api/v1/events/listing_controller.rb \
        config/routes.rb \
        spec/requests/api/v1/events/listing_spec.rb
git commit -m "Add GET /events/listing with filter, search, year, pricing, and pagination"
git push origin main
```
