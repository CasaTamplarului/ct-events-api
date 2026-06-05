# frozen_string_literal: true

class EventTemplateDocTranslation < ApplicationRecord
  belongs_to :event_template_doc
  belongs_to :language, foreign_key: :languages_code, primary_key: :code, optional: true

  validates :languages_code, presence: true
  validates :label,          presence: true
  validates :languages_code, uniqueness: { scope: :event_template_doc_id }
end
