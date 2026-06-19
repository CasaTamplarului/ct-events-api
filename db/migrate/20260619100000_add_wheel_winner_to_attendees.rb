# frozen_string_literal: true

class AddWheelWinnerToAttendees < ActiveRecord::Migration[8.1]
  def change
    add_column :attendees, :wheel_winner, :boolean, null: false, default: false
  end
end
