# frozen_string_literal: true

module ScanSerialisable
  private

    def serialise_order(order)
      attendees = if order.association(:attendees).loaded?
                    order.attendees.sort_by(&:id)
                  else
                    order.attendees
                         .includes(:checked_in_by, :meal_stamps,
                                   ticket: [:tickets_translations, :ticket_meal_slots])
                         .order(:id)
                  end
      {
        order_reference: order.order_reference,
        payment_status:  order.payment_status(attendees),
        attendees:       attendees.map { |a| serialise_attendee(a) }
      }
    end

    def serialise_attendee(attendee)
      by = attendee.checked_in_by
      {
        id:             attendee.id,
        first_name:     attendee.first_name,
        last_name:      attendee.last_name,
        email_address:  attendee.email_address,
        age:            attendee.age,
        ticket_name:    attendee.ticket
                        &.tickets_translations
                                &.find { |t| t.languages_code == 'ro-RO' }
                                &.name,
        ticket_price:   attendee.ticket&.price,
        valid_from:     attendee.ticket&.valid_from,
        valid_to:       attendee.ticket&.valid_to,
        payment_status:     attendee.payment_status,
        checked_in:         attendee.checked_in,
        checked_in_at:      attendee.checked_in_at,
        checked_in_by:      by ? "#{by.first_name} #{by.last_name}".strip : nil,
        dietary_preference: attendee.dietary_preference,
        allergies:          attendee.allergies,
        meal_slots:     serialise_meal_slots(attendee)
      }
    end

    def serialise_meal_slots(attendee)
      slots = attendee.ticket&.ticket_meal_slots || []
      slots.sort_by { |s| [s.occurs_on, s.sort || 0] }.map do |slot|
        stamp_count = attendee.meal_stamps.count { |s| s.ticket_meal_slot_id == slot.id }
        { id: slot.id, meal_type: slot.meal_type, occurs_on: slot.occurs_on, sort: slot.sort,
          stamp_count: stamp_count }
      end
    end
end
