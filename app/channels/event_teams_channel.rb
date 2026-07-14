# frozen_string_literal: true

class EventTeamsChannel < ApplicationCable::Channel
  def subscribed
    event_slug = params[:event_slug].to_s.strip
    return reject if event_slug.blank?
    return reject unless Event.exists?(slug: event_slug)
    return reject unless current_user&.can?(:can_manage_teams)

    stream_from "event_teams_#{event_slug}"
  end
end
