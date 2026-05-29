# frozen_string_literal: true

class AddCascadeDeleteToEventForeignKeys < ActiveRecord::Migration[8.1]
  # Tables whose event_id FK lacks ON DELETE CASCADE
  TABLES = %i[attendees event_attendee_fields event_gallery events_translations].freeze

  def up
    TABLES.each do |table|
      remove_foreign_key table, column: :event_id
      add_foreign_key table, :events, column: :event_id, on_delete: :cascade
    end
  end

  def down
    TABLES.each do |table|
      remove_foreign_key table, column: :event_id
      add_foreign_key table, :events, column: :event_id
    end
  end
end
