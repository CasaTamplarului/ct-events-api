# frozen_string_literal: true

class CreateEventBooleanFields < ActiveRecord::Migration[8.1]
  def change
    create_table :event_boolean_fields do |t|
      t.references :event, null: false, foreign_key: { on_delete: :cascade }
      t.integer :sort,       null: false, default: 0
      t.boolean :required,   null: false, default: false
      t.string  :display_as, null: false

      t.timestamps default: -> { 'CURRENT_TIMESTAMP' }
    end

    add_index :event_boolean_fields, %i[event_id sort]
  end
end
