# frozen_string_literal: true

FactoryBot.define do
  factory :whatsapp_broadcast do
    association :whatsapp_template
    association :sent_by_user, factory: :user, role: 'admin'
    recipient_count { 0 }
  end
end
