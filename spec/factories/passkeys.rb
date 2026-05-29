# frozen_string_literal: true

FactoryBot.define do
  factory :passkey do
    user
    external_id { SecureRandom.urlsafe_base64(32) }
    public_key  { SecureRandom.base64(64) }
    nickname    { nil }
  end
end
