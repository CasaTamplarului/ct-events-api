# frozen_string_literal: true

FactoryBot.define do
  factory :event_attendee_field do
    association :event
    field_name { 'first_name' }
    required   { true }
  end
end
