# frozen_string_literal: true

class SendCancellationAlertJob < ApplicationJob
  queue_as :default

  REASON_LABELS = {
    'cant_attend' => 'Nu pot participa',
    'health' => 'Motive de sănătate',
    'financial' => 'Motive financiare',
    'plans_changed' => 'Schimbare de planuri',
    'other' => 'Altele'
  }.freeze

  def perform(attendee_id:)
    attendee = Attendee.includes(event: :events_translations).find_by(id: attendee_id)
    return unless attendee

    event_name   = attendee.event
                           .events_translations
                           .find { |t| t.languages_code == 'ro-RO' }
                           &.name
                           .to_s
    reason_label = REASON_LABELS[attendee.cancellation_reason] || 'Nespecificat'

    title = "Anulare bilet — #{event_name}"
    body  = "#{attendee.first_name} #{attendee.last_name} și-a anulat locul. Motiv: #{reason_label}"

    User.where(role: 'admin').find_each do |admin|
      FcmService.send_to_user(
        user: admin,
        title: title,
        body: body,
        link: nil,
        image: nil,
        actions: [],
        preference: nil
      )
    end
  end
end
