# frozen_string_literal: true

class TrackEmailInBroadcastRecipients < ActiveRecord::Migration[7.1]
  def up
    remove_index :email_broadcast_recipients, name: 'idx_email_broadcast_recipients_unique'
    remove_index :email_broadcast_recipients, name: 'idx_email_broadcast_recipients_user_id'

    add_column :email_broadcast_recipients, :email, :string
    change_column_null :email_broadcast_recipients, :user_id, true

    execute <<~SQL
      UPDATE email_broadcast_recipients r
      SET email = LOWER(u.email)
      FROM users u
      WHERE r.user_id = u.id
        AND u.email IS NOT NULL
        AND u.email != ''
    SQL

    execute <<~SQL
      DELETE FROM email_broadcast_recipients
      WHERE email IS NULL OR email = ''
    SQL

    change_column_null :email_broadcast_recipients, :email, false

    execute <<~SQL
      CREATE UNIQUE INDEX idx_email_broadcast_recipients_broadcast_email
        ON email_broadcast_recipients (email_broadcast_id, LOWER(email))
    SQL

    add_index :email_broadcast_recipients, :user_id,
              where: 'user_id IS NOT NULL',
              name: 'idx_email_broadcast_recipients_user_id'
  end

  def down
    remove_index :email_broadcast_recipients, name: 'idx_email_broadcast_recipients_broadcast_email'
    remove_index :email_broadcast_recipients, name: 'idx_email_broadcast_recipients_user_id'
    remove_column :email_broadcast_recipients, :email
    change_column_null :email_broadcast_recipients, :user_id, false

    add_index :email_broadcast_recipients, %i[email_broadcast_id user_id], unique: true,
              name: 'idx_email_broadcast_recipients_unique'
    add_index :email_broadcast_recipients, :user_id,
              name: 'idx_email_broadcast_recipients_user_id'
  end
end
