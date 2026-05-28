# frozen_string_literal: true

class RemoveUniqueIndexFromEventAttendeeFields < ActiveRecord::Migration[8.1]
  def change
    remove_index :event_attendee_fields, %i[event_id field_name]
    add_index :event_attendee_fields, %i[event_id field_name]
  end
end
