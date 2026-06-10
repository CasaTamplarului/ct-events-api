# frozen_string_literal: true

class CreateBracelets < ActiveRecord::Migration[8.1]
  def change
    create_table :bracelets do |t|
      t.string     :code,        null: false
      t.references :event,       null: false, foreign_key: { on_delete: :cascade }
      t.references :attendee,    null: true,  foreign_key: { on_delete: :nullify }
      t.timestamps
    end

    add_index :bracelets, :code, unique: true
  end
end
