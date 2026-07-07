# frozen_string_literal: true

FactoryBot.define do
  factory :whatsapp_template do
    name        { 'Event Reminder' }
    content_sid { 'HXabc1234567890' }
    variables   { [{ 'position' => 1, 'name' => 'first_name' }, { 'position' => 2, 'name' => 'event_name' }] }
  end
end
