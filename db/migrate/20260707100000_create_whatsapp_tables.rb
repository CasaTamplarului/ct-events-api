# frozen_string_literal: true

class CreateWhatsappTables < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_templates do |t|
      t.string :name,        null: false
      t.string :content_sid, null: false
      t.jsonb  :variables,   null: false, default: []
      t.timestamps
    end

    create_table :whatsapp_broadcasts do |t|
      t.bigint  :whatsapp_template_id, null: false
      t.bigint  :event_id
      t.bigint  :sent_by_user_id,      null: false
      t.integer :recipient_count,      null: false, default: 0
      t.timestamps
    end

    add_index :whatsapp_broadcasts, :whatsapp_template_id
    add_index :whatsapp_broadcasts, :event_id
    add_index :whatsapp_broadcasts, :sent_by_user_id

    create_table :whatsapp_broadcast_recipients, id: false do |t|
      t.bigint :whatsapp_broadcast_id, null: false
      t.bigint :user_id
      t.string :phone_number, null: false
    end

    execute <<~SQL
      CREATE UNIQUE INDEX idx_whatsapp_broadcast_recipients_broadcast_phone
        ON whatsapp_broadcast_recipients (whatsapp_broadcast_id, LOWER(phone_number))
    SQL

    add_index :whatsapp_broadcast_recipients, :user_id,
              where: 'user_id IS NOT NULL',
              name: 'idx_whatsapp_broadcast_recipients_user_id'
  end
end
