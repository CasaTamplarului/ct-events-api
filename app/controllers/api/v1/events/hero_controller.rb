# frozen_string_literal: true

module Api
  module V1
    module Events
      class HeroController < ActionController::API
        def index
          event = Event.hero.includes(:events_translations, :tickets, :event_gallery_items,
                                          event_description_sections: :event_description_section_translations).first

          return head :no_content if event.nil?

          render json:
            HeroEventSerializer.new(event, params: { languages_code: params[:languages_code] }).serialize,
                 status: :ok
        end
      end
    end
  end
end
