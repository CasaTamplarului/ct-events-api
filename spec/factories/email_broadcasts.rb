# frozen_string_literal: true

FactoryBot.define do
  factory :email_broadcast do
    subject { 'Test Subject' }
    body    { '<p>Hello</p>' }
    channel { 'marketing_emails' }
    association :sent_by_user, factory: :user
  end
end
