# frozen_string_literal: true

class QaSessionTranslation < ApplicationRecord
  belongs_to :qa_session
  belongs_to :language, foreign_key: :languages_code, primary_key: :code

  validates :name, presence: true
  validates :languages_code, presence: true, uniqueness: { scope: :qa_session_id }
end
