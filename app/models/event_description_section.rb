# frozen_string_literal: true

class EventDescriptionSection < ApplicationRecord
  belongs_to :event
  has_many :event_description_section_translations, dependent: :destroy

  def label_for(languages_code)
    translation_for(languages_code)&.label
  end

  def content_for(languages_code)
    translation_for(languages_code)&.content
  end

  private

    def translation_for(languages_code)
      event_description_section_translations.find { |t| t.languages_code == languages_code } ||
        event_description_section_translations.find { |t| t.languages_code == 'ro-RO' }
    end
end
