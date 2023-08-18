# frozen_string_literal: true

class Event < ApplicationRecord
  has_many :attendees, dependent: :destroy
  has_many :events_translations, foreign_key: 'events_id'

  # Enums
  enum status: { draft: 0, live: 1, cancelled: 2, deleted: 3 }

  def translations(language_code)
    events_translations.find_by(languages_code: language_code)
  end

  def fully_booked?
    return false if max_number_of_people.nil?

    attendees.count >= max_number_of_people
  end
end
