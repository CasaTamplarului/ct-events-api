# frozen_string_literal: true

class AddFoodIncludedToTickets < ActiveRecord::Migration[8.1]
  def change
    add_column :tickets, :food_included, :boolean, null: false, default: false
  end
end
