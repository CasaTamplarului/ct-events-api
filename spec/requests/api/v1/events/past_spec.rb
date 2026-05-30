# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/:lang/events/past' do
  let(:lang) { 'ro-RO' }
  let!(:language) { Language.find_or_create_by!(code: lang) { |l| l.name = 'Romanian' } }

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
    _older  = create_past(30, name: 'Older')
    _recent = create_past(5, name: 'Recent')

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
