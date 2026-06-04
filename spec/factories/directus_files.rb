# frozen_string_literal: true

FactoryBot.define do
  factory :directus_file do
    id { SecureRandom.uuid }
    filename_download { 'test.pdf' }
    storage { 'local' }
  end
end
