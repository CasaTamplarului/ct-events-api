# frozen_string_literal: true

class AddAgeToAttendees < ActiveRecord::Migration[8.1]
  def change
    add_column :attendees, :age, :integer, null: true
  end
end
