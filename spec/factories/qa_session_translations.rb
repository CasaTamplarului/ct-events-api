# frozen_string_literal: true

FactoryBot.define do
  factory :qa_session_translation do
    association :qa_session
    languages_code { 'ro-RO' }
    name { 'Sesiunea de Q&A' }

    before(:create) do |t|
      Language.find_or_create_by!(code: t.languages_code) { |l| l.name = 'Romanian' }
    end
  end
end
