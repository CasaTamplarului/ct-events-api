# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/:lang/events/listing' do
  let(:lang) { 'ro-RO' }
  let!(:language) { Language.find_or_create_by!(code: lang) { |l| l.name = 'Romanian' } }

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
      _future_near = create_live_event(start_date: 2.days.from_now,  name: 'Near')
      _future_far  = create_live_event(start_date: 20.days.from_now, name: 'Far')

      get_listing(filter: 'upcoming')

      names = json['events'].pluck('name')
      expect(names).not_to include('Past')
      expect(names.index('Near')).to be < names.index('Far')
    end

    it 'filter=past returns only past events sorted DESC (most recent first)' do
      _recent = create_live_event(start_date: 2.days.ago,  name: 'Recent')
      _older  = create_live_event(start_date: 20.days.ago, name: 'Older')

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
    let!(:event_a) { create_live_event(start_date: 5.days.from_now, name: 'Conferinta anuala', tag_line: 'O intalnire') }
    let!(:event_b) { create_live_event(start_date: 5.days.from_now, name: 'Tabara copii', tag_line: 'Multa distractie') }

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
    let!(:event_current_year) do
      e = create(:event, status: :live, start_date: Time.zone.parse('2026-06-01 10:00'),
                         end_date: Time.zone.parse('2026-06-04 18:00'))
      create(:events_translation, event: e, languages_code: lang, name: '2026 Event')
      e
    end
    let!(:event_prior_year) do
      e = create(:event, status: :live, start_date: Time.zone.parse('2025-03-01 10:00'),
                         end_date: Time.zone.parse('2025-03-04 18:00'))
      create(:events_translation, event: e, languages_code: lang, name: '2025 Event')
      e
    end

    it 'returns only events from the given year' do
      get_listing(year: 2026)

      slugs = json['events'].pluck('slug')
      expect(slugs).to include(event_current_year.slug)
      expect(slugs).not_to include(event_prior_year.slug)
    end

    it 'returns all events when year is absent' do
      get_listing

      slugs = json['events'].pluck('slug')
      expect(slugs).to include(event_current_year.slug, event_prior_year.slug)
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
      expect(page1_slugs & page2_slugs).to be_empty
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
