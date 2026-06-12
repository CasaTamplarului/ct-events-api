# frozen_string_literal: true

FactoryBot.define do
  factory :event_description_section_translation do
    association :event_description_section
    languages_code { 'ro-RO' }
    label   { 'Titlu secțiune' }
    content { '<p>Conținut secțiune</p>' }
  end
end
