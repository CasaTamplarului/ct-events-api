# frozen_string_literal: true

class BackfillBroadcast1Recipients < ActiveRecord::Migration[7.1]
  BROADCAST_ID = 1
  EVENT_ID     = 26

  def up
    # Registered users who are non-cancelled attendees of the event
    execute <<~SQL
      INSERT INTO email_broadcast_recipients (email_broadcast_id, user_id, email)
      SELECT DISTINCT #{BROADCAST_ID}, u.id, LOWER(u.email)
      FROM users u
      JOIN attendees a ON a.user_id = u.id
      WHERE a.event_id = #{EVENT_ID}
        AND a.payment_status != 3
        AND u.email IS NOT NULL
        AND u.email != ''
        AND u.deleted_at IS NULL
    SQL

    # Unregistered attendees (no user account) - one row per unique email,
    # skipping any email already inserted from the registered users pass
    execute <<~SQL
      INSERT INTO email_broadcast_recipients (email_broadcast_id, user_id, email)
      SELECT DISTINCT ON (LOWER(a.email_address)) #{BROADCAST_ID}, NULL, LOWER(a.email_address)
      FROM attendees a
      WHERE a.event_id = #{EVENT_ID}
        AND a.user_id IS NULL
        AND a.payment_status != 3
        AND a.email_address IS NOT NULL
        AND a.email_address != ''
        AND NOT EXISTS (
          SELECT 1 FROM email_broadcast_recipients r
          WHERE r.email_broadcast_id = #{BROADCAST_ID}
            AND LOWER(r.email) = LOWER(a.email_address)
        )
      ORDER BY LOWER(a.email_address), a.id
    SQL

    # Update recipient_count
    count = execute("SELECT COUNT(*) FROM email_broadcast_recipients WHERE email_broadcast_id = #{BROADCAST_ID}").first['count'].to_i
    execute("UPDATE email_broadcasts SET recipient_count = #{count} WHERE id = #{BROADCAST_ID}")
  end

  def down
    execute("DELETE FROM email_broadcast_recipients WHERE email_broadcast_id = #{BROADCAST_ID}")
    execute("UPDATE email_broadcasts SET recipient_count = 0 WHERE id = #{BROADCAST_ID}")
  end
end
