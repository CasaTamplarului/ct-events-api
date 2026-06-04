# frozen_string_literal: true

class EventBooleanField < ApplicationRecord
  belongs_to :event
  has_many :event_boolean_field_translations, dependent: :destroy

  validates :display_as, inclusion: { in: %w[toggle checkbox] }

  def label_for(languages_code)
    translation_for(languages_code)&.label
  end

  def true_label_for(languages_code)
    translation_for(languages_code)&.true_label
  end

  def false_label_for(languages_code)
    translation_for(languages_code)&.false_label
  end

  private

    def translation_for(languages_code)
      event_boolean_field_translations.find { |t| t.languages_code == languages_code } ||
        event_boolean_field_translations.find { |t| t.languages_code == 'ro-RO' }
    end
end
