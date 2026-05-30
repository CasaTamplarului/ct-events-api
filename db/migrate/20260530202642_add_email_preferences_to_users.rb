# frozen_string_literal: true

class AddEmailPreferencesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :marketing_emails,         :boolean, null: false, default: false
    add_column :users, :payment_reminder_emails,  :boolean, null: false, default: false
    add_column :users, :payment_receipt_emails,   :boolean, null: false, default: false
    add_column :users, :event_reminder_emails,    :boolean, null: false, default: false
    add_column :users, :event_update_emails,      :boolean, null: false, default: false
  end
end
