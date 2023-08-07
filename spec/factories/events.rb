# frozen_string_literal: true

FactoryBot.define do
  factory :event do
    name { Faker::Lorem.sentence(word_count: 5) }
    description { Faker::Lorem.paragraph(sentence_count: 4) }
    start_date { Faker::Date.forward(days: 10) }
    end_date { Faker::Date.forward(days: 13) }
  end
end