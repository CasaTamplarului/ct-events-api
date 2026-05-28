# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EventSpeaker, type: :model do
  it 'has a valid factory' do
    expect(build(:event_speaker)).to be_valid
  end

  describe '#translations' do
    it 'returns the translation for the given language code' do
      speaker = create(:event_speaker)
      translation = create(:event_speakers_translation,
                           event_speaker: speaker, languages_code: 'ro-RO',
                           description: 'Descriere', action_label: 'Detalii')

      expect(speaker.translations('ro-RO')).to eq(translation)
    end

    it 'returns nil when no translation exists for the language' do
      speaker = create(:event_speaker)
      expect(speaker.translations('en-US')).to be_nil
    end
  end
end
