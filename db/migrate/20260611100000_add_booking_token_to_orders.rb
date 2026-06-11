# frozen_string_literal: true

class AddBookingTokenToOrders < ActiveRecord::Migration[8.1]
  def up
    add_column :orders, :booking_token, :string
    add_index  :orders, :booking_token, unique: true

    # Backfill existing orders
    Order.find_each do |order|
      loop do
        token = SecureRandom.urlsafe_base64(32)
        next if Order.exists?(booking_token: token)

        order.update_column(:booking_token, token) # rubocop:disable Rails/SkipsModelValidations
        break
      end
    end

    change_column_null :orders, :booking_token, false
  end

  def down
    remove_column :orders, :booking_token
  end
end
