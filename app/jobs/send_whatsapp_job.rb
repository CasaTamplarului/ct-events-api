# frozen_string_literal: true

class SendWhatsappJob < ApplicationJob
  queue_as :default

  def perform(template_id:, user_ids:, broadcast_id:, event_id: nil, exclude_broadcast_ids: nil)
    template = WhatsappTemplate.find_by(id: template_id)
    unless template
      Rails.logger.error("SendWhatsappJob: WhatsappTemplate #{template_id} not found")
      return
    end

    event      = event_id ? Event.includes(:events_translations).find_by(id: event_id) : nil
    event_name = event&.events_translations&.find { |t| t.languages_code == 'ro-RO' }&.name.to_s

    order_refs      = batch_order_refs(user_ids, event_id)
    excluded_phones = previously_sent_phones(exclude_broadcast_ids)
    sent_recipients = []

    User.where(id: user_ids).where.not(phone_number: [nil, '']).find_each do |user|
      next if excluded_phones.include?(user.phone_number.downcase)

      vars = build_vars(user.first_name.to_s, user.last_name.to_s, user.email.to_s,
                        user.phone_number.to_s, event_name, order_refs[user.id].to_s)
      content_variables = resolve_content_variables(template.variables, vars)

      TwilioService.send_whatsapp(
        to: user.phone_number,
        content_sid: template.content_sid,
        content_variables: content_variables
      )

      sent_recipients << { user_id: user.id, phone_number: user.phone_number.downcase }
    end

    unregistered = if event_id.present?
                     send_to_unregistered_attendees(
                       template, event_name, event_id,
                       sent_recipients.to_set { |r| r[:phone_number] } | excluded_phones
                     )
                   else
                     []
                   end

    record_recipients(broadcast_id, sent_recipients, unregistered)
  end

  private

    def previously_sent_phones(broadcast_ids)
      return Set.new if broadcast_ids.blank?

      WhatsappBroadcastRecipient.where(whatsapp_broadcast_id: Array(broadcast_ids))
                                .pluck(:phone_number)
                                .to_set(&:downcase)
    end

    def send_to_unregistered_attendees(template, event_name, event_id, skip_phones)
      recipients = []

      Attendee.joins(:order)
              .where(event_id: event_id, user_id: nil)
              .where.not(payment_status: Attendee.payment_statuses[:attendee_cancelled])
              .where.not(phone_number: [nil, ''])
              .select('DISTINCT ON (LOWER(attendees.phone_number)) attendees.*, orders.order_reference AS order_ref')
              .order(Arel.sql('LOWER(attendees.phone_number), attendees.id'))
              .each do |attendee|
        next if skip_phones.include?(attendee.phone_number.downcase)

        vars = build_vars(attendee.first_name.to_s, attendee.last_name.to_s,
                          attendee.email_address.to_s, attendee.phone_number.to_s,
                          event_name, attendee.order_ref.to_s)
        content_variables = resolve_content_variables(template.variables, vars)

        TwilioService.send_whatsapp(
          to: attendee.phone_number,
          content_sid: template.content_sid,
          content_variables: content_variables
        )

        recipients << { user_id: nil, phone_number: attendee.phone_number.downcase }
      end

      recipients
    end

    def build_vars(first_name, last_name, email, phone_number, event_name, order_reference)
      {
        'first_name' => first_name,
        'last_name' => last_name,
        'email' => email,
        'phone_number' => phone_number,
        'event_name' => event_name,
        'order_reference' => order_reference
      }
    end

    def resolve_content_variables(variable_definitions, vars)
      variable_definitions.to_h do |vd|
        [vd['position'].to_s, vars.fetch(vd['name'].to_s, '')]
      end
    end

    def record_recipients(broadcast_id, registered, unregistered)
      all = registered + unregistered
      return if all.empty?

      rows = all.map { |r| r.merge(whatsapp_broadcast_id: broadcast_id) }
      WhatsappBroadcastRecipient.insert_all(
        rows,
        unique_by: :idx_whatsapp_broadcast_recipients_broadcast_phone
      )
      WhatsappBroadcast.where(id: broadcast_id).update_all(recipient_count: all.size)
    end

    def batch_order_refs(user_ids, event_id)
      return {} unless event_id

      Attendee
        .joins(:order)
        .where(event_id: event_id, user_id: user_ids)
        .where.not(payment_status: Attendee.payment_statuses[:attendee_cancelled])
        .select('DISTINCT ON (attendees.user_id) attendees.user_id, orders.order_reference')
        .order('attendees.user_id')
        .to_h { |a| [a.user_id, a.order_reference] }
    end
end
