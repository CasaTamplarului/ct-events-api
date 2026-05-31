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

  REFERENCE_CHARS = (('A'..'Z').to_a + ('0'..'9').to_a).freeze

  private

    def generate_order_reference
      loop do
        ref = "CT-#{created_at.year}-#{Array.new(6) { REFERENCE_CHARS.sample }.join}"
        next if Order.exists?(order_reference: ref)

        # rubocop:disable Rails/SkipsModelValidations
        update_column(:order_reference, ref)
        # rubocop:enable Rails/SkipsModelValidations
        break
      end
    end
end
