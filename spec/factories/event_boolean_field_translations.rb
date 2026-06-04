# frozen_string_literal: true

FactoryBot.define do
  factory :event_boolean_field_translation do
    association :event_boolean_field
    languages_code { 'ro-RO' }
    label       { 'Ești de acord?' }
    true_label  { 'Da' }
    false_label { 'Nu' }
  end
end
