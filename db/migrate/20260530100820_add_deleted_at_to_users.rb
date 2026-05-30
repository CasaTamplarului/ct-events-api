class AddDeletedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :deleted_at, :datetime, default: nil
    add_index :users, :deleted_at
  end
end
