# frozen_string_literal: true

class EmailBroadcast < ApplicationRecord
  belongs_to :event, optional: true
  belongs_to :sent_by_user, class_name: 'User', foreign_key: :sent_by_user_id

  has_many :email_broadcast_recipients, dependent: :delete_all
  has_many :recipient_users, through: :email_broadcast_recipients, source: :user
  has_many_attached :attachments
end
