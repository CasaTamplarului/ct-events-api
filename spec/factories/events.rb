# frozen_string_literal: true

FactoryBot.define do
  factory :event do
    # name { Faker::Lorem.sentence(word_count: 5) }
    # description { Faker::Lorem.paragraph(sentence_count: 4) }
    start_date { Faker::Date.forward(days: 10) }
    end_date { Faker::Date.forward(days: 13) }
    max_number_of_people { Faker::Number.number(digits: 2) }
    min_age { Faker::Number.number(digits: 1) }
    max_age { Faker::Number.number(digits: 2) }
  end
end
