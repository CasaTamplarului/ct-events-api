# frozen_string_literal: true

FactoryBot.define do
  factory :event_template_doc do
    association :event
    directus_files_id { create(:directus_file).id }
    sort { 0 }
    required { false }
    age_from { nil }
    age_to { nil }
  end
end
