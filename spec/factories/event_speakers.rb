# frozen_string_literal: true

FactoryBot.define do
  factory :event_speaker do
    event
    name { 'John Doe' }
    action_url { 'https://example.com' }
  end
end
