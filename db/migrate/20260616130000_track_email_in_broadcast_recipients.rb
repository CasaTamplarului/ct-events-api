# frozen_string_literal: true

class TrackEmailInBroadcastRecipients < ActiveRecord::Migration[7.1]
  def change
    remove_index :email_broadcast_recipients, name: 'idx_email_broadcast_recipients_unique'
    remove_index :email_broadcast_recipients, name: 'idx_email_broadcast_recipients_user_id'

    add_column :email_broadcast_recipients, :email, :string, null: false, default: ''
    change_column_null :email_broadcast_recipients, :user_id, true

    execute <<~SQL
      CREATE UNIQUE INDEX idx_email_broadcast_recipients_broadcast_email
        ON email_broadcast_recipients (email_broadcast_id, LOWER(email))
    SQL

    add_index :email_broadcast_recipients, :user_id,
              where: 'user_id IS NOT NULL',
              name: 'idx_email_broadcast_recipients_user_id'
  end
end
