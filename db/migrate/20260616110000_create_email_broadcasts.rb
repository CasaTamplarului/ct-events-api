# frozen_string_literal: true

class CreateEmailBroadcasts < ActiveRecord::Migration[7.1]
  def change
    create_table :email_broadcasts do |t|
      t.text    :subject,          null: false
      t.text    :body,             null: false
      t.string  :channel,         null: false
      t.bigint  :event_id
      t.bigint  :sent_by_user_id, null: false
      t.integer :recipient_count, null: false, default: 0

      t.timestamps
    end

    add_index :email_broadcasts, :event_id
    add_index :email_broadcasts, :sent_by_user_id

    create_table :email_broadcast_recipients, id: false do |t|
      t.bigint :email_broadcast_id, null: false
      t.bigint :user_id,            null: false
    end

    add_index :email_broadcast_recipients, %i[email_broadcast_id user_id], unique: true,
              name: 'idx_email_broadcast_recipients_unique'
    add_index :email_broadcast_recipients, :user_id, name: 'idx_email_broadcast_recipients_user_id'
  end
end
