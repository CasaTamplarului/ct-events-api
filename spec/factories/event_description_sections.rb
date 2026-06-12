# frozen_string_literal: true

FactoryBot.define do
  factory :event_description_section do
    association :event
    sort { 0 }
  end
end
