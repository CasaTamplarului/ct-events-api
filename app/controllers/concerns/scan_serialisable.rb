# frozen_string_literal: true

module ScanSerialisable
  private

    def serialise_order(order)
      attendees = order.attendees
                       .includes(:checked_in_by, ticket: :tickets_translations)
                       .order(:id)
      {
        order_reference: order.order_reference,
        payment_status: order.payment_status,
        attendees: attendees.map { |a| serialise_attendee(a) }
      }
    end

    def serialise_attendee(attendee)
      by = attendee.checked_in_by
      {
        id: attendee.id,
        first_name: attendee.first_name,
        last_name: attendee.last_name,
        email_address: attendee.email_address,
        ticket_name: attendee.ticket
                     &.tickets_translations
                             &.find { |t| t.languages_code == 'ro-RO' }
                             &.name,
        checked_in: attendee.checked_in,
        checked_in_at: attendee.checked_in_at,
        checked_in_by: by ? "#{by.first_name} #{by.last_name}".strip : nil
      }
    end
end
