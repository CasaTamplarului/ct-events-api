# frozen_string_literal: true

class AddCascadeToTicketsAllowedUsersFks < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :tickets_allowed_users, :tickets
    remove_foreign_key :tickets_allowed_users, :users

    add_foreign_key :tickets_allowed_users, :tickets, on_delete: :cascade
    add_foreign_key :tickets_allowed_users, :users,   on_delete: :cascade
  end

  def down
    remove_foreign_key :tickets_allowed_users, :tickets
    remove_foreign_key :tickets_allowed_users, :users

    add_foreign_key :tickets_allowed_users, :tickets
    add_foreign_key :tickets_allowed_users, :users
  end
end
