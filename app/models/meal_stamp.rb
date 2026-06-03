# frozen_string_literal: true

class MealStamp < ApplicationRecord
  belongs_to :attendee
  belongs_to :ticket_meal_slot
  belongs_to :stamped_by, class_name: 'User', foreign_key: :stamped_by_user_id

  validates :stamped_by_user_id, presence: true
end
