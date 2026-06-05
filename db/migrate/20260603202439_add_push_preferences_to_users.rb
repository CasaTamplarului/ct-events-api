class AddPushPreferencesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :marketing_push,         :boolean, null: false, default: true
    add_column :users, :payment_reminder_push,  :boolean, null: false, default: true
    add_column :users, :event_reminder_push,    :boolean, null: false, default: true
    add_column :users, :event_update_push,      :boolean, null: false, default: true
  end
end
