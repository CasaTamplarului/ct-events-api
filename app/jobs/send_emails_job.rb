# frozen_string_literal: true

class SendEmailsJob < ApplicationJob
  queue_as :default

  VALID_CHANNELS = EmailUnsubscribeTokenService::PREFERENCE_COLUMNS.freeze

  VARIABLE_KEYS = %w[first_name last_name email event_name order_reference].freeze

  def perform(subject:, body:, channel:, user_ids:, broadcast_id:, event_id: nil,
              subject_en: nil, body_en: nil, exclude_broadcast_ids: nil)
    return unless VALID_CHANNELS.include?(channel)

    broadcast     = EmailBroadcast.find(broadcast_id)
    encoded_blobs = broadcast.attachments.blobs.filter_map do |b|
      { content: Base64.strict_encode64(b.download), type: b.content_type, filename: b.filename.to_s }
    rescue StandardError => e
      Rails.logger.error("Failed to download attachment blob #{b.id}: #{e.message}")
      nil
    end
    attach_urls = broadcast.attachment_urls

    event      = event_id ? Event.includes(:events_translations).find_by(id: event_id) : nil
    event_name = event&.events_translations&.find { |t| t.languages_code == 'ro-RO' }&.name.to_s

    order_refs = batch_order_refs(user_ids, event_id)
    api_base   = ENV['API_BASE_URL']&.chomp('/')
    excluded_emails = previously_sent_emails(exclude_broadcast_ids)

    sent_recipients = []

    User.where(id: user_ids, channel => true).find_each do |user|
      next if user.email.blank?
      next if excluded_emails.include?(user.email.downcase)

      romanian = user.language.to_s.start_with?('ro') || user.language.blank?
      subj     = localize(subject, subject_en, romanian)
      bod      = localize(body,    body_en,    romanian)

      token           = EmailUnsubscribeTokenService.generate(user: user, type: channel)
      unsubscribe_url = api_base ? "#{api_base}/api/v1/unsubscribe?token=#{token}" : ''

      vars = {
        'first_name' => user.first_name.to_s,
        'last_name' => user.last_name.to_s,
        'email' => user.email.to_s,
        'event_name' => event_name,
        'order_reference' => order_refs[user.id].to_s
      }

      SendgridService.send_broadcast(
        to: user.email,
        subject: substitute(subj, vars),
        body_html: substitute(bod, vars),
        unsubscribe_url: unsubscribe_url,
        is_romanian: romanian,
        attachments: encoded_blobs,
        attachment_urls: attach_urls
      )

      sent_recipients << { user_id: user.id, email: user.email.downcase }
    end

    unregistered_recipients = if event_id.present?
                                send_to_unregistered_attendees(
                                  subject, body, event_name, event_id, api_base,
                                  sent_recipients.map { |r| r[:email] }.to_set | excluded_emails,
                                  encoded_blobs, attach_urls
                                )
                              else
                                []
                              end

    record_recipients(broadcast_id, sent_recipients, unregistered_recipients)
  end

  private

    def previously_sent_emails(broadcast_ids)
      return Set.new if broadcast_ids.blank?

      EmailBroadcastRecipient.where(email_broadcast_id: Array(broadcast_ids))
                             .pluck(:email)
                             .map(&:downcase)
                             .to_set
    end

    def localize(ro_version, en_version, romanian)
      romanian || en_version.blank? ? ro_version : en_version
    end

    def send_to_unregistered_attendees(subject, body, event_name, event_id, _api_base, skip_emails,
                                       encoded_blobs = [], attach_urls = [])
      recipients = []

      Attendee.joins(:order)
              .where(event_id: event_id, user_id: nil)
              .where.not(payment_status: Attendee.payment_statuses[:attendee_cancelled])
              .where.not(email_address: [nil, ''])
              .select('DISTINCT ON (LOWER(attendees.email_address)) attendees.*, orders.order_reference AS order_ref')
              .order(Arel.sql('LOWER(attendees.email_address), attendees.id'))
              .each do |attendee|
        next if skip_emails.include?(attendee.email_address.downcase)

        vars = {
          'first_name' => attendee.first_name.to_s,
          'last_name' => attendee.last_name.to_s,
          'email' => attendee.email_address.to_s,
          'event_name' => event_name,
          'order_reference' => attendee.order_ref.to_s
        }

        SendgridService.send_broadcast(
          to: attendee.email_address,
          subject: substitute(subject, vars),
          body_html: substitute(body, vars),
          is_romanian: true,
          attachments: encoded_blobs,
          attachment_urls: attach_urls
        )

        recipients << { user_id: nil, email: attendee.email_address.downcase }
      end

      recipients
    end

    def record_recipients(broadcast_id, registered, unregistered)
      all = registered + unregistered
      return if all.empty?

      rows = all.map { |r| r.merge(email_broadcast_id: broadcast_id) }
      EmailBroadcastRecipient.insert_all(rows, unique_by: :idx_email_broadcast_recipients_broadcast_email)
      EmailBroadcast.where(id: broadcast_id).update_all(recipient_count: all.size)
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
