# frozen_string_literal: true

module Api
  module V1
    module Scan
      class EventsController < ActionController::API
        include Authenticatable

        before_action :authenticate_user!
        before_action { require_permission!(:can_check_in_attendees) }

        def index
          lang   = current_user.language || 'ro-RO'
          events = Event.upcoming.order(:start_date).includes(:events_translations)
          render json: events.map { |e| serialise_event(e, lang) }
        end

        private

          def serialise_event(event, lang)
            translation = event.events_translations.find { |t| t.languages_code == lang } ||
                          event.events_translations.find { |t| t.languages_code == 'ro-RO' } ||
                          event.events_translations.first
            {
              name: translation&.name,
              slug: event.slug
            }
          end
      end
    end
  end
end
