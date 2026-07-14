# frozen_string_literal: true

FactoryBot.define do
  factory :event_team_score_entry do
    association :event_team
    association :added_by_user, factory: :user
    delta { 5 }
  end
end
