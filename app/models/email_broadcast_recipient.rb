# frozen_string_literal: true

class EmailBroadcastRecipient < ApplicationRecord
  self.primary_key = nil

  belongs_to :email_broadcast
  belongs_to :user
end
