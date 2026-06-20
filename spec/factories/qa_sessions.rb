# frozen_string_literal: true

FactoryBot.define do
  factory :qa_session do
    association :event
    association :created_by_user, factory: :user, role: 'admin'
    status { :open }
    voting_enabled { true }
    questions_public { true }
  end
end
