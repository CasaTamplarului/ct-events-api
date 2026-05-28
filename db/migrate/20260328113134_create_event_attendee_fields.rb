# frozen_string_literal: true

class CreateEventAttendeeFields < ActiveRecord::Migration[8.1]
  def change
    create_table :event_attendee_fields do |t|
      t.references :event, null: false, foreign_key: true
      t.string :field_name, null: false
      t.boolean :required, null: false, default: true
      t.integer :sort, null: false, default: 0

      t.timestamps
    end

    add_index :event_attendee_fields, %i[event_id field_name], unique: true
    add_index :event_attendee_fields, %i[event_id sort]
  end
end
