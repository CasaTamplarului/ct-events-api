# frozen_string_literal: true

class Order < ApplicationRecord
  belongs_to :user, optional: true
  has_many :attendees, dependent: :destroy

  after_create :generate_order_reference

  def payment_status(attendees_collection = nil)
    collection = attendees_collection || attendees
    active = collection.reject(&:attendee_cancelled?)
    return 'attendee_cancelled' if active.empty?

    statuses = active.map(&:payment_status).uniq
    statuses.size == 1 ? statuses.first : 'partial'
  end

  def payment_pending?(attendees_collection = nil)
    %w[payment_pending partial].include?(payment_status(attendees_collection))
  end

  private

    def generate_order_reference
      # rubocop:disable Rails/SkipsModelValidations
      update_column(:order_reference, "CT-#{created_at.year}-#{format('%05d', id)}")
      # rubocop:enable Rails/SkipsModelValidations
    end
end
