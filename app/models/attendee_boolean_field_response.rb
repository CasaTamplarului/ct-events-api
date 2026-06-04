# frozen_string_literal: true

class AttendeeBooleanFieldResponse < ApplicationRecord
  belongs_to :attendee
  belongs_to :event_boolean_field

  validates :value, inclusion: { in: [true, false] }
  validates :event_boolean_field_id, uniqueness: { scope: :attendee_id }
end
