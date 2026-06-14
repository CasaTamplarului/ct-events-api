# frozen_string_literal: true

module Api
  module V1
    class EventController < ActionController::API
      include Authenticatable

      def show
        try_authenticate_user

        event = Event
                .includes(:events_translations, :attendees, :event_attendee_fields, :event_gallery_items,
                          tickets: %i[tickets_translations ticket_meal_slots ticket_allowed_users],
                          event_speakers: :event_speakers_translations,
                          event_description_sections: :event_description_section_translations)
                .find_by!(slug: params[:slug])

        if event.is_private && params[:token] != event.access_token.to_s
          return render json: { error: I18n.t('errors.not_found') }, status: :not_found
        end

        render json:
          EventSerializer.new(event, params: { languages_code: params[:languages_code],
                                               current_user: current_user }).serialize,
               status: :ok
      end
    end
  end
end
