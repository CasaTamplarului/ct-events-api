# frozen_string_literal: true

FactoryBot.define do
  factory :event_speakers_translation, class: 'EventSpeakerTranslation' do
    event_speaker
    languages_code { 'ro-RO' }
    description { 'Un vorbitor remarcabil.' }
    action_label { 'Detalii' }

    before(:create) do |translation|
      Language.find_or_create_by!(code: translation.languages_code) { |l| l.name = translation.languages_code }
    end
  end
end
