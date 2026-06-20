# frozen_string_literal: true

FactoryBot.define do
  factory :qa_vote do
    association :qa_question
    value { 1 }
    voter_token { SecureRandom.uuid }
    user_id { nil }
  end
end
