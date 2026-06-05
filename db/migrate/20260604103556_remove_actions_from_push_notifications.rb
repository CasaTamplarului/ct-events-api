# frozen_string_literal: true

class RemoveActionsFromPushNotifications < ActiveRecord::Migration[8.1]
  def change
    remove_column :push_notifications, :actions, :jsonb, null: false, default: []
  end
end
