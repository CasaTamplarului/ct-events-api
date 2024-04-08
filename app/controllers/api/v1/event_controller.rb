# frozen_string_literal: true

module Api
  module V1
    class EventController < ActionController::API
      def show
        event = Event.hero.first

        render json:
          EventSerializer.new(event, params: { languages_code: params[:languages_code] }).serialize,
               status: :ok
      end
    end
  end
end
