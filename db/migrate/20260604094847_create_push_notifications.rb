# frozen_string_literal: true

class CreatePushNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :push_notifications do |t|
      t.references :event,      foreign_key: true, null: true
      t.references :created_by, foreign_key: { to_table: :users }, null: false
      t.jsonb      :translations, null: false, default: {}
      t.string     :link
      t.string     :directus_file_id
      t.integer    :sent_to, null: false, default: 0

      t.timestamps
    end
  end
end
