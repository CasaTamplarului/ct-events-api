# frozen_string_literal: true

class SendEmailsJob < ApplicationJob
  queue_as :default

  VALID_CHANNELS = EmailUnsubscribeTokenService::PREFERENCE_COLUMNS.freeze

  VARIABLE_KEYS = %w[first_name last_name email event_name order_reference unsubscribe_url].freeze

  def perform(subject:, body:, channel:, user_ids:, broadcast_id:, event_id: nil)
    return unless VALID_CHANNELS.include?(channel)

    event = event_id ? Event.includes(:events_translations).find_by(id: event_id) : nil
    event_name = event&.events_translations&.find { |t| t.languages_code == 'ro-RO' }&.name.to_s

    order_refs = batch_order_refs(user_ids, event_id)
    api_base   = ENV['API_BASE_URL']&.chomp('/')

    sent_user_ids = []

    User.where(id: user_ids, channel => true).find_each do |user|
      next if user.email.blank?

      token           = EmailUnsubscribeTokenService.generate(user: user, type: channel)
      unsubscribe_url = api_base ? "#{api_base}/api/v1/unsubscribe?token=#{token}" : ''

      vars = {
        'first_name'       => user.first_name.to_s,
        'last_name'        => user.last_name.to_s,
        'email'            => user.email.to_s,
        'event_name'       => event_name,
        'order_reference'  => order_refs[user.id].to_s,
        'unsubscribe_url'  => unsubscribe_url
      }

      SendgridService.send_broadcast(
        to:              user.email,
        subject:         substitute(subject, vars),
        body_html:       substitute(body, vars),
        unsubscribe_url: unsubscribe_url
      )

      sent_user_ids << user.id
    end

    record_recipients(broadcast_id, sent_user_ids)
  end

  private

    def record_recipients(broadcast_id, user_ids)
      return if user_ids.empty?

      rows = user_ids.map { |uid| { email_broadcast_id: broadcast_id, user_id: uid } }
      EmailBroadcastRecipient.insert_all(rows)
      EmailBroadcast.where(id: broadcast_id).update_all(recipient_count: user_ids.size)
    end

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
