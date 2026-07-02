# frozen_string_literal: true

# Mobile devices can receive push notifications without an account: the
# subscription row then has no user and only gets marketing broadcasts.
class AllowAnonymousPushSubscriptions < ActiveRecord::Migration[8.0]
  def change
    change_column_null :push_subscriptions, :user_id, true
  end
end
