# frozen_string_literal: true

class RevertPaymentStatusToAttendees < ActiveRecord::Migration[8.1]
  def up
    add_column :attendees, :payment_status, :integer, default: 0, null: false

    execute <<~SQL
      UPDATE attendees
      SET payment_status = orders.payment_status
      FROM orders
      WHERE attendees.order_id = orders.id
    SQL

    remove_column :orders, :payment_status
  end

  def down
    add_column :orders, :payment_status, :integer, default: 0, null: false

    execute <<~SQL
      UPDATE orders
      SET payment_status = (
        SELECT payment_status
        FROM attendees
        WHERE attendees.order_id = orders.id
        ORDER BY attendees.id ASC
        LIMIT 1
      )
      WHERE EXISTS (
        SELECT 1 FROM attendees WHERE attendees.order_id = orders.id
      )
    SQL

    remove_column :attendees, :payment_status
  end
end
