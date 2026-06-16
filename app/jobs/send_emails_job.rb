# frozen_string_literal: true

class SendEmailsJob < ApplicationJob
  queue_as :default

  VALID_CHANNELS = EmailUnsubscribeTokenService::PREFERENCE_COLUMNS.freeze

  def perform(subject:, body:, channel:, user_ids:)
    return unless VALID_CHANNELS.include?(channel)

    User.where(id: user_ids, channel => true).find_each do |user|
      next if user.email.blank?

      AdminMailer.with(to: user.email, subject: subject, body: body).send_email.deliver_now
    end
  end
end
