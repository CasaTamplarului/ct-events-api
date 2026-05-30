# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/:lang/events/upcoming' do
  let(:lang) { 'ro-RO' }
  let!(:language) { Language.find_or_create_by!(code: lang) { |l| l.name = 'Romanian' } }

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
    _near = create_upcoming(2, name: 'Near')
    _far  = create_upcoming(20, name: 'Far')

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
