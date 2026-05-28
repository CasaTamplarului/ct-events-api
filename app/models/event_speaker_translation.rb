# frozen_string_literal: true

class EventSpeakerTranslation < ApplicationRecord
  self.table_name = 'event_speakers_translations'

  belongs_to :event_speaker
end
