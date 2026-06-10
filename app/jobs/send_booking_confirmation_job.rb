# frozen_string_literal: true

class SendBookingConfirmationJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 10.seconds, attempts: 3

  def perform(order_id, language)
    order = Order.find_by(id: order_id)
    return unless order

    SendgridService.send_booking_confirmation(order: order, language: language)
  end
end
