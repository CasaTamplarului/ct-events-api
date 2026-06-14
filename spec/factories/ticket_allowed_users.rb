# frozen_string_literal: true

FactoryBot.define do
  factory :ticket_allowed_user do
    ticket
    user
  end
end
