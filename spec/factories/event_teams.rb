# frozen_string_literal: true

FactoryBot.define do
  factory :event_team do
    association :event
    name { 'Team Red' }
    icon { nil }
    colour { nil }
    score { 0 }
  end
end
