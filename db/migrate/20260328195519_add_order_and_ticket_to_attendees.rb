class AddOrderAndTicketToAttendees < ActiveRecord::Migration[8.1]
  def change
    add_reference :attendees, :order, null: true, foreign_key: true
    add_reference :attendees, :ticket, null: true, foreign_key: true
  end
end
