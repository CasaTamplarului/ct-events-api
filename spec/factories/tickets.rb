# frozen_string_literal: true

FactoryBot.define do
  factory :ticket do
    name { 'MyString' }
    price { '9.99' }
    event { nil }
  end
end
