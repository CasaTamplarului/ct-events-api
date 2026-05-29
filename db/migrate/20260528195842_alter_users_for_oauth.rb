# frozen_string_literal: true

class AlterUsersForOauth < ActiveRecord::Migration[8.1]
  def change
    change_column_null :users, :password_digest, true
    add_column :users, :avatar_url, :string
  end
end
