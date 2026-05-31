# frozen_string_literal: true

FactoryBot.define do
  factory :order do
    payment_status { :payment_pending }
  end
end
