class RemoveNameFromTickets < ActiveRecord::Migration[7.1]
  def change
    remove_column :tickets, :name, :string
  end
end
