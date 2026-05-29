# frozen_string_literal: true

class AddForgotPasswordToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :language, :string
    add_column :users, :password_reset_token, :string
    add_column :users, :password_reset_token_expires_at, :datetime
    add_index :users, :password_reset_token, unique: true
  end
end
