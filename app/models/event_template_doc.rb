# frozen_string_literal: true

class EventTemplateDoc < ApplicationRecord
  belongs_to :event
  has_many :event_template_doc_translations, dependent: :destroy

  validates :directus_files_id, presence: true

  def label_for(languages_code)
    event_template_doc_translations.find { |t| t.languages_code == languages_code }&.label ||
      event_template_doc_translations.find { |t| t.languages_code == 'ro-RO' }&.label
  end
end
