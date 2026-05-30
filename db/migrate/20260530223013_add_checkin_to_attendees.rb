# frozen_string_literal: true

class AddCheckinToAttendees < ActiveRecord::Migration[8.1]
  def change
    add_column :attendees, :checked_in, :boolean, default: false, null: false
    add_column :attendees, :checked_in_at, :datetime
    add_column :attendees, :checked_in_by_user_id, :bigint
    add_foreign_key :attendees, :users, column: :checked_in_by_user_id
    add_index :attendees, :checked_in_by_user_id
  end
end
