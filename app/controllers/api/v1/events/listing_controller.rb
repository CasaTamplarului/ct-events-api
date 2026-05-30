# frozen_string_literal: true

module Api
  module V1
    module Events
      class ListingController < ActionController::API
        VALID_FILTERS  = %w[all upcoming past].freeze
        VALID_PRICINGS = %w[both free paid].freeze
        DEFAULT_PER_PAGE = 12
        MAX_PER_PAGE     = 100

        def index
          scope = Event
                  .by_filter(filter_param)
                  .by_keyword(params[:search], params[:languages_code])
                  .by_year(params[:year])
                  .by_pricing(pricing_param)
                  .distinct
                  .sorted_for(filter_param)

          total_count = Event.where(id: scope.unscope(:order).select('events.id')).count
          per_page    = per_page_param
          page        = page_param
          total_pages = [(total_count.to_f / per_page).ceil, 1].max

          events = scope.limit(per_page).offset((page - 1) * per_page)

          render json: {
            events: ThumbnailEventSerializer.new(
              events,
              params: { languages_code: params[:languages_code] }
            ).serializable_hash,
            meta: {
              current_page: page,
              total_pages: total_pages,
              total_count: total_count,
              per_page: per_page
            }
          }
        end

        private

          def filter_param
            VALID_FILTERS.include?(params[:filter].to_s) ? params[:filter].to_s : 'all'
          end

          def pricing_param
            VALID_PRICINGS.include?(params[:pricing].to_s) ? params[:pricing].to_s : 'both'
          end

          def per_page_param
            (params[:per_page] || DEFAULT_PER_PAGE).to_i.clamp(1, MAX_PER_PAGE)
          end

          def page_param
            [(params[:page] || 1).to_i, 1].max
          end
      end
    end
  end
end
