class AddStatusToEvent < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :status, :integer, default: 0
  end
end
