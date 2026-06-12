# frozen_string_literal: true

class EventDescriptionSectionTranslation < ApplicationRecord
  self.table_name = 'event_description_section_translations'

  belongs_to :event_description_section
end
