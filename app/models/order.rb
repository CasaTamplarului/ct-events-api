# frozen_string_literal: true

class Order < ApplicationRecord
  has_many :attendees, dependent: :destroy

  after_create :generate_order_reference

  private

  def generate_order_reference
    update_column(:order_reference, "CT-#{created_at.year}-#{format('%05d', id)}")
  end
end
