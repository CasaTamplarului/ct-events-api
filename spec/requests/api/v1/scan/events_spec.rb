# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/scan/events' do
  let(:admin)         { create(:user, role: 'admin', language: 'ro-RO') }
  let(:attendee_user) { create(:user, role: 'attendee') }

  def auth_header(user)
    { 'Authorization' => "Bearer #{JwtService.encode(user.id)}", 'Content-Type' => 'application/json' }
  end

  before do
    Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }
    Language.find_or_create_by!(code: 'en-US') { |l| l.name = 'English' }
  end

  describe 'authentication and authorisation' do
    it 'returns 401 without a token' do
      get '/api/v1/scan/events'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 for attendee role' do
      get '/api/v1/scan/events', headers: auth_header(attendee_user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'filtering and sorting' do
    let!(:upcoming_event) do
      create(:event, status: :live, start_date: 7.days.from_now, end_date: 9.days.from_now)
    end
    let!(:further_event) do
      create(:event, status: :live, start_date: 30.days.from_now, end_date: 32.days.from_now)
    end
    let!(:past_event) do
      create(:event, status: :live, start_date: 7.days.ago, end_date: 5.days.ago)
    end
    let!(:draft_event) do
      create(:event, status: :draft, start_date: 3.days.from_now, end_date: 5.days.from_now)
    end

    before do
      create(:events_translation, event: upcoming_event, languages_code: 'ro-RO', name: 'Conferința 2026')
      create(:events_translation, event: further_event,  languages_code: 'ro-RO', name: 'Tabăra 2026')
    end

    it 'returns only live future events' do
      get '/api/v1/scan/events', headers: auth_header(admin)
      expect(response).to have_http_status(:ok)
      slugs = json.pluck('slug')
      expect(slugs).to include(upcoming_event.slug, further_event.slug)
      expect(slugs).not_to include(past_event.slug, draft_event.slug)
    end

    it 'returns name and slug only' do
      get '/api/v1/scan/events', headers: auth_header(admin)
      event_json = json.find { |e| e['slug'] == upcoming_event.slug }
      expect(event_json.keys).to contain_exactly('name', 'slug')
      expect(event_json['name']).to eq('Conferința 2026')
    end

    it 'sorts by start_date ascending (soonest first)' do
      get '/api/v1/scan/events', headers: auth_header(admin)
      slugs = json.pluck('slug')
      expect(slugs.index(upcoming_event.slug)).to be < slugs.index(further_event.slug)
    end
  end

  describe 'empty result' do
    it 'returns empty array when no upcoming live events exist' do
      get '/api/v1/scan/events', headers: auth_header(admin)
      expect(response).to have_http_status(:ok)
      expect(json).to eq([])
    end
  end

  describe 'translation resolution' do
    let!(:event) do
      create(:event, status: :live, start_date: 7.days.from_now, end_date: 9.days.from_now)
    end

    before do
      create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Conferința RO')
    end

    it 'returns name in the user language when translation exists' do
      en_user = create(:user, role: 'admin', language: 'en-US')
      create(:events_translation, event: event, languages_code: 'en-US', name: 'Conference EN')
      get '/api/v1/scan/events', headers: auth_header(en_user)
      expect(json.first['name']).to eq('Conference EN')
    end

    it 'falls back to ro-RO when user language translation is absent' do
      en_user = create(:user, role: 'admin', language: 'en-US')
      get '/api/v1/scan/events', headers: auth_header(en_user)
      expect(json.first['name']).to eq('Conferința RO')
    end
  end
end
