# frozen_string_literal: true

class CreateEventDescriptionSections < ActiveRecord::Migration[8.1]
  def change
    create_table :event_description_sections do |t|
      t.references :event, null: false, foreign_key: { on_delete: :cascade }
      t.integer :sort, null: false, default: 0

      t.timestamps default: -> { 'CURRENT_TIMESTAMP' }
    end

    add_index :event_description_sections, %i[event_id sort]
  end
end
