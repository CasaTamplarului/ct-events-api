# frozen_string_literal: true

FactoryBot.define do
  factory :tickets_translation do
    languages_code { 'ro-RO' }
    name { 'Standard' }
  end
end
