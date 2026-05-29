# frozen_string_literal: true

class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.string :order_reference

      t.timestamps
    end
    add_index :orders, :order_reference, unique: true
  end
end
