# frozen_string_literal: true

class Attendee < ApplicationRecord
  belongs_to :event
  belongs_to :user, optional: true
  belongs_to :order, optional: true
  belongs_to :ticket, optional: true
  belongs_to :checked_in_by, class_name: 'User', foreign_key: :checked_in_by_user_id, optional: true,
                             inverse_of: false
  has_many :meal_stamps, dependent: :destroy
  has_many :attendee_template_doc_uploads, dependent: :destroy
  has_many :attendee_boolean_field_responses, dependent: :destroy

  enum :payment_status, { payment_pending: 0, paid: 1, refunded: 2, attendee_cancelled: 3 }
  enum :dietary_preference, { no_preference: 0, vegetarian: 1, vegan: 2 }

  ALLERGY_OPTIONS = %w[gluten lactose nuts eggs soy fish shellfish].freeze
  validate :allergies_are_valid

  def qr_code
    "#{order.order_reference}-#{id}"
  end

  def self.backfill_user(email:, user_id:)
    # rubocop:disable Rails/SkipsModelValidations
    where('LOWER(email_address) = LOWER(?)', email).update_all(user_id: user_id)
    # rubocop:enable Rails/SkipsModelValidations
  end

  private

    def allergies_are_valid
      invalid = Array(allergies) - ALLERGY_OPTIONS
      errors.add(:allergies, :invalid) if invalid.any?
    end
end
