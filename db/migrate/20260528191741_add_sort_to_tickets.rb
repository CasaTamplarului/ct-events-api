# frozen_string_literal: true

class AddSortToTickets < ActiveRecord::Migration[8.1]
  def change
    add_column :tickets, :sort, :integer
    add_index :tickets, %i[event_id sort]
  end
end
