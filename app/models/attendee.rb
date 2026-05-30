# frozen_string_literal: true

class Attendee < ApplicationRecord
  belongs_to :event
  belongs_to :user, optional: true
  belongs_to :order, optional: true
  belongs_to :ticket, optional: true

  # Enums
  enum :payment_status, { payment_pending: 0, paid: 1, refunded: 2 }
  enum :dietary_preference, { no_preference: 0, vegetarian: 1, vegan: 2 }

  def self.backfill_user(email:, user_id:)
    # rubocop:disable Rails/SkipsModelValidations
    where('LOWER(email_address) = LOWER(?)', email).update_all(user_id: user_id)
    # rubocop:enable Rails/SkipsModelValidations
  end
end
