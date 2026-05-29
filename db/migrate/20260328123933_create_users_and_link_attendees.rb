# frozen_string_literal: true

class CreateUsersAndLinkAttendees < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :email, null: false
      t.string :phone_number
      t.string :password_digest, null: false

      t.timestamps
    end

    add_index :users, :email, unique: true

    add_reference :attendees, :user, foreign_key: true, null: true
  end
end
