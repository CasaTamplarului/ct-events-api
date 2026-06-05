# frozen_string_literal: true

class EventAttendeeField < ApplicationRecord
  ALLOWED_FIELDS = %w[first_name last_name email_address phone_number dietary_preference allergies church_name city age].freeze

  belongs_to :event

  validates :field_name, inclusion: { in: ALLOWED_FIELDS }
  validates :field_name, uniqueness: { scope: :event_id }
end
