# frozen_string_literal: true

class CreateEventSpeakers < ActiveRecord::Migration[8.1]
  def change
    create_table :event_speakers do |t|
      t.references :event, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.uuid :image
      t.string :action_url
      t.integer :sort, null: false, default: 0

      t.timestamps
    end

    add_index :event_speakers, %i[event_id sort]
    add_foreign_key :event_speakers, :directus_files, column: :image,
                    name: :event_speakers_image_foreign, on_delete: :nullify
  end
end
