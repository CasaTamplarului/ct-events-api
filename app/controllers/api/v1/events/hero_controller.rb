# frozen_string_literal: true

module Api
  module V1
    module Events
      class HeroController < ActionController::API
        def index
          event = Event.hero.first

          render json:
            HeroEventSerializer.new(event, params: { languages_code: params[:languages_code] }).serialize,
                 status: :ok
        end
      end
    end
  end
end
