# frozen_string_literal: true

FactoryBot.define do
  factory :attendee_template_doc_upload do
    association :attendee
    association :event_template_doc
    directus_files_id { create(:directus_file).id }
  end
end
