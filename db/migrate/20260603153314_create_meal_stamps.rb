# frozen_string_literal: true

class CreateMealStamps < ActiveRecord::Migration[8.0]
  def change
    create_table :meal_stamps do |t|
      t.references :attendee,         null: false, foreign_key: true
      t.references :ticket_meal_slot, null: false, foreign_key: true
      t.bigint     :stamped_by_user_id, null: false
      t.datetime   :created_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end
    add_foreign_key :meal_stamps, :users, column: :stamped_by_user_id
    add_index :meal_stamps, %i[attendee_id ticket_meal_slot_id]
  end
end
