# frozen_string_literal: true

FactoryBot.define do
  factory :qa_question do
    association :qa_session
    body { 'What time does it start?' }
    display_name { 'A User' }
    submitter_token { SecureRandom.uuid }
    user_id { nil }
  end
end
