# frozen_string_literal: true

FactoryBot.define do
  factory :event_boolean_field do
    association :event
    sort       { 0 }
    required   { false }
    display_as { 'checkbox' }
  end
end
