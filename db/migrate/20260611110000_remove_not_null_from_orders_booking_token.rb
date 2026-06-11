# frozen_string_literal: true

class RemoveNotNullFromOrdersBookingToken < ActiveRecord::Migration[8.1]
  def up
    change_column_null :orders, :booking_token, true
  end

  def down
    change_column_null :orders, :booking_token, false
  end
end
