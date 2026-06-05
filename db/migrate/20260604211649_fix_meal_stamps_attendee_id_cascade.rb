# frozen_string_literal: true

class FixMealStampsAttendeeIdCascade < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :meal_stamps, column: :attendee_id
    add_foreign_key :meal_stamps, :attendees, column: :attendee_id, on_delete: :cascade
  end

  def down
    remove_foreign_key :meal_stamps, column: :attendee_id
    add_foreign_key :meal_stamps, :attendees, column: :attendee_id
  end
end
