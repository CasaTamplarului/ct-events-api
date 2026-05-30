# frozen_string_literal: true

module Api
  module V1
    module Events
      class PastController < ActionController::API
        def index
          events = Event.past.order(start_date: :desc).limit(10)

          render json:
            ThumbnailEventSerializer.new(events,
                                         params: { languages_code: params[:languages_code],
                                                   show_price: false }).serialize,
                 status: :ok
        end
      end
    end
  end
end
