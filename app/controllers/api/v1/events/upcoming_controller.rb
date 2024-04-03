# frozen_string_literal: true

module Api
  module V1
    module Events
      class UpcomingController < ActionController::API
        def index
          events = Event.upcoming.limit(6)

          render json:
            ThumbnailEventSerializer.new(events, params: { languages_code: params[:languages_code] }).serialize,
                 status: :ok
        end
      end
    end
  end
end
