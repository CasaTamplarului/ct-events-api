# frozen_string_literal: true

FactoryBot.define do
  factory :events_translation do
    event
    languages_code { 'ro-RO' }
    name { Faker::Lorem.words(number: 3).join(' ') }
    tag_line { Faker::Lorem.sentence }
  end
end
