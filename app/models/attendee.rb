class Attendee < ApplicationRecord
  belongs_to :event

  # Enums
  enum payment_status: { payment_pending: 0, paid: 1, refunded: 2 }
end
