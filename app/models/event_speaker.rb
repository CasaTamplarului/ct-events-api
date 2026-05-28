# frozen_string_literal: true

class EventSpeaker < ApplicationRecord
  belongs_to :event
  has_many :event_speakers_translations, class_name: "EventSpeakerTranslation", dependent: :destroy, inverse_of: :event_speaker

  def translations(language_code)
    event_speakers_translations.find_by(languages_code: language_code)
  end
end
