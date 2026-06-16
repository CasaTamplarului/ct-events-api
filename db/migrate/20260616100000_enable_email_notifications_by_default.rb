# frozen_string_literal: true

class EnableEmailNotificationsByDefault < ActiveRecord::Migration[8.1]
  EMAIL_COLUMNS = %w[marketing_emails payment_reminder_emails event_reminder_emails event_update_emails].freeze

  def up
    EMAIL_COLUMNS.each do |col|
      change_column_default :users, col, from: false, to: true
    end

    execute(<<~SQL)
      UPDATE users
      SET marketing_emails = true,
          payment_reminder_emails = true,
          event_reminder_emails = true,
          event_update_emails = true
    SQL
  end

  def down
    EMAIL_COLUMNS.each do |col|
      change_column_default :users, col, from: true, to: false
    end
  end
end
