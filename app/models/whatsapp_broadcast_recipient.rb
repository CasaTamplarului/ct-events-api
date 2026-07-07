# frozen_string_literal: true

class WhatsappBroadcastRecipient < ApplicationRecord
  self.primary_key = nil

  belongs_to :whatsapp_broadcast
  belongs_to :user, optional: true
end
