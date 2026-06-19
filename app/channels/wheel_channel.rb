# frozen_string_literal: true

class WheelChannel < ApplicationCable::Channel
  def subscribed
    reject unless current_user.can?(:can_check_in_attendees)

    event_id = params[:event_id].to_i
    reject unless event_id.positive?

    stream_from "wheel_event_#{event_id}"
  end
end
