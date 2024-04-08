# frozen_string_literal: true

class Ticket < ApplicationRecord
  has_many :tickets_translations, foreign_key: 'tickets_id', dependent: :destroy, inverse_of: :ticket

  belongs_to :event

  def translations(language_code)
    tickets_translations.find_by(languages_code: language_code)
  end
end
