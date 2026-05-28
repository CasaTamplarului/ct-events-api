# frozen_string_literal: true

FactoryBot.define do
  factory :user_identity do
    user
    provider { 'google' }
    uid { SecureRandom.hex(16) }
  end
end
