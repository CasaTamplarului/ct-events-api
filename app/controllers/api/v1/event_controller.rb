# frozen_string_literal: true

module Api
  module V1
    class EventController < ActionController::API
      def show
        event = EventsTranslation.find_by(slug: params[:slug]).event

        render json:
          EventSerializer.new(event, params: { languages_code: params[:languages_code] }).serialize,
               status: :ok
      end
    end
  end
end
