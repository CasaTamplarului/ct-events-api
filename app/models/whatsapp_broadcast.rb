# frozen_string_literal: true

class WhatsappBroadcast < ApplicationRecord
  belongs_to :whatsapp_template
  belongs_to :event, optional: true
  belongs_to :sent_by_user, class_name: 'User'

  has_many :whatsapp_broadcast_recipients, dependent: :delete_all
end
