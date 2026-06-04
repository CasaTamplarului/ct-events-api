# frozen_string_literal: true

class EventBooleanFieldTranslation < ApplicationRecord
  belongs_to :event_boolean_field
  belongs_to :language, foreign_key: :languages_code, primary_key: :code, optional: true

  validates :languages_code, presence: true
  validates :label,           presence: true
  validates :true_label,      presence: true
  validates :false_label,     presence: true
  validates :languages_code, uniqueness: { scope: :event_boolean_field_id }
end
