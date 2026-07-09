# frozen_string_literal: true

class AddCancellationReasonToAttendees < ActiveRecord::Migration[7.1]
  def change
    add_column :attendees, :cancellation_reason, :string
    add_column :attendees, :cancellation_reason_text, :text
  end
end
