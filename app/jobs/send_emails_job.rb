# frozen_string_literal: true

class SendEmailsJob < ApplicationJob
  queue_as :default

  VALID_CHANNELS = EmailUnsubscribeTokenService::PREFERENCE_COLUMNS.freeze

  VARIABLE_KEYS = %w[first_name last_name email event_name order_reference].freeze

  def perform(subject:, body:, channel:, user_ids:, event_id: nil)
    return unless VALID_CHANNELS.include?(channel)

    event = event_id ? Event.includes(:events_translations).find_by(id: event_id) : nil
    event_name = event&.events_translations&.find { |t| t.languages_code == 'ro-RO' }&.name.to_s

    order_refs = batch_order_refs(user_ids, event_id)

    User.where(id: user_ids, channel => true).find_each do |user|
      next if user.email.blank?

      vars = {
        'first_name'       => user.first_name.to_s,
        'last_name'        => user.last_name.to_s,
        'email'            => user.email.to_s,
        'event_name'       => event_name,
        'order_reference'  => order_refs[user.id].to_s
      }

      AdminMailer.with(
        to:      user.email,
        subject: substitute(subject, vars),
        body:    substitute(body, vars)
      ).send_email.deliver_now
    end
  end

  private

    def substitute(text, variables)
      variables.reduce(text) { |t, (k, v)| t.gsub("{{#{k}}}", v) }
    end

    def batch_order_refs(user_ids, event_id)
      return {} unless event_id

      Attendee
        .joins(:order)
        .where(event_id: event_id, user_id: user_ids)
        .where.not(payment_status: Attendee.payment_statuses[:attendee_cancelled])
        .select('DISTINCT ON (attendees.user_id) attendees.user_id, orders.order_reference')
        .order('attendees.user_id')
        .each_with_object({}) { |a, h| h[a.user_id] = a.order_reference }
    end
end
