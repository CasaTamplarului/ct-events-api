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

  context 'template_docs' do
    before do
      Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }
      Language.find_or_create_by!(code: 'en-US') { |l| l.name = 'English' }
    end

    def create_directus_file(uuid)
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql([
          "INSERT INTO directus_files (id, filename_download, storage) VALUES (?, 'test.pdf', 'local') ON CONFLICT DO NOTHING",
          uuid
        ])
      )
    end

    it 'returns empty array when event has no template docs' do
      get_event
      expect(json['template_docs']).to eq([])
    end

    it 'includes age_from and age_to on each template doc' do
      uuid = 'aaaaaaaa-0000-0000-0000-000000000001'
      create_directus_file(uuid)
      doc = EventTemplateDoc.create!(event: event, directus_files_id: uuid, sort: 0,
                                     age_from: 16, age_to: 25)
      doc.event_template_doc_translations.create!(languages_code: 'ro-RO', label: 'Formular')

      get_event

      expect(json['template_docs'].first['age_from']).to eq(16)
      expect(json['template_docs'].first['age_to']).to eq(25)
    end

    it 'returns null age_from and age_to when not set' do
      uuid = 'aaaaaaaa-0000-0000-0000-000000000001'
      create_directus_file(uuid)
      doc = EventTemplateDoc.create!(event: event, directus_files_id: uuid, sort: 0)
      doc.event_template_doc_translations.create!(languages_code: 'ro-RO', label: 'Formular')

      get_event

      expect(json['template_docs'].first['age_from']).to be_nil
      expect(json['template_docs'].first['age_to']).to be_nil
    end

    it 'includes required flag on each template doc' do
      uuid = 'aaaaaaaa-0000-0000-0000-000000000001'
      create_directus_file(uuid)
      doc = EventTemplateDoc.create!(event: event, directus_files_id: uuid, sort: 0, required: true)
      doc.event_template_doc_translations.create!(languages_code: 'ro-RO', label: 'Formular')

      get_event

      expect(json['template_docs'].first['required']).to be true
    end

    it 'returns label in the requested language and url for each template doc' do
      uuid = 'aaaaaaaa-0000-0000-0000-000000000001'
      create_directus_file(uuid)
      doc = EventTemplateDoc.create!(event: event, directus_files_id: uuid, sort: 0)
      doc.event_template_doc_translations.create!(languages_code: 'ro-RO', label: 'Formular')
      doc.event_template_doc_translations.create!(languages_code: 'en-US', label: 'Form')

      get_event

      expect(json['template_docs'].length).to eq(1)
      expect(json['template_docs'].first['label']).to eq('Formular')
      expect(json['template_docs'].first['url']).to eq(ApplicationSerializer.asset_url(doc.directus_files_id))
    end

    it 'falls back to ro-RO label when requested language has no translation' do
      create(:events_translation, event: event, languages_code: 'en-US', name: 'Tabara Impact EN')
      uuid = 'aaaaaaaa-0000-0000-0000-000000000001'
      create_directus_file(uuid)
      doc = EventTemplateDoc.create!(event: event, directus_files_id: uuid, sort: 0)
      doc.event_template_doc_translations.create!(languages_code: 'ro-RO', label: 'Formular')

      get "/api/v1/en-US/event/#{event.slug}"

      expect(json['template_docs'].first['label']).to eq('Formular')
    end

    it 'returns template docs ordered by sort' do
      create_directus_file('aaaaaaaa-0000-0000-0000-000000000001')
      create_directus_file('aaaaaaaa-0000-0000-0000-000000000002')
      doc1 = EventTemplateDoc.create!(event: event, directus_files_id: 'aaaaaaaa-0000-0000-0000-000000000002', sort: 1)
      doc2 = EventTemplateDoc.create!(event: event, directus_files_id: 'aaaaaaaa-0000-0000-0000-000000000001', sort: 0)
      doc1.event_template_doc_translations.create!(languages_code: 'ro-RO', label: 'Second')
      doc2.event_template_doc_translations.create!(languages_code: 'ro-RO', label: 'First')

      get_event

      expect(json['template_docs'].map { |d| d['label'] }).to eq(['First', 'Second'])
    end
  end

  context 'boolean_fields' do
    before do
      Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }
      Language.find_or_create_by!(code: 'en-US') { |l| l.name = 'English' }
    end

    it 'returns an empty array when the event has no boolean fields' do
      get_event
      expect(json['boolean_fields']).to eq([])
    end

    it 'returns boolean fields with translated label, true_label, false_label' do
      field = EventBooleanField.create!(event: event, sort: 0, required: true, display_as: 'checkbox')
      EventBooleanFieldTranslation.create!(event_boolean_field: field, languages_code: 'ro-RO',
                                            label: 'Ești de acord?',
                                            true_label: 'Da, sunt de acord',
                                            false_label: 'Nu sunt de acord')

      get_event

      expect(json['boolean_fields'].length).to eq(1)
      bf = json['boolean_fields'].first
      expect(bf['id']).to eq(field.id)
      expect(bf['required']).to be true
      expect(bf['display_as']).to eq('checkbox')
      expect(bf['label']).to eq('Ești de acord?')
      expect(bf['true_label']).to eq('Da, sunt de acord')
      expect(bf['false_label']).to eq('Nu sunt de acord')
    end

    it 'falls back to ro-RO labels when the requested language has no translation' do
      create(:events_translation, event: event, languages_code: 'en-US', name: 'Tabara Impact EN',
             tag_line: 'A camp')
      field = EventBooleanField.create!(event: event, sort: 0, required: false, display_as: 'toggle')
      EventBooleanFieldTranslation.create!(event_boolean_field: field, languages_code: 'ro-RO',
                                            label: 'Ești de acord?', true_label: 'Da', false_label: 'Nu')

      get "/api/v1/en-US/event/#{event.slug}"

      expect(json['boolean_fields'].first['label']).to eq('Ești de acord?')
    end

    it 'returns boolean fields ordered by sort' do
      field1 = EventBooleanField.create!(event: event, sort: 1, required: false, display_as: 'checkbox')
      field2 = EventBooleanField.create!(event: event, sort: 0, required: false, display_as: 'toggle')
      EventBooleanFieldTranslation.create!(event_boolean_field: field1, languages_code: 'ro-RO',
                                            label: 'Second', true_label: 'Da', false_label: 'Nu')
      EventBooleanFieldTranslation.create!(event_boolean_field: field2, languages_code: 'ro-RO',
                                            label: 'First', true_label: 'Da', false_label: 'Nu')

      get_event

      expect(json['boolean_fields'].map { |f| f['label'] }).to eq(%w[First Second])
    end
  end

  context 'when event has no speakers' do
    it 'returns nil for speakers' do
      get_event

      expect(response).to have_http_status(:ok)
      expect(json['speakers']).to be_nil
    end
  end

  context 'attendee_fields with age validation' do
    let(:event_with_age) do
      create(:event, status: :live, slug: 'tabara-tineri', min_age: 16, max_age: 35)
    end

    before do
      create(:events_translation, event: event_with_age, languages_code: language_code, name: 'Tabara Tineri')
      create(:event_attendee_field, event: event_with_age, field_name: 'first_name', required: true)
      create(:event_attendee_field, event: event_with_age, field_name: 'age', required: true)
    end

    it 'includes validation with min and max for the age field' do
      get "/api/v1/#{language_code}/event/#{event_with_age.slug}"

      age_field = json['attendee_fields'].find { |f| f['field'] == 'age' }
      expect(age_field['validation']).to eq({ 'min' => 16, 'max' => 35 })
    end

    it 'returns null validation for non-age fields' do
      get "/api/v1/#{language_code}/event/#{event_with_age.slug}"

      name_field = json['attendee_fields'].find { |f| f['field'] == 'first_name' }
      expect(name_field['validation']).to be_nil
    end

    it 'includes age as a valid attendee field' do
      expect(EventAttendeeField::ALLOWED_FIELDS).to include('age')
    end
  end
end
