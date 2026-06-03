# frozen_string_literal: true

class AddDefaultsToTicketMealSlotTimestamps < ActiveRecord::Migration[8.1]
  def change
    change_column_default :ticket_meal_slots, :created_at, from: nil, to: -> { 'CURRENT_TIMESTAMP' }
    change_column_default :ticket_meal_slots, :updated_at, from: nil, to: -> { 'CURRENT_TIMESTAMP' }
  end
end
