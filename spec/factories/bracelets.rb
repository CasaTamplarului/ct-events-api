# frozen_string_literal: true

FactoryBot.define do
  factory :bracelet do
    sequence(:code) { |n| "1-TEST#{n.to_s.rjust(3, '0')}" }
    event
    attendee { nil }
  end
end
