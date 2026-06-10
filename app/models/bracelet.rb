# frozen_string_literal: true

class Bracelet < ApplicationRecord
  belongs_to :event
  belongs_to :attendee, optional: true

  validates :code, presence: true, uniqueness: true
end
