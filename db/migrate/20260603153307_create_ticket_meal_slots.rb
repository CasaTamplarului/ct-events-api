# frozen_string_literal: true

class CreateTicketMealSlots < ActiveRecord::Migration[8.0]
  def change
    create_table :ticket_meal_slots do |t|
      t.references :ticket, null: false, foreign_key: true
      t.date    :occurs_on, null: false
      t.string  :meal_type, null: false
      t.integer :sort
      t.timestamps
    end
    add_index :ticket_meal_slots, %i[ticket_id occurs_on meal_type]
  end
end
