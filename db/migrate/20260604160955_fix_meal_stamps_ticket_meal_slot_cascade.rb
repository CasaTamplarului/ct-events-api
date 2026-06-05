# frozen_string_literal: true

class FixMealStampsTicketMealSlotCascade < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :meal_stamps, :ticket_meal_slots
    add_foreign_key :meal_stamps, :ticket_meal_slots, on_delete: :cascade
  end
end
