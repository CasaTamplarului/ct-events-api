# frozen_string_literal: true

class SendPasswordResetJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 10.seconds, attempts: 3

  def perform(user_id, reset_url)
    user = User.find_by(id: user_id)
    return unless user

    SendgridService.send_password_reset(user: user, reset_url: reset_url)
  end
end
