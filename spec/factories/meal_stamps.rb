# frozen_string_literal: true

FactoryBot.define do
  factory :meal_stamp do
    attendee
    ticket_meal_slot
    stamped_by_user_id { create(:user).id }
  end
end
