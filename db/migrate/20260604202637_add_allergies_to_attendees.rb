# frozen_string_literal: true

class AddAllergiesToAttendees < ActiveRecord::Migration[8.1]
  def change
    add_column :attendees, :allergies, :integer, default: 0, null: false
  end
end
