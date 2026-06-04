# frozen_string_literal: true

FactoryBot.define do
  factory :attendee_boolean_field_response do
    association :attendee
    association :event_boolean_field
    value { true }
  end
end
