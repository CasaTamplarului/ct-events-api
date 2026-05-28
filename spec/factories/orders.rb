# frozen_string_literal: true

FactoryBot.define do
  factory :order do
    order_reference { "CT-#{Time.zone.now.year}-00001" }
  end
end
