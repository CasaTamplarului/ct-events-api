# frozen_string_literal: true

class AddCascadeDeleteToPasskeysUserFk < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :passkeys, :users
    add_foreign_key :passkeys, :users, on_delete: :cascade
  end
end
