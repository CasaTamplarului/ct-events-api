class RemoveFieldsFromEvents < ActiveRecord::Migration[7.0]
  def change
    remove_column :events, :name, :string
    remove_column :events, :description, :text
  end
end
