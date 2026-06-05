# frozen_string_literal: true

FactoryBot.define do
  factory :push_notification do
    association :created_by, factory: :user, role: 'admin'
    translations do
      {
        'ro' => { 'title' => 'Salut!', 'body' => 'Buna ziua' },
        'en' => { 'title' => 'Hello!', 'body' => 'Good day' }
      }
    end
    link            { nil }
    directus_file_id { nil }
    sent_to         { 0 }
  end
end
