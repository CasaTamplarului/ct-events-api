# frozen_string_literal: true

FactoryBot.define do
  factory :order do
    payment_status { :payment_pending }
    sequence(:order_reference) { |n| "CT-#{Time.zone.now.year}-#{n.to_s.rjust(5, '0')}" }
  end
end
