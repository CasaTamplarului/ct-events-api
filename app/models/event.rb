# frozen_string_literal: true

class Event < ApplicationRecord
  has_many :attendees

  # Enums
  enum status: { draft: 0, live: 1, cancelled: 2, deleted: 3 }

  def fully_booked?
    attendees.count >= max_number_of_people
  end
end
