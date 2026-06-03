# frozen_string_literal: true

class TicketMealSlot < ApplicationRecord
  MEAL_TYPES = %w[breakfast lunch dinner snack].freeze

  belongs_to :ticket
  has_many :meal_stamps, dependent: :destroy

  validates :occurs_on, :meal_type, presence: true
  validates :meal_type, inclusion: { in: MEAL_TYPES }
end
