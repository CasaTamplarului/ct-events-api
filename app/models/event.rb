# frozen_string_literal: true

class Event < ApplicationRecord
  has_many :attendees, dependent: :destroy

  # Enums
  enum status: { draft: 0, live: 1, cancelled: 2, deleted: 3 }

  def fully_booked?
    return false if max_number_of_people.nil?

    attendees.count >= max_number_of_people
  end
end
