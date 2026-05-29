# frozen_string_literal: true

class AddMediaToEvents < ActiveRecord::Migration[8.1]
  def change
    # Single hero media slot (image or video) — stores Directus file UUID
    add_column :events, :hero_image, :uuid

    # Gallery — M2M junction between events and directus_files
    create_table :event_gallery do |t|
      t.references :event, null: false, foreign_key: true
      t.uuid :directus_files_id, null: false
      t.integer :sort, null: false, default: 0

      t.timestamps
    end

    add_index :event_gallery, %i[event_id directus_files_id], unique: true
    add_index :event_gallery, %i[event_id sort]
  end
end
