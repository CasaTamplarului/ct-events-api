# frozen_string_literal: true

FactoryBot.define do
  factory :ticket_meal_slot do
    ticket
    occurs_on { Date.today }
    meal_type { 'lunch' }
    sort      { 1 }
  end
end
