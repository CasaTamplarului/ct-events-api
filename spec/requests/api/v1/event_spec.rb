# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/:lang/event/:slug' do
  let(:language_code) { 'ro-RO' }
  let!(:language) { Language.find_or_create_by!(code: language_code) { |l| l.name = 'Romanian' } }

  let(:event) { create(:event, status: :live, slug: 'tabara-impact-2026') }
  let!(:event_translation) do
    create(:events_translation, event: event, languages_code: language_code,
           name: 'Tabara Impact', tag_line: 'O tabara')
  end

  def get_event
    get "/api/v1/#{language_code}/event/#{event.slug}"
  end

  context 'when event has speakers' do
    let!(:speaker) do
      create(:event_speaker, event: event, name: 'Ion Popescu', action_url: 'https://example.com', sort: 0)
    end
    let!(:speaker_translation) do
      create(:event_speakers_translation, event_speaker: speaker, languages_code: language_code,
             description: 'Un vorbitor remarcabil.', action_label: 'Detalii')
    end

    it 'returns speakers with translated fields' do
      get_event

      expect(response).to have_http_status(:ok)
      speakers = json['speakers']
      expect(speakers).to be_an(Array)
      expect(speakers.length).to eq(1)

      s = speakers.first
      expect(s['name']).to eq('Ion Popescu')
      expect(s['action_url']).to eq('https://example.com')
      expect(s['description']).to eq('Un vorbitor remarcabil.')
      expect(s['action_label']).to eq('Detalii')
      expect(s['image']).to be_nil
    end
  end

  context 'when event has no speakers' do
    it 'returns nil for speakers' do
      get_event

      expect(response).to have_http_status(:ok)
      expect(json['speakers']).to be_nil
    end
  end
end
