# frozen_string_literal: true

class AddProfileFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    change_column_null :users, :last_name, true
    add_column :users, :church_name, :string
    add_column :users, :city, :string
  end
end
