class AddPaymentStatusToAttendees < ActiveRecord::Migration[7.0]
  def change
    add_column :attendees, :payment_status, :integer, default: 0
  end
end
